# `nixie menu`: finishes, wallpapers, packages, update, keybinds, system
# info. It edits the site config, shows the diff, and runs `nixie apply`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  template = import ../../lib/template.nix lib;
  cfg = config.nixie.desktop;
  menu = pkgs.writeShellApplication {
    name = "nixie-menu";
    runtimeInputs = with pkgs; [
      gum
      git
      gnused
      coreutils
      diffutils
    ];
    text = template.fill ./menu.sh {
      inherit (cfg) finish;
      sitePath = config.nixie.site.path;
    };
  };
  desktopEntry = pkgs.makeDesktopItem {
    name = "nixie-menu";
    desktopName = "Nixie menu";
    comment = "Finish, wallpaper, packages, update, keybinds, system info";
    exec = "${
      if cfg.defaultApps.terminal == null then "kitty" else cfg.defaultApps.terminal
    } -e nixie-menu";
    icon = "preferences-system";
    categories = [ "Settings" ];
  };
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      menu
      desktopEntry
    ];
    # The menu applies through sudo; the admin is in wheel and asked for the password.
  };
}
