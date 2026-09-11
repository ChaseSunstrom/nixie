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
  onTailnet = config.nixie.network.tailscale.enable;
  private = "{ 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 }";

  # Under exit-node the only way out is the tunnel and, by option, the LAN;
  # otherwise the uplinks.
  egressRules =
    if exitNode then
      ''
        iifname "${br}" oifname "${tailnetIf}" accept
        ${lib.optionalString net.exitNodeAllowLan ''iifname "${br}" oifname "uplink*" ip daddr ${private} accept''}
        iifname "${br}" drop
      ''
    else
      ''iifname "${br}" oifname "uplink*" accept'';

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
            # Guests never reach the host's own services.
            iifname "${br}" tcp dport { ${sshPort}, ${uiPort}, ${hostUiPort}, ${promPort} } drop
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
      # catch-all handles instances the site does not declare.
      nixie-guests = {
        family = "bridge";
        content = ''
          chain input {
            type filter hook input priority filter; policy accept;
            ${lib.concatMapStringsSep "\n" (g: ''iifname "veth-${g.name}" jump guest-${g.name}'') guests}
            iifname "veth-*" jump guest-undeclared
          }
          chain forward {
            type filter hook forward priority filter; policy accept;
            ${lib.concatMapStringsSep "\n" (g: ''iifname "veth-${g.name}" jump guest-${g.name}'') guests}
            iifname "veth-*" jump guest-undeclared
          }
          ${lib.concatMapStringsSep "\n" guestChain guests}
          chain guest-undeclared {
            accept
          }
        '';
      };
    };
  };
}
