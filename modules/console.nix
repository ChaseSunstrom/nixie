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
  totp = config.nixie.auth.secondFactor == "totp";
  lockPage = pkgs.writeText "lock.html" (
    template.fill ./console/lock.html (
      tk.marks t
      // {
        lead =
          if totp then
            "The administrator's password, and the code from the authenticator app."
          else
            "The administrator's password.";
        code = lib.optionalString totp ''<label>Code from the authenticator app<input name="code" inputmode="numeric" autocomplete="one-time-code" maxlength="6"></label>'';
      }
    )
  );
  panelPage = pkgs.writeText "panel.html" (template.fill ./console/panel.html (tk.marks t));
  # The lock in front of the local panel, and the panel's way to incusd
  # (console/kiosk-gate.py): the administrator's password through
  # `unix_chkpwd`, the pam_unix helper, and the authenticator code against
  # the secret the host page uses; incusd over its unix socket, so the kiosk
  # browser holds no certificate.
  gate = pkgs.writeScriptBin "nixie-kiosk-gate" (
    "#!${pkgs.python3}/bin/python3\n" + builtins.readFile ./console/kiosk-gate.py
  );
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
      # The lock checks the same authenticator the host page does; without
      # this it would have no secret to check against, and must not open.
      sops.secrets.totp-secret = lib.mkIf totp { };
      systemd.services.nixie-kiosk-gate = {
        description = "Lock page in front of the local control panel";
        wantedBy = [ "multi-user.target" ];
        before = [ "cage-tty1.service" ];
        after = [ "sops-nix.service" ];
        serviceConfig = {
          # exposure: root, to check the admin password through unix_chkpwd,
          # read the second factor's secret and reach incusd's socket;
          # loopback only.
          ExecStart = lib.escapeShellArgs [
            "${gate}/bin/nixie-kiosk-gate"
            config.nixie.auth.admin.name
            (toString (lib.toInt (lib.removeSuffix "m" cfg.kiosk.idleLock) * 60))
            (if totp then config.sops.secrets.totp-secret.path else "none")
            lockPage
            panelPage
            "/var/lib/incus/unix.socket"
          ];
          Restart = "always";
          RestartSec = 1;
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
