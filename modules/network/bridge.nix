{ lib, ... }:
let
  inherit (import ../../lib/option.nix lib) mkOption;
in
{
  options.nixie.network = {
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
}
