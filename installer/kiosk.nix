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
    ];
    text = ''
      url=${lib.escapeShellArg cfg.url}
      ${lib.optionalString (cfg.tokenFile != "") ''
        if [ -r ${lib.escapeShellArg cfg.tokenFile} ]; then
          url="$url?token=$(cat ${lib.escapeShellArg cfg.tokenFile})"
        fi
      ''}
      # The certificate is the setup service's own, made on this machine.
      exec chromium --kiosk --no-first-run --disable-translate --noerrdialogs \
        --disable-infobars --password-store=basic --ozone-platform=wayland \
        --ignore-certificate-errors --user-data-dir=/var/lib/nixie-kiosk/chromium "$url"
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
      extraArguments = [ "-d" ];
    };
    hardware.graphics.enable = true;
    fonts.packages = [ pkgs.jetbrains-mono ];
  };
}
