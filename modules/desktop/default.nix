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
      description = ''
        The finish for the whole desktop: bar, windows, terminal, editor and
        apps. This is the default; the control centre can switch it for a
        person without a rebuild.
      '';
      nixieUi = {
        section = "desktop";
        order = 1;
      };
    };
    wallpaper = mkOption {
      type = t.nullOr t.path;
      default = null;
      description = "An image for the desktop background. Empty means the generated set for the finish.";
      nixieUi = {
        section = "desktop";
        order = 2;
      };
    };
    wallpapers = mkOption {
      type = t.nullOr t.path;
      default = null;
      description = "A folder of your own images for the wallpaper picker, on top of the generated ones.";
    };
    wallpaperCycle = mkOption {
      type = t.nullOr t.int;
      default = null;
      description = "Minutes between automatic wallpaper changes. Empty means never.";
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
        "SUPER + Return" = "kitty";
      };
      description = "Extra key bindings: a key combination to a command, added to the platform set.";
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
    favourites = mkOption {
      type = t.listOf t.str;
      default = [ ];
      example = [
        "firefox"
        "kitty"
      ];
      description = "Desktop entry ids pinned at the top of the launcher.";
    };
    workspaces.labels = mkOption {
      type = t.listOf t.str;
      default = [ ];
      example = [
        "web"
        "code"
        "chat"
      ];
      description = "Names shown for workspaces 1, 2, 3… in the bar. Empty means numbers.";
    };
    clock.format = mkOption {
      type = t.str;
      default = "ddd d MMM  HH:mm";
      description = "The bar clock, in Qt date format.";
    };
    look = {
      gaps.inner = mkOption {
        type = t.int;
        default = 6;
        description = "Space between windows, in pixels.";
      };
      gaps.outer = mkOption {
        type = t.int;
        default = 14;
        description = "Space between windows and the screen edge, in pixels.";
      };
      rounding = mkOption {
        type = t.int;
        default = 12;
        description = "Corner radius of windows, in pixels.";
      };
      borderSize = mkOption {
        type = t.int;
        default = 2;
        description = "Window border width, in pixels.";
      };
      blur = mkOption {
        type = t.bool;
        default = true;
        description = "Blur behind translucent windows and the shell.";
      };
      animations = mkOption {
        type = t.enum [
          "full"
          "reduced"
          "none"
        ];
        default = "full";
        description = "Window and workspace motion: the full set, faster and fewer, or none.";
      };
      barPosition = mkOption {
        type = t.enum [
          "top"
          "bottom"
        ];
        default = "top";
        description = "Where the bar sits.";
      };
      terminalOpacity = mkOption {
        type = t.float;
        default = 0.92;
        description = "Background opacity of the terminal, 0 to 1.";
      };
      cursor.theme = mkOption {
        type = t.str;
        default =
          if config.nixie.desktop.finish == "paper" then "Bibata-Modern-Ice" else "Bibata-Modern-Classic";
        defaultText = "Bibata, light on paper";
        description = "Cursor theme.";
      };
      cursor.size = mkOption {
        type = t.int;
        default = 24;
        description = "Cursor size in pixels.";
      };
      systemReadouts = mkOption {
        type = t.bool;
        default = true;
        description = "Show processor, memory and temperature readouts in the bar.";
      };
      iconTheme = mkOption {
        type = t.str;
        default = if config.nixie.desktop.finish == "paper" then "Papirus" else "Papirus-Dark";
        defaultText = "Papirus, dark on the dark finishes";
        description = "Icon theme for apps and the shell.";
      };
    };
    fonts.ui = mkOption {
      type = t.str;
      default = "Archivo";
      description = "The interface font.";
    };
    fonts.mono = mkOption {
      type = t.str;
      default = "JetBrains Mono";
      description = "The monospace font (terminal, readouts).";
    };
    themes = mkOption {
      type = t.attrsOf (
        t.submodule {
          options = {
            colors = mkOption {
              type = t.attrsOf t.str;
              default = { };
              example = {
                bg = "#1e1e2e";
                ink = "#cdd6f4";
                brand = "#89b4fa";
              };
              description = ''
                The colours of this theme. Any you leave out keep Graphite's
                value, so a handful is enough: bg, s1, s2, s3, line, line2,
                ink, muted, brand, brand2, ok, err, hot, cpu, mem, net, disk,
                ice, scrim.
              '';
            };
            dark = mkOption {
              type = t.bool;
              default = true;
              description = "Whether this is a dark theme (apps and the greeter follow).";
            };
            wallpapers = mkOption {
              type = t.nullOr t.path;
              default = null;
              description = "A folder of wallpapers for this theme. Empty means the generated ones.";
            };
          };
        }
      );
      default = { };
      example = {
        catppuccin-mocha.colors = {
          bg = "#1e1e2e";
          ink = "#cdd6f4";
          brand = "#89b4fa";
        };
      };
      description = ''
        Themes of your own, on top of Graphite, Umber and Paper. Each one
        appears in the control centre and in `nixie-shell finish <name>`,
        and colours the whole desktop the same way the built-in finishes do.
      '';
    };
    hyde.enable = mkOption {
      type = t.bool;
      default = false;
      description = ''
        Hand the desktop to HyDE itself instead of the Nixie one. Nixie stops
        configuring the session, the shell, Hyprland and the theme, and your
        site brings HyDE in (the hydenix flake is the packaged form). The
        rest of the platform is unchanged: the same installer, the same
        security options, the same `nixie` command. Off by default because
        HyDE is a large third-party desktop whose theme tool downloads themes
        at the moment you switch them, which the Nixie desktop never does.
      '';
      nixieUi = {
        section = "desktop";
        order = 9;
      };
    };
    hyde.themes = mkOption {
      type = t.attrsOf t.path;
      default = { };
      example = {
        catppuccin-mocha = "/path/to/hyde-themes/Configs/.config/hyde/themes/Catppuccin Mocha";
      };
      description = ''
        HyDE themes to offer alongside the built-in finishes, as a name and
        the theme's own directory. Its colours and wallpapers are read as
        data at build time, so nothing is downloaded or run on the machine.
        Pin the theme repository as a flake input and point at a directory
        inside it.
      '';
    };
    audioVisualiser.enable = mkOption {
      type = t.bool;
      default = false;
      description = "Draw a spectrum of whatever is playing in the control centre. Costs a small background process.";
    };
    terminal.greeting = mkOption {
      type = t.bool;
      default = true;
      description = "Show system facts (fastfetch) when a terminal opens.";
    };
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
