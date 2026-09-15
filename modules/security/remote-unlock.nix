{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  inherit (import ../../lib/option.nix lib) mkOption;
  cfg = config.nixie.security.remoteUnlock;
  net = config.nixie.network;
  esp = "/dev/disk/by-partlabel/disk-system-esp";
  espUnit = "${utils.escapeSystemdPath esp}.device";
  # Relays every pending prompt to the SSH session, in crypttab order, then
  # exits once the root file system is up.
  relay = pkgs.writeShellApplication {
    name = "nixie-unlock-relay";
    runtimeInputs = [ config.boot.initrd.systemd.package ];
    text = ''
      # Without a terminal the agent answers the boot's query with a
      # cancellation, which systemd-cryptsetup takes as a failure: one
      # `ssh -p <port> root@<host> true` left a machine in emergency mode.
      if [ ! -t 0 ]; then
        echo "remote unlock needs a terminal: ssh -t -p <port> root@<host>" >&2
        exit 1
      fi
      systemd-tty-ask-password-agent --query --watch &
      agent=$!
      until systemctl -q is-active initrd-root-fs.target; do sleep 1; done
      kill "$agent" 2>/dev/null || true
    '';
  };
in
{
  options.nixie.security.remoteUnlock = {
    enable = mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Let you type the boot passphrase over SSH from another machine, using
        the SSH keys of the administrator. Needed for a server without a
        keyboard.
      '';
      nixieUi = {
        section = "security";
        order = 6;
      };
    };
    port = mkOption {
      type = lib.types.port;
      default = 2222;
      description = "Port the early-boot SSH server listens on.";
      nixieUi = {
        section = "security";
        order = 7;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.nixie.security.encryption.enable;
        message = "nixie.security.remoteUnlock.enable needs nixie.security.encryption.enable";
      }
      {
        assertion = config.nixie.auth.sshKeys != [ ];
        message = "nixie.security.remoteUnlock.enable needs at least one key in nixie.auth.sshKeys";
      }
    ];

    boot.initrd.network.enable = true;
    boot.initrd.systemd.network.enable = true;
    boot.initrd.systemd.network.networks."10-nixie-uplink" = {
      matchConfig.MACAddress = lib.concatStringsSep " " net.bridge.uplinks;
      networkConfig.DHCP = lib.mkIf (net.address == null) "yes";
      address = lib.optional (net.address != null) net.address;
      gateway = lib.optional (net.gateway != null) net.gateway;
    };

    # The host key lives on the boot partition, next to the initrd it serves,
    # so it is neither in the Nix store nor inside a signed image.
    boot.initrd.availableKernelModules = [
      "vfat"
      "nls_cp437"
      "nls_iso8859-1"
    ];
    boot.initrd.systemd.services.nixie-initrd-host-key = {
      description = "Load the early-boot SSH host key from the boot partition";
      wantedBy = [ "initrd.target" ];
      requiredBy = [ "sshd.service" ];
      before = [ "sshd.service" ];
      after = [ espUnit ];
      requires = [ espUnit ];
      unitConfig.DefaultDependencies = false;
      serviceConfig.Type = "oneshot";
      script = ''
        mkdir -p /run/nixie/esp
        mount -t vfat -o ro ${esp} /run/nixie/esp
        install -m 0600 /run/nixie/esp/nixie/ssh_host_ed25519_key /run/nixie/ssh_host_ed25519_key
        umount /run/nixie/esp
      '';
    };
    boot.initrd.network.ssh = {
      enable = true;
      inherit (cfg) port;
      authorizedKeys = config.nixie.auth.sshKeys;
      hostKeys = [ ];
      ignoreEmptyHostKeys = true;
      extraConfig = "HostKey /run/nixie/ssh_host_ed25519_key";
    };
    boot.initrd.systemd.storePaths = [ relay ];
    # Above mkDefault: nixpkgs sets this shell with mkDefault too, and two
    # definitions at one priority stopped every host with remote unlock from
    # evaluating. A site's own plain definition still wins.
    boot.initrd.systemd.users.root.shell = lib.mkOverride 900 "${relay}/bin/nixie-unlock-relay";
  };
}
