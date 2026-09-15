# What runs on the installer, ISO or kexec image: the phase engine, the
# setup service with the wizard, and one of three ways to drive it from this
# machine (nixie.installer.mode). The ISO module wraps this in the CD image
# and offers each mode as a boot menu entry.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../lib/option.nix lib) mkOption;
  cfg = config.nixie.installer;
  graphical = cfg.mode == "graphical";
  web = cfg.mode != "terminal";
  # The terminal wizard owns tty1 when it is the chosen front end and tty2
  # otherwise, so it is always one key chord away.
  wizardTty = if cfg.mode == "terminal" then "tty1" else "tty2";
  # tty1 in web mode, and in graphical mode when the display cannot run the
  # kiosk: the address, pairing code and fingerprint, redrawn when they change.
  banner = pkgs.writeShellScript "nixie-banner" ''
    f=/var/lib/nixie/setup/banner.txt; last=""
    while :; do
      now=$(${pkgs.coreutils}/bin/stat -c %Y "$f" 2>/dev/null || echo none)
      if [ "$now" != "$last" ]; then
        last=$now
        printf '\033[2J\033[H'
        ${pkgs.coreutils}/bin/cat "$f" 2>/dev/null || printf '\n  Starting the setup service...\n'
        printf '\n  Terminal installer: press Alt+F2.\n'
      fi
      ${pkgs.coreutils}/bin/sleep 2
    done
  '';
  onTty = tty: {
    StandardInput = "tty";
    StandardOutput = "tty";
    StandardError = "tty";
    TTYPath = "/dev/${tty}";
    TTYReset = true;
    TTYVHangup = true;
    Restart = "always";
    RestartSec = 2;
  };
in
{
  imports = [ ./kiosk.nix ];

  options.nixie.installer = {
    packages = mkOption {
      type = lib.types.attrsOf lib.types.package;
      description = "Internal: nixie-setup, nixie-installer, nixie-cli and deploy as built by the platform flake.";
    };
    toplevel = mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Internal (tests): a prebuilt system to install instead of building the site.";
    };
    disko = mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Internal (tests): the prebuilt disko script for that system.";
    };
    mode = mkOption {
      type = lib.types.enum [
        "graphical"
        "web"
        "terminal"
      ];
      default = "graphical";
      description = ''
        Internal: how the installer is driven. graphical shows the wizard on
        this screen, web shows the address and pairing code for a browser on
        another device, terminal runs the text wizard on this screen. The
        setup service listens on the network in graphical and web modes.
      '';
    };
  };

  config = {
    environment.systemPackages = [
      cfg.packages.nixie-installer
      cfg.packages.nixie-setup
      cfg.packages.nixie-cli
      cfg.packages.deploy
      pkgs.gum
      pkgs.git
      pkgs.jq
    ];
    environment.etc."nixie-iso".text = "nixie installer\n";
    # Phase 3 evaluates the site flake and nixos-install builds it; installed
    # hosts get the same setting from modules/base.nix.
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    # The installer's root and store overlay are RAM, and evaluating a site
    # takes about 2 GB on its own: on a 4 GB machine phase 3 was killed for
    # memory. Compressed swap in RAM gives the evaluator's heap room.
    zramSwap = {
      enable = true;
      memoryPercent = 100;
    };

    boot.supportedFilesystems.zfs = true;
    networking.hostId = lib.mkDefault "8425e349";
    networking.useDHCP = lib.mkDefault true;
    networking.firewall.allowedTCPPorts = [ 22 ] ++ lib.optional web 9443;
    services.openssh.enable = true;
    # The person turns SSH on from the terminal wizard by setting a root
    # password; until then there is nothing to log in with.
    services.openssh.settings.PermitRootLogin = "yes";

    security.tpm2.enable = true;
    boot.initrd.availableKernelModules = [
      "tpm_tis"
      "tpm_crb"
    ];

    systemd.services.nixie-setup = lib.mkIf web {
      description = "Nixie setup service (installer)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        # exposure: runs the phase scripts as root; that is its whole purpose.
        ExecStart =
          "${lib.getExe cfg.packages.nixie-setup} --mode iso --cert-dir /var/lib/nixie/setup-cert"
          + lib.optionalString (cfg.toplevel != null) " --toplevel ${cfg.toplevel}"
          + lib.optionalString (cfg.disko != null) " --disko ${cfg.disko}";
        Restart = "on-failure";
        # The kiosk user reads the local token the setup service writes.
        ExecStartPost = lib.mkIf graphical (
          pkgs.writeShellScript "share-token" ''
            for _ in $(seq 50); do [ -e /run/nixie-setup/local-token ] && break; sleep 0.2; done
            chgrp nixie-kiosk /run/nixie-setup /run/nixie-setup/local-token
            chmod 750 /run/nixie-setup; chmod 640 /run/nixie-setup/local-token
          ''
        );
      };
    };

    nixie.kiosk.enable = graphical;
    # A display the kiosk cannot drive must still say where to go next.
    systemd.services.cage-tty1.onFailure = lib.mkIf graphical [ "nixie-banner.service" ];

    systemd.services.nixie-banner = lib.mkIf web {
      description = "Nixie setup address on tty1";
      wantedBy = lib.mkIf (!graphical) [ "multi-user.target" ];
      after = [ "nixie-setup.service" ];
      # exposure: root with a console; it only prints the banner file.
      serviceConfig = onTty "tty1" // {
        ExecStart = banner;
      };
    };

    # tty1 always belongs to the installer, tty2 too unless the wizard is on
    # tty1. logind spawns autovt@ttyN when someone switches to an unused VT,
    # and a getty there fights the owner for the keyboard, so both instance
    # names are masked.
    systemd.services."getty@tty1".enable = false;
    systemd.services."autovt@tty1".enable = false;
    systemd.services."getty@tty2" = lib.mkIf web { enable = false; };
    systemd.services."autovt@tty2" = lib.mkIf web { enable = false; };
    systemd.services.nixie-terminal = {
      description = "Nixie terminal wizard on ${wizardTty}";
      wantedBy = [ "multi-user.target" ];
      after = lib.optional web "nixie-setup.service";
      # The wizard writes the site with nixie-setup and offers a shell.
      path = [ "/run/current-system/sw" ];
      # exposure: the installer itself; it partitions disks as root.
      serviceConfig = onTty wizardTty // {
        ExecStart = "${lib.getExe cfg.packages.deploy} --local";
      };
    };
  };
}
