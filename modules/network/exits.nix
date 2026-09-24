# Egress through named exits (ARCHITECTURE 4.12): tailnet exit nodes,
# WireGuard providers, NordVPN, and Tor behind any of them. Every scope -- the
# guests' default, a guest with its own list, the machine itself, tailnet
# devices using this one as their exit, each Tor instance -- carries a
# firewall mark, and a rule per mark points it at the table of the exit it
# currently uses; behind every such rule is a blackhole, so a scope with no
# working exit is cut off rather than let out directly. nixie-egress picks the
# exit per scope.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../../lib/option.nix lib) mkOption;
  t = lib.types;
  net = config.nixie.network;
  # The old single exit node is an exit list of one.
  legacy = net.egress == "exit-node" && net.exitNode != "";
  allExits =
    lib.mapAttrs (_: e: {
      inherit (e)
        type
        node
        configFile
        tokenFile
        country
        via
        ;
    }) net.exits
    // lib.optionalAttrs legacy {
      exit-node = {
        type = "tailnet";
        node = net.exitNode;
        configFile = null;
        tokenFile = null;
        country = null;
        via = null;
      };
    };
  torExits = lib.filterAttrs (_: e: e.type == "tor") allExits;
  tunnels = lib.filterAttrs (_: e: e.type == "wireguard" || e.type == "nordvpn") allExits;
  exitIndex = lib.listToAttrs (lib.imap1 (i: n: lib.nameValuePair n i) (lib.attrNames allExits));
  guestDefault = if net.guestEgress != [ ] then net.guestEgress else lib.optional legacy "exit-node";
  incus = config.nixie.incus.enable;
  ownLists = lib.filter (g: incus && g.egress != null) (lib.attrValues config.nixie.guests);
  # Scopes, each with the mark its traffic carries and its list of exits;
  # a list of [ ] is "direct".
  scopes = lib.imap0 (i: s: s // { mark = 20032 + i; }) (
    [
      {
        name = "host";
        list = net.hostEgress;
      }
    ]
    ++ lib.optional incus {
      name = "guests";
      list = guestDefault;
    }
    ++ lib.optional (net.tailscale.advertiseExit != null) {
      name = "tailnet-clients";
      list = [ net.tailscale.advertiseExit ];
    }
    ++ map (g: {
      name = "guest-${g.name}";
      list = if g.egress == "direct" then [ ] else g.egress;
    }) ownLists
    # Tor's own connections go out through the exit it names.
    ++ lib.mapAttrsToList (n: e: {
      name = "tor-${n}";
      list = lib.optional (e.via != null) e.via;
    }) torExits
  );
  markOf = n: toString (lib.findFirst (s: s.name == n) { mark = 0; } scopes).mark;
  used = lib.unique (lib.concatMap (s: s.list) scopes);
  on = used != [ ] || net.tailscale.advertiseExit != null;
  wgMark = 19967; # 0x4dff: a tunnel's own packets and the exits' requests, which leave directly
  settings = pkgs.writeText "nixie-egress.json" (
    builtins.toJSON {
      inherit wgMark;
      table0 = 4200;
      allowLan = net.exitNodeAllowLan;
      inherit (net) nordApi;
      exits = lib.mapAttrs (n: e: {
        inherit (e) type via node;
        table = 4200 + exitIndex.${n};
        iface = "wg-${n}";
        configFile = if e.configFile == null then "" else toString e.configFile;
        tokenFile = if e.tokenFile == null then "" else toString e.tokenFile;
        country = if e.country == null then "" else e.country;
        transPort = 9040 + exitIndex.${n};
        dnsPort = 5350 + exitIndex.${n};
      }) allExits;
      scopes = map (s: { inherit (s) name mark list; }) scopes;
    }
  );
  tools = [
    pkgs.iproute2
    pkgs.wireguard-tools
    pkgs.nftables
    pkgs.jq
    pkgs.curl
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.gawk
    config.services.tailscale.package
    config.systemd.package
  ];
  exitUp = pkgs.writeShellApplication {
    name = "nixie-exit-up";
    runtimeInputs = tools;
    text = builtins.readFile ./exit-up.sh;
  };
  watch = pkgs.writeShellApplication {
    name = "nixie-egress-watch";
    runtimeInputs = tools;
    text = builtins.readFile ./egress-watch.sh;
  };
  exit = t.submodule {
    options = {
      type = mkOption {
        type = t.enum [
          "tailnet"
          "wireguard"
          "nordvpn"
          "tor"
        ];
        description = ''
          What this exit is. "tailnet": a device on your tailnet that offers
          itself as an exit node. "wireguard": a WireGuard server, such as a
          VPN provider's or your own. "nordvpn": NordVPN, with a server picked
          for you each time it connects. "tor": the Tor network, reached
          through another exit.
        '';
      };
      node = mkOption {
        type = t.str;
        default = "";
        description = "For a tailnet exit: the exit node's name on your tailnet.";
      };
      configFile = mkOption {
        type = t.nullOr t.path;
        default = null;
        description = "For a WireGuard exit: the provider's configuration file, kept in the site's secrets.";
      };
      tokenFile = mkOption {
        type = t.nullOr t.path;
        default = null;
        description = "For a NordVPN exit: a file with your NordVPN access token, kept in the site's secrets.";
      };
      country = mkOption {
        type = t.nullOr t.str;
        default = null;
        example = "ch";
        description = "For a NordVPN exit: the country to connect through, as a two-letter code. Empty lets NordVPN pick the nearest.";
      };
      via = mkOption {
        type = t.nullOr t.str;
        default = null;
        description = "For a Tor exit: the exit Tor itself connects through, so the VPN sees only Tor and Tor never sees your address. Empty connects Tor directly.";
      };
    };
  };
in
{
  options.nixie.network = {
    exits = mkOption {
      type = t.attrsOf exit;
      default = { };
      example = lib.literalExpression ''
        {
          home = { type = "tailnet"; node = "home-router"; };
          nord = { type = "nordvpn"; tokenFile = config.sops.secrets.nord.path; country = "ch"; };
          tor = { type = "tor"; via = "nord"; };
        }
      '';
      description = ''
        Ways out to the internet other than your own connection, each with a
        name the lists below use. Nothing uses an exit until a list names it.
      '';
    };
    guestEgress = mkOption {
      type = t.listOf t.str;
      default = [ ];
      example = [
        "nord"
        "home"
      ];
      description = ''
        The exits guests use, in order: the first that works carries their
        traffic, and the next takes over when it stops. If none works, guests
        are cut off rather than sent out directly. Guests created outside the
        site follow this list too. Empty means your own connection.
      '';
      nixieUi = {
        section = "network";
        order = 9;
      };
    };
    hostEgress = mkOption {
      type = t.listOf t.str;
      default = [ ];
      description = ''
        The same for this machine's own traffic -- on a desktop, everything you
        do. Your local network and tailnet stay reachable. Empty means your own
        connection.
      '';
      nixieUi = {
        section = "network";
        order = 9;
      };
    };
    tailscale.advertiseExit = mkOption {
      type = t.nullOr t.str;
      default = null;
      example = "nord";
      description = ''
        Offer this machine as an exit node to the other devices on your
        tailnet, with what they send leaving through the named exit -- NordVPN,
        for example. Approve it as an exit node in the Tailscale admin console.
      '';
    };
    egressMarks = mkOption {
      type = t.attrsOf t.int;
      default = lib.optionalAttrs on (lib.listToAttrs (map (s: lib.nameValuePair s.name s.mark) scopes));
      readOnly = true;
      internal = true;
      description = "Internal: the firewall mark of each egress scope, for the guests' bridge rules.";
    };
    nordApi = mkOption {
      type = t.str;
      default = "https://api.nordvpn.com";
      internal = true;
      description = "Internal: where NordVPN's server list and credentials are asked for (tests point it elsewhere).";
    };
  };

  config = lib.mkMerge [
    {
      assertions =
        map (n: {
          assertion = allExits ? ${n};
          message = "nixie.network: exit \"${n}\" is used in an egress list but not defined in nixie.network.exits";
        }) used
        ++ lib.mapAttrsToList (n: e: {
          assertion =
            {
              tailnet = e.node != "" && net.tailscale.enable;
              wireguard = e.configFile != null;
              nordvpn = e.tokenFile != null;
              tor = e.via == null || (allExits ? ${e.via} && allExits.${e.via}.type != "tor");
            }
            .${e.type};
          message = "nixie.network.exits.${n}: a ${e.type} exit needs ${
            {
              tailnet = "node, and nixie.network.tailscale.enable";
              wireguard = "configFile";
              nordvpn = "tokenFile";
              tor = "via to name a defined exit that is not Tor";
            }
            .${e.type}
          }";
        }) net.exits
        ++ [
          {
            assertion = net.tailscale.advertiseExit == null || net.tailscale.enable;
            message = "nixie.network.tailscale.advertiseExit needs nixie.network.tailscale.enable";
          }
          {
            assertion = (net.guestEgress == [ ] && ownLists == [ ]) || net.bridge.mode == "managed-nat";
            message = "guest egress lists need nixie.network.bridge.mode = \"managed-nat\": the host can only steer traffic it routes";
          }
        ];
    }
    (lib.mkIf on {
      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = lib.mkDefault 1;
        # A tunnel's packets keep their mark through the reverse path check.
        "net.ipv4.conf.all.src_valid_mark" = 1;
      };
      environment.systemPackages = [ pkgs.wireguard-tools ];
      environment.etc."nixie/egress.json".source = settings;
      # Pins are written by `nixie egress use`, which an administrator may run
      # without sudo (the desktop's control centre does); the watcher reads
      # them on its next round, or at once when it can be signalled.
      systemd.tmpfiles.rules = [ "d /var/lib/nixie/egress 2775 root wheel -" ];
      services.tailscale.extraUpFlags = lib.mkIf (net.tailscale.advertiseExit != null) [
        "--advertise-exit-node"
      ];
      users.groups.nixie-exit = { };
      users.users = {
        nixie-exit = {
          isSystemUser = true;
          group = "nixie-exit";
        };
      }
      // lib.mapAttrs' (
        n: _:
        lib.nameValuePair "nixie-tor-${n}" {
          isSystemUser = true;
          group = "nixie-exit";
        }
      ) torExits;
      networking.nftables.enable = true;
      # The build-time check runs where these users do not exist.
      networking.nftables.preCheckRuleset = ''
        sed -i 's/meta skuid "nixie-[^"]*"/meta skuid "nobody"/' ruleset.conf
      '';
      networking.nftables.tables.nixie-egress = {
        family = "inet";
        content = ''
          # Which scope marks go to which Tor instance; nixie-egress fills
          # these as scopes move on and off Tor.
          map tor_trans { type mark : inet_service; }
          map tor_dns { type mark : inet_service; }
          # Scopes on Tor: what Tor cannot carry (UDP but DNS, ICMP) is
          # dropped, never sent out another way.
          set tor_marks { type mark; }
          chain tor-out {
            type filter hook output priority filter; policy accept;
            meta mark @tor_marks ip daddr != 127.0.0.0/8 drop
            meta mark @tor_marks meta nfproto ipv6 drop
          }
          chain tor-forward {
            type filter hook forward priority filter; policy accept;
            meta mark @tor_marks drop
          }
          chain prerouting {
            type filter hook prerouting priority mangle; policy accept;
            ${lib.optionalString (net.tailscale.advertiseExit != null) ''
              iifname "tailscale0" ip daddr != 100.64.0.0/10 meta mark set ${markOf "tailnet-clients"}
            ''}
          }
          chain output {
            type route hook output priority mangle; policy accept;
            # The exits' own requests leave directly; each Tor instance
            # through its own scope; everything else the machine sends is
            # the host scope, except the tailnet and packets marked already
            # (a tunnel's, Tailscale's).
            meta skuid "nixie-exit" meta mark set ${toString wgMark}
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (
                n: _: ''meta skuid "nixie-tor-${n}" meta mark set ${markOf "tor-${n}"}''
              ) torExits
            )}
            # Replies (to someone who connected in) go back the way they came.
            meta mark 0 ct direction original ip daddr != { 127.0.0.0/8, 100.64.0.0/10 } meta mark set ${markOf "host"}
            meta mark 0 ct direction original ip6 daddr != { ::1, fd7a:115c:a1e0::/48 } meta mark set ${markOf "host"}
          }
          chain nat-prerouting {
            type nat hook prerouting priority dstnat; policy accept;
            meta l4proto tcp redirect to : meta mark map @tor_trans
            udp dport 53 redirect to : meta mark map @tor_dns
          }
          chain nat-output {
            type nat hook output priority -100; policy accept;
            meta l4proto tcp redirect to : meta mark map @tor_trans
            udp dport 53 redirect to : meta mark map @tor_dns
          }
          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;
            oifname "wg-*" masquerade
          }
        '';
      };
      systemd.services =
        lib.mapAttrs' (
          n: e:
          lib.nameValuePair "nixie-exit-${n}" {
            description = "Egress exit ${n} (${e.type})";
            wantedBy = [ "multi-user.target" ];
            before = [ "nixie-egress.service" ];
            wants = [ "network-online.target" ];
            after = [
              "network-online.target"
              "nftables.service"
            ];
            environment.NIXIE_EGRESS = "${settings}";
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${exitUp}/bin/nixie-exit-up up ${n}";
              ExecStop = "${exitUp}/bin/nixie-exit-up down ${n}";
              # systemd reads the secret as root and hands the unit a copy, so
              # the sops file keeps its owner.
              LoadCredential = [
                "secret:${toString (if e.type == "wireguard" then e.configFile else e.tokenFile)}"
              ];
              # exposure: creates and configures a network interface
              # (CAP_NET_ADMIN) and reads the provider's secret; its own user,
              # so its requests leave directly.
              User = "nixie-exit";
              Group = "nixie-exit";
              AmbientCapabilities = [ "CAP_NET_ADMIN" ];
              CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              NoNewPrivileges = true;
              RuntimeDirectory = "nixie-exit-${n}";
            };
          }
        ) tunnels
        // lib.mapAttrs' (
          n: _:
          lib.nameValuePair "nixie-tor-${n}" {
            description = "Tor for exit ${n}";
            wantedBy = [ "multi-user.target" ];
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            serviceConfig = {
              ExecStart = "${pkgs.tor}/bin/tor -f ${pkgs.writeText "torrc-${n}" ''
                DataDirectory /var/lib/nixie-tor-${n}
                SocksPort 0
                TransPort 0.0.0.0:${toString (9040 + exitIndex.${n})}
                DNSPort 0.0.0.0:${toString (5350 + exitIndex.${n})}
                AutomapHostsOnResolve 1
                VirtualAddrNetworkIPv4 10.192.0.0/10
              ''}";
              # exposure: a network daemon by design; confined to its own user
              # and state directory.
              User = "nixie-tor-${n}";
              Group = "nixie-exit";
              StateDirectory = "nixie-tor-${n}";
              StateDirectoryMode = "0700";
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              NoNewPrivileges = true;
              CapabilityBoundingSet = "";
              Restart = "always";
            };
          }
        ) torExits
        // {
          nixie-egress = {
            description = "Pick the working exit for every egress scope";
            wantedBy = [ "multi-user.target" ];
            after = [
              "network-online.target"
              "nftables.service"
              "tailscaled.service"
            ];
            wants = [ "network-online.target" ];
            environment.NIXIE_EGRESS = "${settings}";
            serviceConfig = {
              ExecStart = "${watch}/bin/nixie-egress-watch";
              Restart = "always";
              RestartSec = 5;
              # exposure: root, for routing rules, nftables maps and
              # tailscale's exit node setting.
            };
          };
        };
    })
  ];
}
