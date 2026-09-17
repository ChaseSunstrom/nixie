# Who owns this machine's screen while it is installed and set up: the wizard
# in a kiosk, the address and pairing code for a browser on another device,
# or the terminal wizard. The installer image and the setup generation both
# import this, so the front end chosen at the image's boot menu carries on
# through every reboot until Finish.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  template = import ../lib/template.nix lib;
  inherit (import ../lib/option.nix lib) mkOption;
  cfg = config.nixie.frontEnd;
  graphical = cfg.mode == "graphical";
  web = cfg.mode != "terminal";
  # The terminal wizard owns tty1 when it is the chosen front end and tty2
  # otherwise, so it is always one key chord away.
  wizardTty = if cfg.mode == "terminal" then "tty1" else "tty2";
  # tty1 in web mode, and in graphical mode when the display cannot run the
  # kiosk: the address, pairing code and fingerprint, redrawn when they change.
  banner = pkgs.writeShellScript "nixie-banner" (
    template.fill ./banner.sh { inherit (pkgs) coreutils; }
  );
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

  options.nixie.frontEnd = {
    mode = mkOption {
      type = lib.types.enum [
        "graphical"
        "web"
        "terminal"
      ];
      default = "graphical";
      description = ''
        Internal: how installing and setup are driven from here. graphical
        shows the wizard on this screen, web shows the address and pairing
        code for a browser on another device, terminal runs the text wizard on
        this screen. The setup service listens on the network in graphical
        and web modes.
      '';
    };
    terminal = mkOption {
      type = lib.types.str;
      description = "Internal: the command the terminal wizard runs.";
    };
  };

  config = lib.mkMerge [
    # The kiosk user reads the local token the setup service writes. The
    # condition wraps the unit name: under it, an empty nixie-setup unit would
    # appear in terminal mode.
    (lib.mkIf graphical {
      systemd.services.nixie-setup.serviceConfig.ExecStartPost = pkgs.writeShellScript "share-token" ''
        for _ in $(seq 50); do [ -e /run/nixie-setup/local-token ] && break; sleep 0.2; done
        chgrp nixie-kiosk /run/nixie-setup /run/nixie-setup/local-token
        chmod 750 /run/nixie-setup; chmod 640 /run/nixie-setup/local-token
      '';
    })
    {
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

      # tty1 always belongs to the front end, tty2 too unless the wizard is on
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
        # The wizard runs the phase scripts and offers a shell.
        path = [ "/run/current-system/sw" ];
        # exposure: the installer itself; it partitions disks as root.
        serviceConfig = onTty wizardTty // {
          ExecStart = cfg.terminal;
        };
      };
    }
  ];
}
