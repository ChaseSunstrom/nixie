{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../../lib/option.nix lib) mkOption;
  template = import ../../lib/template.nix lib;
  cfg = config.nixie.security.attestation;
  splash = config.boot.plymouth.enable;
  plymouth = "${config.boot.plymouth.package}/bin/plymouth";
  esp = config.fileSystems."/boot".device or "";
  # The ESP records which system the secret was last sealed for, by its
  # store path: the setup generation and the one after Finish share a label
  # but not a boot chain.
  sealedFile = "nixie/attestation-generation";

  # The code on the console and the splash: `once` before the first prompt,
  # `watch` until the disks are open (attestation.sh, beside this file).
  show = pkgs.writeShellScript "nixie-attestation" (
    template.fill ./attestation.sh {
      plymouth = lib.optionalString splash plymouth;
      esp = lib.escapeShellArg esp;
      tpm2totp = "${pkgs.tpm2-totp}/bin/tpm2-totp";
      sealedFile = lib.escapeShellArg sealedFile;
    }
  );
in
{
  options.nixie.security.attestation.enable = mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Before asking for the passphrase, show a six-digit code computed by the
      TPM from the boot measurements. Compare it with your authenticator app:
      a wrong code means the boot chain was changed. Needs a TPM. After an
      update the first start shows no code; once you unlock it, the code is
      sealed to the new system by itself when Secure Boot is on, and by
      `nixie reseal` otherwise.
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
    boot.initrd.systemd.storePaths = [
      pkgs.tpm2-totp
      show
    ];
    boot.initrd.systemd.services.nixie-attestation = {
      description = "Show the boot attestation code";
      wantedBy = [ "initrd.target" ];
      # cryptsetup units are ordered after this passive target, so pulling it
      # in and starting before it puts the code ahead of every prompt.
      wants = [ "cryptsetup-pre.target" ];
      before = [
        "cryptsetup-pre.target"
        "initrd-switch-root.target"
        "shutdown.target"
      ];
      # Not after dev-tpmrm0.device, though the code comes from the TPM:
      # this unit is ordered in front of every disk prompt, so anything it
      # waits for the prompt waits for too, and a device unit for a TPM that
      # never appears is not waited out until the device timeout -- ninety
      # seconds of a machine looking hung before it asks for the passphrase.
      # The script waits a few seconds for the device itself instead, and
      # says there is no code if it never comes.
      after = [ "plymouth-start.service" ];
      conflicts = [
        "initrd-switch-root.target"
        "shutdown.target"
      ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        # With the splash the code changes on screen every 30 seconds while
        # the prompts wait, so the service stays until the disks are open;
        # for the prompts' ordering it has started once the first code is out.
        Type = if splash then "simple" else "oneshot";
        ExecStartPre = lib.mkIf splash "${show} once";
        ExecStart = if splash then "${show} watch" else "${show} once";
        StandardOutput = "tty";
        StandardError = "tty";
        TTYPath = "/dev/console";
      };
    };
    # Reading the ESP in the initrd needs the vfat driver and its charsets.
    boot.initrd.kernelModules = [
      "vfat"
      "nls_cp437"
      "nls_iso8859-1"
    ];

    # After an update the TPM measures a new boot chain, which the secret is
    # not sealed to. Once the person has unlocked the new system it is sealed
    # again, but only a chain the firmware verified (Secure Boot on) and that
    # this machine installed: an unsigned chain could be anyone's, and it
    # stays for a person to accept with `nixie reseal`.
    systemd.services.nixie-attestation-reseal = {
      description = "Seal the attestation code to this system";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      unitConfig.ConditionPathExists = "/var/lib/nixie/totp-recovery";
      path = [
        pkgs.tpm2-totp
        config.systemd.package
        pkgs.coreutils
        pkgs.gnugrep
      ];
      # It needs the TPM, the ESP to write to, and the system profiles and
      # firmware variables to read; everything else is shut.
      # exposure: root, for the root-only ESP (1.1, "OK" to systemd, above
      # the platform's 0.3).
      serviceConfig = {
        Type = "oneshot";
        ProtectSystem = "strict";
        ReadWritePaths = [ "/boot" ];
        DevicePolicy = "closed";
        DeviceAllow = [ "/dev/tpmrm0 rw" ];
        CapabilityBoundingSet = "";
        PrivateNetwork = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
        IPAddressDeny = "any";
        PrivateTmp = true;
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        NoNewPrivileges = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" ];
        UMask = "0077";
      };
      # The script itself is attestation-reseal.sh, beside this file.
      script = template.fill ./attestation-reseal.sh { sealed = "/boot/${sealedFile}"; };
    };
    environment.systemPackages = [ pkgs.tpm2-totp ];
  };
}
