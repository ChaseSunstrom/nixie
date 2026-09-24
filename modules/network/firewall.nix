# One nftables ruleset for the host: default-drop inbound, guests kept away
# from the host's own services, and the egress policy. Per-guest chains are
# keyed on the veth port in the bridge family, where the port name is
# visible; the egress policy itself is enforced where routed traffic passes,
# the L3 forward hook, keyed on the bridge.
{
  config,
  lib,
  ...
}:
let
  inherit (import ../../lib/option.nix lib) mkOption;
  net = config.nixie.network;
  fw = net.firewall;
  guests = lib.attrValues config.nixie.guests;
  br = net.bridge.name;
  exitNode = net.egress == "exit-node";
  nat = net.bridge.mode == "managed-nat";
  lanIf = if nat then "uplink*" else br;
  tailnetIf = "tailscale0";
  uiPort = toString config.nixie.incus.ui.port;
  sshPort = toString (lib.head config.services.openssh.ports);
  hostUiPort = toString config.nixie.hostUi.port;
  promPort = toString config.nixie.monitoring.port;
  hostPorts = "${sshPort}, ${uiPort}, ${hostUiPort}, ${promPort}";
  # The one host service the guests are meant to reach: the images this
  # machine keeps for them (modules/data.nix).
  registryOn = config.nixie.data.registry.enable;
  registryPort = toString config.nixie.data.registry.port;
  onTailnet = config.nixie.network.tailscale.enable;
  private = "{ 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 }";

  # Under exits (modules/network/exits.nix) a guest leaves through a tunnel
  # and, by option, to the LAN; only a scope whose list is "direct" uses the
  # uplinks. Without exits, the uplinks.
  marks = net.egressMarks;
  directScopes = lib.filter (n: marks ? ${n}) (
    lib.optional (net.guestEgress == [ ] && !exitNode) "guests"
    ++ map (g: "guest-${g.name}") (lib.filter (g: g.egress == "direct") guests)
  );
  egressRules =
    if marks != { } then
      ''
        iifname "${br}" oifname "wg-*" accept
        iifname "${br}" oifname "${tailnetIf}" accept
        ${lib.concatMapStringsSep "\n" (
          n: ''iifname "${br}" oifname "uplink*" meta mark ${toString marks.${n}} accept''
        ) directScopes}
        ${lib.optionalString net.exitNodeAllowLan ''iifname "${br}" oifname "uplink*" ip daddr ${private} accept''}
        iifname "${br}" drop
      ''
    else
      ''iifname "${br}" oifname "uplink*" accept'';
  # Each guest's port marks its traffic with its egress scope.
  markRules = lib.optionalString (marks != { }) ''
    chain prerouting {
      type filter hook prerouting priority filter; policy accept;
      ${lib.concatMapStringsSep "\n" (
        g:
        lib.optionalString (marks ? "guest-${g.name}")
          ''iifname "veth-${g.name}" meta mark set ${toString marks."guest-${g.name}"}''
      ) guests}
      iifname "veth*" meta mark 0 meta mark set ${toString marks.guests}
    }
  '';
  torExits = lib.filterAttrs (_: e: e.type == "tor") net.exits;

  # Per-guest rules a site may extend; empty means the guest is treated like
  # every other one. The undeclared chain catches any other veth.
  guestChain = g: ''
    chain guest-${g.name} {
      ${g.firewall}
      accept
    }
  '';

  # Ports a guest exposes to the LAN reach it through the host's forward path
  # (NAT mode) or straight over the bridge (LAN mode); either way the host
  # itself is never the destination.
  exposeRules = lib.concatMapStringsSep "\n" (
    g:
    lib.optionalString (g.expose.lan != [ ] && g.ip != "auto") ''
      iifname "${lanIf}" ip daddr ${lib.head (lib.splitString "/" g.ip)} tcp dport { ${
        lib.concatMapStringsSep ", " toString g.expose.lan
      } } accept
    ''
  ) guests;

in
{
  options.nixie.network.firewall = {
    lanInterface = mkOption {
      type = lib.types.str;
      default = lanIf;
      readOnly = true;
      internal = true;
      description = "Internal: the nftables interface pattern LAN traffic arrives on (the bridge, or the uplinks under NAT).";
    };
    extraInputRules = mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra nftables rules for the host's input chain, for a site's own needs.";
    };
    extraForwardRules = mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra nftables rules for the forward chain, for a site's own needs.";
    };
  };

  config = lib.mkIf config.nixie.incus.enable {
    networking.firewall.enable = false;
    networking.nftables.enable = true;
    networking.nftables.tables = {
      nixie = {
        family = "inet";
        content = ''
          chain input {
            type filter hook input priority filter; policy drop;
            iifname "lo" accept
            ct state established,related accept
            ct state invalid drop
            ip protocol icmp accept
            ip6 nexthdr icmpv6 accept
            # Guests never reach the host's own services. Under NAT the bridge
            # carries only guests; in LAN mode it is also the LAN, and this
            # rule dropped the LAN's SSH and control panel with the guests', so
            # there the bridge family below does it, where a guest's port shows.
            # The image registry is for the guests: it is the one host
            # service they are meant to reach, so it goes above the drop.
            ${lib.optionalString registryOn ''iifname "${br}" tcp dport ${registryPort} accept''}
            ${lib.optionalString nat ''iifname "${br}" tcp dport { ${hostPorts} } drop''}
            ${lib.optionalString nat ''
              iifname "${br}" udp dport { 67, 53 } accept
              iifname "${br}" tcp dport 53 accept
            ''}
            iifname "${lanIf}" tcp dport ${sshPort} accept
            ${lib.optionalString onTailnet ''iifname "${tailnetIf}" tcp dport ${sshPort} accept''}
            ${lib.optionalString (
              config.nixie.incus.ui.listen == "lan+tailnet"
            ) ''iifname "${lanIf}" tcp dport { ${uiPort}, ${promPort} } accept''}
            ${lib.optionalString onTailnet ''iifname "${tailnetIf}" tcp dport { ${uiPort}, ${promPort} } accept''}
            ${lib.optionalString (
              config.nixie.hostUi.enable && config.nixie.hostUi.listen == "lan+tailnet"
            ) ''iifname "${lanIf}" tcp dport ${hostUiPort} accept''}
            ${lib.optionalString (
              config.nixie.hostUi.enable && onTailnet
            ) ''iifname "${tailnetIf}" tcp dport ${hostUiPort} accept''}
            ${lib.optionalString onTailnet "udp dport 41641 accept"}
            # Guests on a Tor exit reach it here after the redirect.
            ${lib.optionalString (torExits != { }) ''
              iifname "${br}" tcp dport 9041-9099 accept
              iifname "${br}" udp dport 5351-5399 accept
            ''}
            ${fw.extraInputRules}
          }
          chain forward {
            type filter hook forward priority filter; policy drop;
            ct state established,related accept
            ct state invalid drop
            ${exposeRules}
            ${egressRules}
            ${lib.optionalString (!nat) ''iifname "${br}" oifname "${br}" accept''}
            ${fw.extraForwardRules}
          }
          chain output {
            type filter hook output priority filter; policy accept;
          }
        '';
      };
      # Frames from a guest port pass its own chain before anything else; the
      # catch-all handles instances the site does not declare, whose ports
      # Incus names veth<hex>, without the dash declared ones get.
      nixie-guests = {
        family = "bridge";
        content = ''
          chain input {
            type filter hook input priority filter; policy accept;
            iifname "veth*" tcp dport { ${hostPorts} } drop
            ${lib.concatMapStringsSep "\n" (g: ''iifname "veth-${g.name}" jump guest-${g.name}'') guests}
            iifname "veth*" jump guest-undeclared
          }
          chain forward {
            type filter hook forward priority filter; policy accept;
            ${lib.concatMapStringsSep "\n" (g: ''iifname "veth-${g.name}" jump guest-${g.name}'') guests}
            iifname "veth*" jump guest-undeclared
          }
          ${lib.concatMapStringsSep "\n" guestChain guests}
          chain guest-undeclared {
            accept
          }
          ${markRules}
        '';
      };
    };
  };
}
