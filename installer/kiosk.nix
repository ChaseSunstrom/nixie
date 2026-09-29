# A Wayland kiosk: cage running a browser full screen on one URL. Used by
# the ISO and the setup generation for the wizard, and by the console slice
# for the control panel. One module, parameters only.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  template = import ../lib/template.nix lib;
  # The pairing token the kiosk uses to open the page without a code; it is
  # written while the browser starts, so the script waits for it.
  tokenSetup = lib.optionalString (cfg.tokenFile != "") ''
    for _ in $(seq 20); do [ -r ${lib.escapeShellArg cfg.tokenFile} ] && break; sleep 0.5; done
    if [ -r ${lib.escapeShellArg cfg.tokenFile} ]; then
      url="$url?token=$(cat ${lib.escapeShellArg cfg.tokenFile})"
    fi
  '';
  inherit (import ../lib/option.nix lib) mkOption;
  cfg = config.nixie.kiosk;
  browser = pkgs.writeShellApplication {
    name = "nixie-kiosk-browser";
    runtimeInputs = [
      pkgs.chromium
      pkgs.coreutils
      pkgs.curl
    ];
    text = template.fill ./kiosk-browser.sh {
      url = lib.escapeShellArg cfg.url;
      token = tokenSetup;
      debug =
        if cfg.remoteDebugPort == null then
          ""
        else
          # The address as well: bound to the loopback it cannot be reached
          # from outside the machine at all, which is the whole point here.
          # The address, because bound to the loopback it cannot be reached
          # from outside the machine at all, which is the whole point here;
          # and the origins, because Chromium hangs up on a debugger
          # websocket that comes from anywhere but itself.
          "--remote-debugging-address=0.0.0.0 --remote-allow-origins=* --remote-debugging-port=${toString cfg.remoteDebugPort}";
    };
  };
in
{
  options.nixie.kiosk = {
    enable = mkOption {
      type = lib.types.bool;
      default = false;
      description = "Internal: show one web page full screen on the local display.";
    };
    url = mkOption {
      type = lib.types.str;
      default = "https://127.0.0.1:9443/";
      description = "Internal: the page the kiosk shows.";
    };
    remoteDebugPort = mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = ''
        Internal, and for a test image only: open this browser's debugger
        on this port, on every interface, so a test can drive the page the
        way a person at the screen would. Anything that reaches the port
        drives the browser, which is why nothing the platform ships sets it:
        `packages.nixie-iso-kiosk` is the one image that does, and
        `nixie-test-iso --kiosk` is what boots it.
      '';
    };
    tokenFile = mkOption {
      type = lib.types.str;
      default = "/run/nixie-setup/local-token";
      description = "Internal: a file whose content is appended as ?token= so the local browser pairs itself.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.nixie-kiosk = {
      isSystemUser = true;
      group = "nixie-kiosk";
      home = "/var/lib/nixie-kiosk";
      createHome = true;
      extraGroups = [
        "video"
        "input"
      ];
    };
    users.groups.nixie-kiosk = { };
    services.cage = {
      enable = true;
      user = "nixie-kiosk";
      program = lib.getExe browser;
      # -s: cage otherwise swallows Ctrl+Alt+Fn, and the terminal wizard on
      # tty2 is the way out when the page cannot be used.
      extraArguments = [
        "-d"
        "-s"
      ];
      # wlroots falls back to software rendering only for a GPU without a
      # render node. One that has a render node but no OpenGL, like VirtualBox
      # and VMware without 3D acceleration, fails with "Unable to create the
      # wlroots renderer" instead, so that start is retried in software.
      # A GPU driver that loads late (seen in a slow VM; NVIDIA's can too)
      # has no card yet when this starts, and cage gives up with "Found 0
      # GPUs"; it is waited for, up to half a minute.
      package = pkgs.writeShellScriptBin "cage" ''
        for _ in $(seq 60); do ls /dev/dri/card* >/dev/null 2>&1 && break; sleep 0.5; done
        ${pkgs.cage}/bin/cage "$@" || WLR_RENDERER=pixman exec ${pkgs.cage}/bin/cage "$@"
      '';
    };
    # The screen must come back whatever ended it: a card that never came,
    # a browser that crashed, or one closed with Ctrl+W, left a bare console
    # nobody at the machine could get out of. A stop (Finish does one) stays
    # stopped.
    systemd.services.cage-tty1.serviceConfig = {
      Restart = "always";
      RestartSec = 2;
    };
    hardware.graphics.enable = true;
    # The minimal installer CD turns fontconfig off, and a browser without it
    # draws no text at all, not even the page's own web fonts.
    fonts.fontconfig.enable = true;
    fonts.packages = [ pkgs.jetbrains-mono ];
  };
}
