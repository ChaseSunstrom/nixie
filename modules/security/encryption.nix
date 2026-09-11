{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../../lib/option.nix lib) mkOption;
  cfg = config.nixie.security.encryption;
in
{
  options.nixie.security.encryption.enable = mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Encrypt the whole system so a stolen disk is unreadable. You type a
      passphrase every time the machine starts. This is the only setting that
      needs a reinstall to change; `nixie apply` refuses to flip it.
    '';
    nixieUi = {
      section = "security";
      order = 0;
      secret = "passphrase";
    };
  };

  config = lib.mkIf cfg.enable {
    # A kernel that panics while the disk is open must not sit there with the
    # key in memory.
    boot.kernelParams = [ "panic=10" ];
    environment.systemPackages = [ pkgs.cryptsetup ];

    # The data disk is unlocked after the root is up, with a key kept on the
    # encrypted root, so there is one passphrase to type, not two.
    environment.etc.crypttab = lib.mkIf (config.nixie.disks.data != null) {
      text = "dpool /dev/disk/by-partlabel/disk-data-data /etc/nixie/keys/dpool.key luks,discard\n";
    };
    systemd.services.zfs-import-dpool = lib.mkIf (config.nixie.disks.data != null) {
      after = [ "systemd-cryptsetup@dpool.service" ];
      requires = [ "systemd-cryptsetup@dpool.service" ];
    };
  };
}
