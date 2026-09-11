# Disk layout, generated from `nixie.disks` and the security options so the
# installer and the running system describe the same partitions.
{
  config,
  lib,
  ...
}:
let
  inherit (import ../lib/option.nix lib) mkOption;

  cfg = config.nixie.disks;
  sec = config.nixie.security;
  dataRoot = config.nixie.data.root;
  hasDataDisk = cfg.data != null;

  # Passphrases are read from files that exist only while phase 3 runs.
  luks = name: inner: {
    type = "luks";
    inherit name;
    passwordFile = "/run/nixie/keys/${name}";
    settings.allowDiscards = true;
    content = inner;
  };

  wrap =
    pool:
    let
      zfs = {
        type = "zfs";
        inherit pool;
      };
      # Layer order from the outside in: TPM+PIN, passphrase, filesystem.
      inner = if sec.encryption.enable then luks pool zfs else zfs;
    in
    if sec.tpm.enable then luks "${pool}-outer" inner else inner;

  # The data disk has one layer, opened after the root with a key that lives
  # on the encrypted root (see security/encryption.nix); the passphrase slot
  # stays as the recovery path.
  dataContent =
    if sec.encryption.enable then
      luks "dpool" {
        type = "zfs";
        pool = "dpool";
      }
      // {
        initrdUnlock = false;
        additionalKeyFiles = [ "/run/nixie/keys/dpool.key" ];
      }
    else
      {
        type = "zfs";
        pool = "dpool";
      };

  dataDatasets = {
    data = {
      type = "zfs_fs";
      mountpoint = dataRoot;
    };
    "data/state" = {
      type = "zfs_fs";
      mountpoint = "${dataRoot}/state";
    };
    "data/cache" = {
      type = "zfs_fs";
      mountpoint = "${dataRoot}/cache";
    };
    "data/media" = {
      type = "zfs_fs";
      mountpoint = "${dataRoot}/media";
    };
  };
  systemPart = "/dev/disk/by-partlabel/disk-system-system";
  dataPart = "/dev/disk/by-partlabel/disk-data-data";
  luksDevices =
    lib.optional sec.tpm.enable {
      name = "rpool-outer";
      device = systemPart;
    }
    ++ lib.optional sec.encryption.enable {
      name = "rpool";
      device = if sec.tpm.enable then "/dev/mapper/rpool-outer" else systemPart;
    }
    ++ lib.optional (sec.encryption.enable && hasDataDisk) {
      name = "dpool";
      device = dataPart;
    };
  # Incus manages its own children under this dataset.
  incusDataset.incus = {
    type = "zfs_fs";
    options.mountpoint = "none";
  };
  layout = {
    inherit (cfg) system data;
    luks = luksDevices;
    esp = "/dev/disk/by-partlabel/disk-system-esp";
    features = {
      encryption = sec.encryption.enable;
      tpm = sec.tpm.enable;
      inherit (sec.tpm) pcrs;
      secureBoot = sec.secureBoot.enable;
      attestation = sec.attestation.enable;
      duress = sec.duress.enable;
      remoteUnlock = sec.remoteUnlock.enable;
    };
  };
in
{
  options.nixie.disks = {
    system = mkOption {
      type = lib.types.str;
      description = "The disk the operating system is installed on. It is wiped at install. Written by the installer as a stable by-id path.";
      nixieUi = {
        section = "hardware";
        order = 0;
      };
    };
    data = mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        An optional second disk holding the data root as its own storage pool.
        Without it the data root lives on the system disk.
      '';
      nixieUi = {
        section = "hardware";
        order = 1;
      };
    };
    layout = mkOption {
      type = lib.types.enum [
        "single"
        "system+data"
      ];
      default = if hasDataDisk then "system+data" else "single";
      defaultText = "\"system+data\" when a data disk is set";
      description = "Whether the data root shares the system disk or has its own.";
    };
  };

  options.nixie.disks.luks = lib.mkOption {
    type = lib.types.listOf lib.types.attrs;
    default = luksDevices;
    readOnly = true;
    description = "Internal: every encryption layer, outermost first, as the installer and the duress agent see them.";
  };

  config = {
    # The pools are created by the installer on this host, so a forced import
    # would only ever hide a real problem.
    boot.zfs.forceImportRoot = false;

    # The phase scripts read the layout from the built system instead of
    # deriving it a second time.
    environment.etc."nixie/layout.json".text = builtins.toJSON layout;

    disko.devices = {
      disk.system = {
        type = "disk";
        device = cfg.system;
        content = {
          type = "gpt";
          partitions = {
            esp = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            system = {
              size = "100%";
              content = wrap "rpool";
            };
          };
        };
      };
      disk.data = lib.mkIf hasDataDisk {
        type = "disk";
        device = cfg.data;
        content = {
          type = "gpt";
          partitions.data = {
            size = "100%";
            content = dataContent;
          };
        };
      };
      zpool.rpool = {
        type = "zpool";
        options.ashift = "12";
        rootFsOptions = {
          compression = "zstd";
          acltype = "posixacl";
          xattr = "sa";
          mountpoint = "none";
        };
        datasets = {
          root = {
            type = "zfs_fs";
            mountpoint = "/";
          };
          nix = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options.atime = "off";
          };
          var = {
            type = "zfs_fs";
            mountpoint = "/var";
          };
          home = {
            type = "zfs_fs";
            mountpoint = "/home";
          };
        }
        // lib.optionalAttrs (!hasDataDisk) dataDatasets
        // lib.optionalAttrs (config.nixie.incus.enable && !hasDataDisk) incusDataset;
      };
      zpool.dpool = lib.mkIf hasDataDisk {
        type = "zpool";
        options.ashift = "12";
        rootFsOptions = {
          compression = "zstd";
          acltype = "posixacl";
          xattr = "sa";
          mountpoint = "none";
        };
        datasets = dataDatasets // lib.optionalAttrs config.nixie.incus.enable incusDataset;
      };
    };
  };
}
