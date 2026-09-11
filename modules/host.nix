{ lib, ... }:
let
  inherit (import ../lib/option.nix lib) mkOption;
in
{
  options.nixie.host = {
    name = mkOption {
      type = lib.types.strMatching "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$";
      description = "The machine's name on the network and in the site repo. Lowercase letters, digits and dashes.";
      nixieUi = {
        section = "network";
        order = 0;
      };
    };
    timezone = mkOption {
      type = lib.types.str;
      default = "UTC";
      example = "Europe/Amsterdam";
      description = "Time zone for logs, timers and the clock.";
      nixieUi = {
        section = "network";
        order = 1;
      };
    };
    siteRevision = mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      internal = true;
      description = "Internal: the site repository commit this system was built from; it labels generations and snapshots.";
    };
  };
}
