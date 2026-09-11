# The guest bridge. Uplinks are matched by hardware address and renamed to
# stable names, so nothing here depends on how the kernel names a card.
{
  config,
  lib,
  ...
}:
let
  inherit (import ../../lib/option.nix lib) mkOption;
  cfg = config.nixie.network;
  enabled = config.nixie.incus.enable;
  nat = cfg.bridge.mode == "managed-nat";
  # First host address of the private network, for the bridge itself.
  natHost = "${lib.removeSuffix ".0" (lib.head (lib.splitString "/" cfg.bridge.natSubnet))}.1";
  natPrefix = lib.last (lib.splitString "/" cfg.bridge.natSubnet);
in
{
  options.nixie.network = {
    bridge.name = mkOption {
      type = lib.types.str;
      default = "nixie-br";
      readOnly = true;
      description = "Internal: the name of the guest bridge.";
    };
    bridge.uplinks = mkOption {
      type = lib.types.listOf (lib.types.strMatching "^([0-9a-f]{2}:){5}[0-9a-f]{2}$");
      default = [ ];
      description = ''
        Which physical network ports join the guest bridge, chosen by hardware
        address so cable and slot changes do not matter. Written by the
        installer.
      '';
      nixieUi = {
        section = "hardware";
        order = 2;
      };
    };
    bridge.vlanAware = mkOption {
      type = lib.types.bool;
      default = false;
      description = "Let guests use VLAN tags on the bridge.";
      nixieUi = {
        section = "network";
        order = 3;
      };
    };
    bridge.mode = mkOption {
      type = lib.types.enum [
        "unmanaged-lan"
        "managed-nat"
      ];
      default = "unmanaged-lan";
      description = ''
        "unmanaged-lan": guests appear on your network like any other computer
        and get addresses from your router. "managed-nat": guests live on a
        private network behind this host and share its address.
      '';
      nixieUi = {
        section = "network";
        order = 2;
      };
    };
    bridge.natSubnet = mkOption {
      type = lib.types.str;
      default = "10.90.0.0/24";
      description = "The private network used in managed-nat mode.";
      nixieUi = {
        section = "network";
        order = 4;
      };
    };
    address = mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "192.0.2.10/24";
      description = "A fixed address for this host. Empty means ask the router (DHCP).";
      nixieUi = {
        section = "network";
        order = 5;
      };
    };
    gateway = mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "The router's address, needed only with a fixed address.";
      nixieUi = {
        section = "network";
        order = 6;
      };
    };
    dns = mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Name servers, needed only with a fixed address.";
      nixieUi = {
        section = "network";
        order = 7;
      };
    };
  };

  config = lib.mkIf enabled {
    boot.kernel.sysctl."net.ipv4.ip_forward" = lib.mkIf nat 1;
    networking.useNetworkd = true;
    networking.useDHCP = false;
    networking.nameservers = cfg.dns;

    systemd.network = {
      enable = true;
      links = lib.listToAttrs (
        lib.imap0 (i: mac: {
          name = "10-nixie-uplink${toString i}";
          value = {
            matchConfig.MACAddress = mac;
            linkConfig.Name = "uplink${toString i}";
          };
        }) cfg.bridge.uplinks
      );
      netdevs."10-${cfg.bridge.name}" = {
        netdevConfig = {
          Kind = "bridge";
          Name = cfg.bridge.name;
        };
        bridgeConfig.VLANFiltering = cfg.bridge.vlanAware;
      };
      networks = {
        "10-nixie-uplinks" = {
          matchConfig.Name = "uplink*";
          networkConfig.Bridge = cfg.bridge.name;
          linkConfig.RequiredForOnline = "enslaved";
        };
        "20-${cfg.bridge.name}" = {
          matchConfig.Name = cfg.bridge.name;
          # In NAT mode the host owns the private network and hands out
          # addresses; otherwise the bridge is just another LAN port.
          networkConfig =
            if nat then
              {
                Address = "${natHost}/${natPrefix}";
                ConfigureWithoutCarrier = true;
                DHCPServer = true;
                IPMasquerade = "ipv4";
                IPv4Forwarding = true;
              }
            else
              {
                DHCP = if cfg.address == null then "yes" else "no";
              };
          dhcpServerConfig = lib.mkIf nat {
            EmitDNS = true;
            DNS = if cfg.dns == [ ] then [ natHost ] else cfg.dns;
          };
          address = lib.optional (!nat && cfg.address != null) cfg.address;
          gateway = lib.optional (!nat && cfg.gateway != null) cfg.gateway;
          # In NAT mode the bridge has no members until a guest starts, so it
          # must be addressed without carrier.
          linkConfig.RequiredForOnline = if nat then "no" else "routable";
        };
      }
      // lib.optionalAttrs nat {
        # With NAT the uplinks are the host's own way out.
        "10-nixie-uplinks" = lib.mkForce {
          matchConfig.Name = "uplink*";
          networkConfig.DHCP = if cfg.address == null then "yes" else "no";
          address = lib.optional (cfg.address != null) cfg.address;
          gateway = lib.optional (cfg.gateway != null) cfg.gateway;
        };
      };
    };
  };
}
