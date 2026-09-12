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
    keepGenerations = mkOption {
      type = lib.types.ints.positive;
      default = 10;
      description = ''
        How many earlier versions of this machine's system stay bootable. Each
        `nixie apply` adds one; the boot menu, `nixie rollback --list` and the
        History page show them with the site commit, date and kernel. Older
        ones go with the weekly clean-up, and with Secure Boot on only these
        stay signed.
      '';
    };
    siteRevision = mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      internal = true;
      description = "Internal: the site repository commit this system was built from; it labels generations and snapshots.";
    };
  };
}
