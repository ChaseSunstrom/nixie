{ lib, ... }:
let
  inherit (import ../lib/option.nix lib) mkOption;
in
{
  options.nixie.backups = {
    enable = mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Back up the state directory and every guest's backup paths with restic
        on a schedule. Costs storage at the repository and some disk activity.
      '';
      nixieUi = {
        section = "services";
        order = 0;
      };
    };
    repository = mkOption {
      type = lib.types.str;
      default = "";
      example = "sftp:backup@host:/srv/restic";
      description = "Where backups go, as a restic repository URL.";
      nixieUi = {
        section = "services";
        order = 1;
      };
    };
    passwordFile = mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "File holding the repository password.";
    };
    environmentFile = mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "File with credentials for the repository's storage, if it needs any.";
    };
    schedule = mkOption {
      type = lib.types.str;
      default = "daily";
      description = "How often to back up.";
      nixieUi = {
        section = "services";
        order = 2;
      };
    };
    excludes = mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Patterns left out of backups.";
    };
    keep = {
      daily = mkOption {
        type = lib.types.int;
        default = 7;
        description = "Daily snapshots to keep.";
      };
      weekly = mkOption {
        type = lib.types.int;
        default = 4;
        description = "Weekly snapshots to keep.";
      };
      monthly = mkOption {
        type = lib.types.int;
        default = 6;
        description = "Monthly snapshots to keep.";
      };
    };
  };
}
