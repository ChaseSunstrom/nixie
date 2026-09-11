{
  config,
  lib,
  ...
}:
let
  inherit (import ../../lib/option.nix lib) mkOption;
  cfg = config.nixie.security.hardening;
  h = "nixie.security.hardening";
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
        later is ignored until you add it to the allowlist in ${h}.usbguard.rules.
      '';
      nixieUi = {
        section = "security";
        order = 11;
      };
    };
    usbguard.rules = mkOption {
      type = lib.types.lines;
      default = "";
      description = "The USB allowlist. Empty means the list setup generated on this host.";
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
        rules = if cfg.usbguard.rules == "" then null else cfg.usbguard.rules;
        implicitPolicyTarget = "block";
        presentDevicePolicy = "apply-policy";
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
