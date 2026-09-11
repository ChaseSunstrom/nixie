{
  config,
  lib,
  ...
}:
let
  inherit (import ../../lib/option.nix lib) mkOption;

  t = lib.types;
  categories = [
    "browsers"
    "terminals"
    "editors"
    "media"
    "office"
    "communication"
    "gaming"
    "creative"
  ];
in
{
  options.nixie.desktop = {
    user = mkOption {
      type = t.str;
      default = config.nixie.auth.admin.name;
      defaultText = "the administrator";
      description = "The account that gets the desktop session.";
    };
    finish = mkOption {
      type = t.enum [
        "graphite"
        "umber"
        "paper"
      ];
      default = config.nixie.ui.theme;
      defaultText = "nixie.ui.theme";
      description = "The finish for the whole desktop: bar, windows, terminal, editor and apps.";
      nixieUi = {
        section = "desktop";
        order = 1;
      };
    };
    wallpaper = mkOption {
      type = t.nullOr t.path;
      default = null;
      description = "An image for the desktop background. Empty means a plain one matching the finish.";
      nixieUi = {
        section = "desktop";
        order = 2;
      };
    };
    accentFromWallpaper = mkOption {
      type = t.bool;
      default = false;
      description = "Pick the accent colour from the wallpaper instead of the finish.";
    };
    keyboard.layout = mkOption {
      type = t.str;
      default = "us";
      description = "Keyboard layout.";
      nixieUi = {
        section = "desktop";
        order = 3;
      };
    };
    keyboard.variant = mkOption {
      type = t.str;
      default = "";
      description = "Keyboard layout variant, if any.";
      nixieUi = {
        section = "desktop";
        order = 4;
      };
    };
    monitors = mkOption {
      type = t.listOf (
        t.submodule {
          options = {
            name = mkOption {
              type = t.str;
              description = "Output name.";
            };
            mode = mkOption {
              type = t.str;
              default = "preferred";
              description = "Resolution and refresh rate, or \"preferred\".";
            };
            position = mkOption {
              type = t.str;
              default = "auto";
              description = "Position, or \"auto\".";
            };
            scale = mkOption {
              type = t.str;
              default = "1";
              description = "Scale factor.";
            };
          };
        }
      );
      default = [ ];
      description = "Per-monitor settings. Empty means every monitor at its preferred mode.";
      nixieUi = {
        section = "desktop";
        order = 5;
      };
    };
    keybinds = mkOption {
      type = t.attrsOf t.str;
      default = { };
      example = {
        "SUPER, Return" = "exec, kitty";
      };
      description = "Key bindings added to or replacing the platform set.";
    };
    autostart = mkOption {
      type = t.listOf t.str;
      default = [ ];
      description = "Commands run when the session starts.";
    };
    defaultApps = lib.genAttrs [ "browser" "terminal" "editor" "fileManager" ] (
      n:
      mkOption {
        type = t.nullOr t.str;
        default = null;
        description = "Desktop entry name of the default ${n}.";
      }
    );
    packages.categories = lib.genAttrs categories (
      c:
      mkOption {
        type = t.listOf t.str;
        default = [ ];
        description = "Package names in the ${c} category, chosen in the installer.";
        nixieUi = {
          section = "desktop";
          order = 6;
        };
      }
    );
    packages.extra = mkOption {
      type = t.listOf t.package;
      default = [ ];
      description = "Any other packages.";
    };
    flatpak.enable = mkOption {
      type = t.bool;
      default = false;
      description = "Also allow Flatpak apps. Off by default because they are not declared in the site.";
      nixieUi = {
        section = "desktop";
        order = 7;
      };
    };
    power.backend = mkOption {
      type = t.enum [
        "power-profiles-daemon"
        "tlp"
      ];
      default = "power-profiles-daemon";
      description = "Which power manager to use on a laptop.";
    };
    power.lid = mkOption {
      type = t.enum [
        "suspend"
        "lock"
        "ignore"
      ];
      default = "suspend";
      description = "What closing the lid does.";
    };
    idle.lockAfter = mkOption {
      type = t.int;
      default = 300;
      description = "Seconds of inactivity before the screen locks.";
    };
    idle.screenOffAfter = mkOption {
      type = t.int;
      default = 600;
      description = "Seconds of inactivity before the screen turns off.";
    };
    idle.suspendAfter = mkOption {
      type = t.nullOr t.int;
      default = null;
      description = "Seconds of inactivity before suspend. Empty means never.";
    };
    nightLight.enable = mkOption {
      type = t.bool;
      default = true;
      description = "Warm the screen colours in the evening.";
    };
    overview.enable = mkOption {
      type = t.bool;
      default = true;
      description = "An overview of all workspaces on one key.";
    };
  };
}
