{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../../lib/option.nix lib) mkOption;
  cfg = config.nixie.security.attestation;
  splash = config.boot.plymouth.enable;
  plymouth = "${config.boot.plymouth.package}/bin/plymouth";
  esp = config.fileSystems."/boot".device or "";
  # The ESP records which system the secret was last sealed for, by its
  # store path: the setup generation and the one after Finish share a label
  # but not a boot chain.
  sealedFile = "nixie/attestation-generation";

  # `once` prints the code on the console and puts it on the splash before
  # the first prompt; `watch` keeps the splash's code current until the disks
  # are open.
  show = pkgs.writeShellScript "nixie-attestation" ''
    set -u
    booted=""
    read -r cmdline </proc/cmdline
    for w in $cmdline; do
      case $w in init=*) booted=''${w#init=}; booted=''${booted%/init} ;; esac
    done

    state() {
      sealed=$(cat /run/nixie-attestation-sealed 2>/dev/null || true)
      if [ -n "$sealed" ] && [ "$sealed" != "$booted" ]; then
        # Sealed for another system, so no code can match.
        kind=warn
        text="No attestation code: this system changed since it was sealed. Unlock only if you updated it."
      elif code=$(${pkgs.tpm2-totp}/bin/tpm2-totp calculate 2>/dev/null); then
        kind=code
        text=$code
      elif [ -z "$sealed" ]; then
        # Before setup seals one; a machine set up long ago that says this
        # has had its ESP changed.
        kind=warn
        text="No attestation code yet: setup seals one. If this machine was set up before, do not unlock it."
      else
        kind=warn
        text="ATTESTATION FAILED: the boot chain was changed. Do not unlock unless you know why."
      fi
    }

    # Put a line on the splash, replacing the one shown before; any theme
    # shows it, and the Nixie one draws a code large.
    tell() {
      ${lib.optionalString splash ''
        old=$(cat /run/nixie-attestation-shown 2>/dev/null || true)
        [ "$old" != "$1" ] || return 0
        [ -z "$old" ] || ${plymouth} hide-message --text="$old" 2>/dev/null || true
        printf '%s' "$1" >/run/nixie-attestation-shown
        [ -z "$1" ] || ${plymouth} display-message --text="$1" 2>/dev/null || true
      ''}
      return 0
    }
    line() { if [ "$kind" = code ]; then echo "Attestation code $text"; else echo "$text"; fi; }

    case ''${1:-once} in
      once)
        ${lib.optionalString (esp != "") ''
          if [ -e ${lib.escapeShellArg esp} ]; then
            mkdir -p /run/nixie-esp
            if mount -o ro ${lib.escapeShellArg esp} /run/nixie-esp 2>/dev/null; then
              cat /run/nixie-esp/${sealedFile} >/run/nixie-attestation-sealed 2>/dev/null || true
              umount /run/nixie-esp 2>/dev/null || true
            fi
          fi
        ''}
        state
        echo
        if [ "$kind" = code ]; then echo "  Attestation code: $text"; else echo "  $text"; fi
        echo
        tell "$(line)"
        # For the journal, without the code: Plymouth keeps what is written
        # to the console while it runs.
        echo "<5>nixie-attestation: $kind shown" >/dev/kmsg 2>/dev/null || true
        ;;
      watch)
        window=$(( $(date +%s) / 30 ))
        until systemctl -q is-active cryptsetup.target; do
          sleep 1
          now=$(( $(date +%s) / 30 ))
          [ "$now" != "$window" ] || continue
          window=$now
          state
          tell "$(line)"
        done
        tell ""
        ;;
    esac
  '';
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
      wants = [
        "cryptsetup-pre.target"
        "dev-tpmrm0.device"
      ];
      before = [
        "cryptsetup-pre.target"
        "initrd-switch-root.target"
        "shutdown.target"
      ];
      after = [
        "dev-tpmrm0.device"
        "plymouth-start.service"
      ];
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
      script = ''
        booted=$(readlink -f /run/booted-system)
        sealed=$(cat /boot/${sealedFile} 2>/dev/null || true)
        # Never sealed (setup does that), or sealed for this very system: a
        # code that does not compute then means the chain changed without an
        # update, which is for a person to look into.
        [ -n "$sealed" ] && [ "$sealed" != "$booted" ] || exit 0
        installed=""
        for g in /nix/var/nix/profiles/system-*-link; do
          for s in "$g" "$g"/specialisation/*; do
            [ "$(readlink -f "$s")" != "$booted" ] || installed=1
          done
        done
        if [ -z "$installed" ] || ! bootctl status 2>/dev/null | grep -qE 'Secure Boot: *enabled'; then
          echo "not sealing: $booted is not a Secure Boot verified system this machine installed; run 'nixie reseal' if you trust it"
          exit 0
        fi
        tpm2-totp reseal -P "$(cat /var/lib/nixie/totp-recovery)" -p 4,7,8,9
        printf '%s' "$booted" >/boot/${sealedFile}
        echo "attestation sealed to $booted"
      '';
    };
    environment.systemPackages = [ pkgs.tpm2-totp ];
  };
}
