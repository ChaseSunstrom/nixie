{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../../lib/option.nix lib) mkOption;
  cfg = config.nixie.security.attestation;
in
{
  options.nixie.security.attestation.enable = mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Before asking for the passphrase, show a six-digit code computed by the
      TPM from the boot measurements. Compare it with your authenticator app:
      a wrong code means the boot chain was changed. Needs a TPM; run
      `nixie reseal` after kernel updates.
    '';
    nixieUi = {
      section = "security";
      order = 4;
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.nixie.security.encryption.enable;
        message = "nixie.security.attestation.enable needs nixie.security.encryption.enable";
      }
    ];
    boot.initrd.availableKernelModules = [
      "tpm_tis"
      "tpm_crb"
    ];
    boot.initrd.systemd.storePaths = [ pkgs.tpm2-totp ];
    boot.initrd.systemd.services.nixie-attestation = {
      description = "Show the boot attestation code";
      wantedBy = [ "initrd.target" ];
      # cryptsetup units are ordered after this passive target, so pulling it
      # in and running before it puts the code ahead of every prompt.
      wants = [
        "cryptsetup-pre.target"
        "dev-tpmrm0.device"
      ];
      before = [ "cryptsetup-pre.target" ];
      after = [ "dev-tpmrm0.device" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        StandardOutput = "tty";
        StandardError = "tty";
        TTYPath = "/dev/console";
      };
      script = ''
        echo
        if code=$(${pkgs.tpm2-totp}/bin/tpm2-totp show 2>/dev/null); then
          echo "  Attestation code: $code"
        else
          echo "  ATTESTATION FAILED: the boot chain does not match the sealed measurements."
          echo "  If you just updated the kernel, run 'nixie reseal' after unlocking."
        fi
        echo
      '';
    };
    environment.systemPackages = [ pkgs.tpm2-totp ];
  };
}
