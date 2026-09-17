{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../../lib/option.nix lib) mkOption;
  cfg = config.nixie.security.hardening;
  h = "nixie.security.hardening";
  allowRule =
    spec:
    let
      parts = lib.splitString "/" spec;
      id = lib.head parts;
      serial = lib.concatStringsSep "/" (lib.tail parts);
    in
    "allow id ${id}" + lib.optionalString (serial != "") " serial \"${serial}\"";
  declaredRules = pkgs.writeText "nixie-usbguard-declared.conf" (
    lib.concatMapStrings (r: r + "\n") (map allowRule cfg.usbguard.allow)
    # Setup is finished at the machine itself, in a kiosk that needs a pointer
    # as well as a keyboard: a mouse, touchpad or touchscreen plugged in
    # after usbguard first ran would otherwise be blocked and the setup page
    # could not be used. HID boot keyboards and mice, and HID devices without
    # a boot subclass (touchscreens, most touchpads). After Finish this rule
    # is gone and only the setup list and the allow list remain.
    + lib.optionalString config.nixie.setup.pending "allow with-interface one-of { 03:00:00 03:00:01 03:00:02 03:01:01 03:01:02 }\n"
    + cfg.usbguard.rules
  );
in
{
  options.nixie.security.hardening = {
    ssh.enable = mkOption {
      type = lib.types.bool;
      default = true;
      description = "Key-only SSH with modern ciphers, no root login and no forwarding.";
      nixieUi = {
        section = "security";
        order = 10;
      };
    };
    usbguard.enable = mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Only USB devices present at setup are allowed. Anything plugged in
        later is blocked until `nixie usb allow` adds it to ${h}.usbguard.allow.
      '';
      nixieUi = {
        section = "security";
        order = 11;
      };
    };
    usbguard.rules = mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra usbguard rules, added after the list of devices present when this host was set up.";
    };
    usbguard.allow = mkOption {
      type = lib.types.listOf (lib.types.strMatching "^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}(/.*)?$");
      default = [ ];
      example = [
        "1234:5678"
        "1234:5678/SERIAL"
      ];
      description = ''
        USB devices allowed on top of the ones present at setup, as
        "vendor:product" or "vendor:product/serial". `nixie usb allow` adds
        to this list in the site.
      '';
    };
    memoryEncryption.enable = mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Ask the processor to encrypt memory (AMD TSME) and turn on the IOMMU so
        devices cannot read memory they were not given. Only takes effect on
        hardware that supports it.
      '';
      nixieUi = {
        section = "security";
        order = 12;
      };
    };
    remoteJournal.enable = mkOption {
      type = lib.types.bool;
      default = false;
      description = "Send a copy of the system log to another machine so an intruder cannot erase it here.";
      nixieUi = {
        section = "security";
        order = 13;
      };
    };
    remoteJournal.url = mkOption {
      type = lib.types.str;
      default = "";
      example = "https://logs.example:19532";
      description = "Where the log copy is sent (a systemd-journal-remote endpoint).";
      nixieUi = {
        section = "security";
        order = 14;
      };
    };
  };

  config = lib.mkMerge [
    {
      # Sensible everywhere: hide kernel pointers and logs from users, keep
      # BPF and ptrace to root, and reject spoofed source addresses.
      boot.kernel.sysctl = {
        "kernel.kptr_restrict" = 2;
        "kernel.dmesg_restrict" = 1;
        "kernel.unprivileged_bpf_disabled" = 1;
        "net.core.bpf_jit_harden" = 2;
        "kernel.yama.ptrace_scope" = 1;
        "net.ipv4.conf.all.rp_filter" = 1;
        "net.ipv4.conf.default.rp_filter" = 1;
        "fs.protected_fifos" = 2;
        "fs.protected_regular" = 2;
      };
    }
    (lib.mkIf cfg.ssh.enable {
      services.openssh.settings = {
        X11Forwarding = false;
        AllowAgentForwarding = false;
        AllowUsers = [ config.nixie.auth.admin.name ];
        KexAlgorithms = [
          "sntrup761x25519-sha512@openssh.com"
          "mlkem768x25519-sha256"
          "curve25519-sha256"
        ];
        Ciphers = [
          "chacha20-poly1305@openssh.com"
          "aes256-gcm@openssh.com"
        ];
        Macs = [
          "hmac-sha2-512-etm@openssh.com"
          "hmac-sha2-256-etm@openssh.com"
        ];
      };
    })
    (lib.mkIf cfg.usbguard.enable {
      services.usbguard = {
        enable = true;
        implicitPolicyTarget = "block";
        presentDevicePolicy = "apply-policy";
      };
      # The policy is the devices present when usbguard first ran on this
      # host (kept in /var/lib/usbguard/setup-rules.conf) followed by the
      # declared part; usbguard reads one file, so it is joined before every
      # start and the daemon restarts when the declared part changes.
      systemd.services.usbguard = {
        path = [ config.services.usbguard.package ];
        restartTriggers = [ declaredRules ];
        preStart = lib.mkAfter ''
          cd /var/lib/usbguard
          [ -s setup-rules.conf ] || usbguard generate-policy >setup-rules.conf
          cat setup-rules.conf ${declaredRules} >rules.conf
        '';
      };
    })
    (lib.mkIf cfg.memoryEncryption.enable {
      boot.kernelParams = [
        "mem_encrypt=on"
        "amd_iommu=on"
        "intel_iommu=on"
        "iommu=pt"
      ];
    })
    (lib.mkIf cfg.remoteJournal.enable {
      services.journald.upload = {
        enable = true;
        settings.Upload.URL = cfg.remoteJournal.url;
      };
    })
  ];
}
