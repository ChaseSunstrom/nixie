{
  config,
  lib,
  ...
}:
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
        other way. Needs the managed-nat bridge mode, because the host must
        route the guests' traffic to force it anywhere.
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
    exitNodeAllowLan = mkOption {
      type = lib.types.bool;
      default = false;
      description = "Under exit-node egress, still let guests reach your local network directly.";
      nixieUi = {
        section = "network";
        order = 10;
      };
    };
  };

  config = lib.mkIf (config.nixie.network.egress == "exit-node") {
    assertions = [
      {
        assertion = config.nixie.network.bridge.mode == "managed-nat";
        message = "nixie.network.egress = \"exit-node\" needs nixie.network.bridge.mode = \"managed-nat\"";
      }
      {
        assertion = config.nixie.network.tailscale.enable;
        message = "nixie.network.egress = \"exit-node\" needs nixie.network.tailscale.enable";
      }
    ];
  };
}
