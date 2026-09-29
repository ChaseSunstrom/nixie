{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../../lib/option.nix lib) mkOption;
  template = import ../../lib/template.nix lib;
  cfg = config.nixie.security.tpm;
  # tpm-lockout.sh, beside this file: phase 6 prepares the TPM's lockout
  # with it, and every start checks how the disk was opened.
  lockout = pkgs.writeShellApplication {
    name = "nixie-tpm-lockout";
    runtimeInputs = with pkgs; [
      tpm2-tools
      cryptsetup
      jq
      openssl
      gawk
      gnugrep
      coreutils
      config.systemd.package
    ];
    text = template.fill ./tpm-lockout.sh { state = "/run/nixie/tpm.json"; };
  };
in
{
  options.nixie.security.tpm = {
    enable = mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Add a second encryption layer tied to this machine's TPM chip plus a
        PIN. The disk then opens only in this machine, and only with both the
        PIN and the passphrase. Needs a TPM 2.0. After a firmware update or a
        change to Secure Boot the TPM can refuse the PIN: the recovery key
        then opens the disk, and `nixie security rebind` seals it again.
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
    environment.systemPackages = [
      pkgs.tpm2-tools
      lockout
    ];

    # Once a start is through, say how the outer layer was opened and why the
    # TPM refused if it did (the notices and `nixie doctor` read the file),
    # and forgive the wrong PINs that came before: nobody without the PIN or
    # the recovery key gets this far.
    systemd.services.nixie-tpm-check = {
      description = "Check how the disk was opened and reset the TPM's count of wrong PINs";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      before = [ "nixie-notices.service" ];
      # exposure: root, to read the disk's LUKS header and use the TPM's
      # lockout password; no capabilities or network, and it writes only
      # /run/nixie.
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe lockout} check";
        ExecStartPost = "-${pkgs.systemd}/bin/systemctl start --no-block nixie-notices.service";
        ProtectSystem = "strict";
        # cryptsetup takes a read lock on the header there.
        ReadWritePaths = [ "-/run/cryptsetup" ];
        RuntimeDirectory = "nixie";
        RuntimeDirectoryPreserve = true;
        PrivateNetwork = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
        IPAddressDeny = "any";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        NoNewPrivileges = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" ];
        CapabilityBoundingSet = "";
      };
    };
  };
}
