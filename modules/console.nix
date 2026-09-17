# The local console: the front panel on the first text console, and an
# optional permanent kiosk showing the control panel behind a lock page.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  template = import ../lib/template.nix lib;
  inherit (import ../lib/option.nix lib) mkOption;
  cfg = config.nixie.console;
  panel = import ../packages/nixie-panel.nix { inherit pkgs; };
  server = config.nixie.profile == "server";
  # The setup generation owns tty1 while setup is pending; the kiosk keeps
  # tty1 when it is on, so the panel moves to tty2.
  panelTty = if cfg.kiosk.enable then "tty2" else "tty1";
  # The lock page is the setup pairing card in the host's finish.
  tk = import ../lib/tokens.nix { inherit lib; };
  t = tk.forFinish config.nixie.ui.theme;
  lockPage = pkgs.writeText "lock.html" (template.fill ./console/lock.html (tk.marks t));
  # A small local gate: the kiosk checks the password with `unix_chkpwd`, the
  # pam_unix helper (it reads the password from stdin, so no terminal is
  # needed), and, when TOTP is enrolled, the code against the same file the
  # host page uses.
  gate = pkgs.writeShellApplication {
    name = "nixie-kiosk-gate";
    runtimeInputs = with pkgs; [
      python3
      coreutils
      oath-toolkit
    ];
    text = template.fill ./console/kiosk-gate.sh { inherit lockPage; };
  };
in
{
  imports = [ ../installer/kiosk.nix ];

  options.nixie.console = {
    frontPanel.enable = mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        A status screen on the first text console instead of a bare login:
        host name, addresses, the control panel address as a QR code, each
        guest as a lane with its state, GPU temperature, pool usage, and
        anything `nixie doctor` would flag, drawn in the chosen finish. Any
        key opens the normal login. The other consoles stay ordinary logins.
      '';
      nixieUi = {
        section = "services";
        order = 7;
      };
    };
    kiosk.enable = mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Keep the setup kiosk permanently and point it at the control panel,
        so the local display shows the full web page behind a lock page that
        checks the administrator password and second factor. Costs a
        compositor and a browser in the server closure.
      '';
      nixieUi = {
        section = "services";
        order = 8;
      };
    };
    kiosk.idleLock = mkOption {
      type = lib.types.str;
      default = "10m";
      description = "Re-lock the kiosk after this much inactivity.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (server && cfg.frontPanel.enable && !config.nixie.setup.pending) {
      environment.etc."nixie/ui.json".text = builtins.toJSON {
        inherit (config.nixie.ui) theme;
        uiPort = config.nixie.incus.ui.port;
      };
      systemd.services."getty@${panelTty}".enable = false;
      systemd.services.nixie-panel = {
        description = "Nixie front panel on ${panelTty}";
        # `r`/`b` on the panel run the nixie CLI from the system profile.
        path = [ "/run/current-system/sw" ];
        wantedBy = [ "multi-user.target" ];
        after = [
          "incus.service"
          "systemd-user-sessions.service"
          # The splash holds the console until it quits.
          "plymouth-quit-wait.service"
        ];
        conflicts = [ "getty@${panelTty}.service" ];
        serviceConfig = {
          # exposure: owns a console and execs login(1); it must run as root.
          ExecStart = "${lib.getExe panel} /dev/${panelTty}";
          StandardInput = "tty";
          StandardOutput = "tty";
          TTYPath = "/dev/${panelTty}";
          TTYReset = true;
          TTYVHangup = true;
          Restart = "always";
          RestartSec = 1;
        };
      };
    })
    (lib.mkIf (server && cfg.kiosk.enable && !config.nixie.setup.pending) {
      nixie.kiosk = {
        enable = true;
        url = "http://127.0.0.1:9444/";
        tokenFile = "";
      };
      systemd.services.nixie-kiosk-gate = {
        description = "Lock page in front of the local control panel";
        wantedBy = [ "multi-user.target" ];
        before = [ "cage-tty1.service" ];
        serviceConfig = {
          # exposure: checks the admin password through unix_chkpwd; loopback only.
          ExecStart = "${lib.getExe gate} ${config.nixie.auth.admin.name} ${
            toString (lib.toInt (lib.removeSuffix "m" cfg.kiosk.idleLock) * 60)
          } https://127.0.0.1:${toString config.nixie.incus.ui.port}/ui/";
          Restart = "on-failure";
        };
      };
    })
    (lib.mkIf server {
      # Prompts, the attestation code and the front panel must render on the
      # primary GPU. With the NVIDIA driver that needs modesetting and the
      # driver's own framebuffer.
      hardware.nvidia.modesetting.enable = lib.mkIf (config.nixie.hardware.gpu == "nvidia") true;
      # The open kernel modules are the supported choice on current cards; a
      # site with an older card sets this to false in its hardware.nix.
      hardware.nvidia.open = lib.mkIf (config.nixie.hardware.gpu == "nvidia") (lib.mkDefault true);
      boot.kernelParams = lib.optional (config.nixie.hardware.gpu == "nvidia") "nvidia-drm.fbdev=1";
      services.xserver.videoDrivers = lib.mkIf (config.nixie.hardware.gpu == "nvidia") [ "nvidia" ];
    })
  ];
}
