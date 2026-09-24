{
  config,
  lib,
  pkgs,
  ...
}:
let
  template = import ../lib/template.nix lib;
  inherit (import ../lib/option.nix lib) mkOption;
  cfg = config.nixie.backups;
  onNas = lib.hasPrefix "nas:" cfg.repository;
  nasMount = "/nas/${lib.head (lib.splitString "/" (lib.removePrefix "nas:" cfg.repository))}";
  # The sops path of the password the installer generates when the wizard
  # turns backups on; written out as a path, not read from sops.secrets, so the
  # declaration below can depend on it without a loop.
  generatedPassword = "/run/secrets/backup-password";
  root = toString config.nixie.data.root;
  guestsLib = import ../lib/guests.nix { inherit lib; };
  # `nixie-snapshot pre-apply <label>`: ZFS snapshots of state/ and every
  # guest backup path before apply, keeping the last five; also marks
  # those datasets for zfs-auto-snapshot.
  snapshotTool = pkgs.writeShellApplication {
    name = "nixie-snapshot";
    runtimeInputs = [
      pkgs.zfs
      pkgs.jq
    ];
    text = template.fill ./backups/snapshot.sh { inherit root; };
  };
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
      description = "Where backups go, as a restic repository URL, or \"nas:<share>/<folder>\" for a share in nixie.nas.";
      nixieUi = {
        section = "services";
        order = 1;
      };
    };
    passwordFile = mkOption {
      type = lib.types.nullOr lib.types.path;
      default = generatedPassword;
      defaultText = generatedPassword;
      description = "File holding the repository password. By default the one the installer generated into the host's secrets.";
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
    snapshots = {
      hourly = mkOption {
        type = lib.types.int;
        default = 24;
        description = "Hourly ZFS snapshots of state/ to keep on the disk itself. They are not a backup against losing the disk.";
      };
      daily = mkOption {
        type = lib.types.int;
        default = 7;
        description = "Daily ZFS snapshots of state/ to keep.";
      };
      weekly = mkOption {
        type = lib.types.int;
        default = 4;
        description = "Weekly ZFS snapshots of state/ to keep.";
      };
    };
    rcloneConfigFile = mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "An rclone configuration file for \"rclone:\" repositories (S3, B2 and friends).";
    };
    check = mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "weekly";
      description = "How often to run `restic check` over the repository; `nixie doctor` and `nixie backup verify` show the last result. Null turns it off.";
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

  config = lib.mkMerge [
    # Local history is part of the data layout, not of offsite backups: it
    # works (and `nixie apply` uses it) whether or not restic is configured.
    {
      # zfs-auto-snapshot over every dataset carrying the com.sun:auto-snapshot
      # property (state/ from the disk layout, plus what `nixie-snapshot` marks).
      services.zfs.autoSnapshot = lib.mkIf config.boot.zfs.enabled {
        enable = true;
        flags = "-k -p --utc";
        frequent = 0;
        monthly = 0;
        inherit (cfg.snapshots) hourly daily weekly;
      };
      environment.systemPackages = [ snapshotTool ];
    }
    (lib.mkIf cfg.enable {
      sops.secrets.backup-password = lib.mkIf (toString cfg.passwordFile == generatedPassword) { };
      assertions = [
        {
          assertion = cfg.repository != "" && cfg.passwordFile != null;
          message = "nixie.backups needs a repository and a passwordFile";
        }
      ];
      services.restic.backups.nixie = {
        # A NAS share is a local path under its mount, which the backup then
        # needs (below).
        repository = if onNas then "/nas/${lib.removePrefix "nas:" cfg.repository}" else cfg.repository;
        inherit (cfg)
          passwordFile
          environmentFile
          rcloneConfigFile
          ;
        initialize = true;
        paths = lib.unique (
          [ "${root}/state" ]
          ++ guestsLib.backupPaths config.nixie.guests
          ++ lib.optional config.nixie.data.mediaBackup "${root}/media"
        );
        # cache/ is re-fetchable by definition and Incus's own database is
        # regenerated by apply; neither belongs in a backup.
        exclude = [
          "${root}/cache"
          "/var/lib/incus/database"
        ]
        ++ cfg.excludes;
        timerConfig = {
          OnCalendar = cfg.schedule;
          Persistent = true;
        };
        pruneOpts = [
          "--keep-daily ${toString cfg.keep.daily}"
          "--keep-weekly ${toString cfg.keep.weekly}"
          "--keep-monthly ${toString cfg.keep.monthly}"
        ];
      };
      systemd.services.restic-backups-nixie.unitConfig.RequiresMountsFor = lib.mkIf onNas [ nasMount ];
      # `restic check` on its own schedule; the result file feeds doctor/verify.
      systemd.services.nixie-backup-check = lib.mkIf (cfg.check != null) {
        description = "Verify the backup repository";
        unitConfig.RequiresMountsFor = lib.mkIf onNas [ nasMount ];
        # The restic module puts its `restic-nixie` wrapper (repository and
        # credentials baked in) in the system profile, not on a unit's PATH.
        path = [ "/run/current-system/sw" ];
        serviceConfig = {
          Type = "oneshot";
          # exposure: reads the repository credentials as root, like the backup itself.
          ExecStart = pkgs.writeShellScript "nixie-backup-check" (
            template.fill ./backups/check.sh { inherit (pkgs) jq; }
          );
        };
      };
      systemd.timers.nixie-backup-check = lib.mkIf (cfg.check != null) {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.check;
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
      };
      environment.systemPackages = [
        # `nixie restore <snapshot> [--path <p>]... [--to <dir>]`: in place by
        # default, beside the live data with --to; other flags go to restic.
        (pkgs.writeShellApplication {
          name = "nixie-restore";
          text = builtins.readFile ./backups/restore.sh;
        })
        # `nixie backup now | list [--json] | verify | kit <file> [--recipient r]`.
        (pkgs.writeShellApplication {
          name = "nixie-backup";
          runtimeInputs = [
            pkgs.age
            pkgs.jq
            pkgs.gnutar
            pkgs.systemd
          ];
          text = template.fill ./backups/backup.sh {
            environmentFile = toString cfg.environmentFile;
            passwordFile = toString cfg.passwordFile;
            rcloneConfigFile = toString cfg.rcloneConfigFile;
            kitEnv = lib.optionalString (
              cfg.environmentFile != null
            ) ''cp ${toString cfg.environmentFile} "$tmp/restic-env"'';
            kitRclone = lib.optionalString (
              cfg.rcloneConfigFile != null
            ) ''cp ${toString cfg.rcloneConfigFile} "$tmp/rclone.conf"'';
          };
        })
      ];
    })
  ];
}
