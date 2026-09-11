{ lib, ... }:
let
  inherit (import ../../lib/option.nix lib) mkOption;
in
{
  options.nixie.network = {
    egress = mkOption {
      type = lib.types.enum [
        "direct"
        "exit-node"
      ];
      default = "direct";
      description = ''
        "direct": guests reach the internet through your network.
        "exit-node": every guest, declared or not, is forced through the
        Tailscale exit node named below and cannot reach the internet any
        other way.
      '';
      nixieUi = {
        section = "network";
        order = 8;
      };
    };
    exitNode = mkOption {
      type = lib.types.str;
      default = "";
      description = "The tailnet name of the exit node used when egress is \"exit-node\".";
      nixieUi = {
        section = "network";
        order = 9;
      };
    };
  };
}
