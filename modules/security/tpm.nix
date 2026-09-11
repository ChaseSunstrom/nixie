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
    ];
    boot.initrd.systemd.tpm2.enable = true;
    boot.initrd.availableKernelModules = [
      "tpm_tis"
      "tpm_crb"
    ];
    # The outer layer is enrolled by setup (phase 6) with a PIN; until then its
    # passphrase slot is used, so first boot asks twice.
    boot.initrd.luks.devices.rpool-outer.crypttabExtraOpts = [ "tpm2-device=auto" ];
    security.tpm2.enable = true;
    environment.systemPackages = [ pkgs.tpm2-tools ];
  };
}
