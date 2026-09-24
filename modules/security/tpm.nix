{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../../lib/option.nix lib) mkOption;
  cfg = config.nixie.security.tpm;
in
{
  options.nixie.security.tpm = {
    enable = mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Add a second encryption layer tied to this machine's TPM chip plus a
        PIN. The disk then opens only in this machine, and only with both the
        PIN and the passphrase. Needs a TPM 2.0. A firmware update or a change
        to the boot chain can require running `nixie reseal`.
      '';
      nixieUi = {
        section = "security";
        order = 1;
        secret = "pin";
      };
    };
    pcrs = mkOption {
      type = lib.types.listOf lib.types.int;
      default = [ 7 ];
      description = ''
        Which boot measurements the TPM layer is tied to. 7 tracks the Secure
        Boot state. Adding more makes unlocking stricter and re-enrolment more
        frequent.
      '';
      nixieUi = {
        section = "security";
        order = 2;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.nixie.security.encryption.enable;
        message = "nixie.security.tpm.enable needs nixie.security.encryption.enable";
      }
      {
        # Caught here rather than at the first start. Without a TPM this adds
        # an outer layer whose crypttab tells the initrd to look for a device
        # that is not there; the install succeeds and the machine stops in
        # emergency mode instead of asking for the passphrase.
        assertion = config.nixie.hardware.tpm;
        message = ''
          nixie.security.tpm.enable is on, but this machine has no TPM:
          hosts/<name>/hardware.nix says nixie.hardware.tpm = false, which is
          what the installer found. Binding the disk to a TPM that is not
          there gives it a layer nothing can open, and the machine stops at
          its first start. Turn nixie.security.tpm.enable (and
          nixie.security.attestation.enable, which needs it too) off, or
          install on a machine with a TPM.
        '';
      }
    ];
    boot.initrd.systemd.tpm2.enable = true;
    boot.initrd.availableKernelModules = [
      "tpm_tis"
      "tpm_crb"
    ];
    # The outer layer is enrolled by setup (phase 6) with a PIN; until then
    # its passphrase slot is what opens it, and systemd offers the inner
    # layer the same passphrase, so a person still types it once (vm-splash
    # holds that). This option is also why the TPM must actually exist: it
    # tells the initrd to look for one.
    boot.initrd.luks.devices.rpool-outer.crypttabExtraOpts = [
      "tpm2-device=auto"
      # Asked until answered: the default three tries counted the TPM PIN
      # attempts too, so when the TPM refused (Secure Boot changed) one
      # wrong answer at the recovery key prompt ended in emergency mode.
      # The TPM's own lockout still limits PIN guessing.
      "tries=0"
    ];
    security.tpm2.enable = true;
    environment.systemPackages = [ pkgs.tpm2-tools ];
  };
}
