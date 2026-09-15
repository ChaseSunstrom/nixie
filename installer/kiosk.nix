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
  inherit (import ../lib/option.nix lib) mkOption;
  cfg = config.nixie.kiosk;
  browser = pkgs.writeShellApplication {
    name = "nixie-kiosk-browser";
    runtimeInputs = [
      pkgs.chromium
      pkgs.coreutils
      pkgs.curl
    ];
    text = ''
      url=${lib.escapeShellArg cfg.url}
      # The display comes up before the page's service can answer (the setup
      # service waits for the network), and a browser that starts first shows
      # a connection error, or the pairing form without the local token, whose
      # code is on the console this kiosk covers. Neither is retried, so wait.
      for _ in $(seq 300); do curl -sk --max-time 2 -o /dev/null "$url" && break; sleep 1; done
      ${lib.optionalString (cfg.tokenFile != "") ''
        for _ in $(seq 20); do [ -r ${lib.escapeShellArg cfg.tokenFile} ] && break; sleep 0.5; done
        if [ -r ${lib.escapeShellArg cfg.tokenFile} ]; then
          url="$url?token=$(cat ${lib.escapeShellArg cfg.tokenFile})"
        fi
      ''}
      # The certificate is the setup service's own, made on this machine.
      # --kiosk alone never goes full screen under cage on Wayland and leaves
      # the tab strip and address bar; --app opens a window without them.
      exec chromium --app="$url" --kiosk --start-fullscreen --no-first-run --disable-translate --noerrdialogs \
        --disable-infobars --password-store=basic --ozone-platform=wayland \
        --ignore-certificate-errors --user-data-dir=/var/lib/nixie-kiosk/chromium
    '';
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
      package = pkgs.writeShellScriptBin "cage" ''
        ${pkgs.cage}/bin/cage "$@" || WLR_RENDERER=pixman exec ${pkgs.cage}/bin/cage "$@"
      '';
    };
    hardware.graphics.enable = true;
    # The minimal installer CD turns fontconfig off, and a browser without it
    # draws no text at all, not even the page's own web fonts.
    fonts.fontconfig.enable = true;
    fonts.packages = [ pkgs.jetbrains-mono ];
  };
}
