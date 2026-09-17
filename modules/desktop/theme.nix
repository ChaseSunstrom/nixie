# One token source for everything on the desktop. Every finish's assets are
# built and shipped under /etc/nixie/desktop/<finish>/, so the active finish
# is a per-user choice (`nixie-shell finish`) and needs no rebuild; the site
# option is the default a new session starts with.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  template = import ../../lib/template.nix lib;
  inherit (import ../../lib/option.nix lib) mkOption;
  cfg = config.nixie.desktop;
  tk = import ../../lib/tokens.nix { inherit lib; };
  # Every finish the desktop knows: the three built in, the site's own, and
  # any HyDE theme it points at (read as data, never run).
  imported = lib.mapAttrs (
    _: dir: import ../../lib/hyde-theme.nix { inherit lib; } dir
  ) cfg.hyde.themes;
  siteThemes = lib.mapAttrs (_: v: {
    inherit (v) colors dark;
    wallpapers = v.wallpapers or null;
  }) (cfg.themes // imported);
  finishes = tk.finishes ++ lib.attrNames siteThemes;
  tokensOf =
    f:
    if lib.elem f tk.finishes then
      tk.forFinish f
    else
      tk.forFinish "graphite"
      // siteThemes.${f}.colors
      // {
        name = f;
        inherit (siteThemes.${f}) dark;
      };
  wallpapersOf =
    f:
    if (siteThemes.${f}.wallpapers or null) != null then siteThemes.${f}.wallpapers else wallpapers f;
  t = tokensOf cfg.finish;
  uiFont = cfg.fonts.ui;
  monoFont = cfg.fonts.mono;

  # Three procedural wallpapers per finish: a smooth mesh of the finish's
  # surfaces with one accent blob, grain, and (on the first) the mark.
  wallpapers =
    f:
    let
      c = tokensOf f;
      mesh = n: pts: ''
        magick -size 3840x2160 xc: -sparse-color Shepards '${pts}' -blur 0x120 \
          \( +clone -fx 'rand()*0.03' -colorspace gray \) -compose overlay -composite \
          -quality 92 $out/${f}-${toString n}.png
      '';
    in
    pkgs.runCommand "nixie-wallpapers-${f}" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
      mkdir -p $out
      ${mesh 1 "0,0 ${c.bg} 3840,0 ${c.s2} 0,2160 ${c.s1} 3840,2160 ${c.bg} 2700,700 ${c.brand} 900,1600 ${c.s3}"}
      ${mesh 2 "0,0 ${c.s2} 3840,0 ${c.bg} 0,2160 ${c.bg} 3840,2160 ${c.s3} 600,500 ${c.brand2} 3100,1800 ${c.s1}"}
      ${mesh 3 "0,0 ${c.bg} 3840,0 ${c.s1} 0,2160 ${c.s3} 3840,2160 ${c.s2} 1920,1080 ${c.brand} 300,1900 ${c.brand2}"}
      # The Segment n mark, quiet, bottom right of the first one.
      magick $out/${f}-1.png \
        \( -size 3840x2160 xc:none -fill "${c.brand}" -draw "roundrectangle 3336,1785 3372,1944 11,11" -draw "roundrectangle 3336,1785 3524,1821 11,11" \
           -fill "${c.brand2}" -draw "roundrectangle 3488,1785 3524,1944 11,11" \) \
        -compose over -composite $out/${f}-1.png
    '';

  gtkCss = c: pkgs.writeText "gtk.css" (template.fill ./finish/gtk.css (tk.marks c));

  kittyColors =
    c: pkgs.writeText "kitty-colors.conf" (template.fill ./finish/kitty-colors.conf (tk.marks c));

  hyprlockConf =
    c: f:
    pkgs.writeText "hyprlock.conf" (
      template.fill ./finish/hyprlock.conf (
        tk.marks c
        // {
          wallpaper = "${wallpapers f}/${f}-1.png";
          dim = if c.dark then "0.7" else "1.05";
          inherit uiFont monoFont;
        }
      )
    );

  # Everything one finish needs, in one directory.
  finishDir =
    f:
    let
      c = tokensOf f;
    in
    pkgs.runCommand "nixie-desktop-${f}" { } ''
      mkdir -p $out
      cp ${
        pkgs.writeText "tokens.json" (
          builtins.toJSON (
            c
            // {
              finish = f;
              fontUi = uiFont;
              fontMono = monoFont;
              iconTheme = if c.dark then "Papirus-Dark" else "Papirus";
              inherit (cfg.look) rounding;
            }
          )
        )
      } $out/tokens.json
      cp ${gtkCss c} $out/gtk.css
      cp ${kittyColors c} $out/kitty.conf
      cp ${hyprlockConf c f} $out/hyprlock.conf
      ln -s "${wallpapersOf f}" $out/wallpapers
    '';
in
{
  options.nixie.desktop.finishes = mkOption {
    type = lib.types.listOf lib.types.str;
    default = finishes;
    readOnly = true;
    description = "Internal: every finish this desktop offers, built in and from the site.";
  };

  options.nixie.desktop.tokens = mkOption {
    type = lib.types.attrs;
    default = t;
    readOnly = true;
    description = "Internal: the colours of the chosen finish, for what draws before a session (the login screen, the boot splash).";
  };

  options.nixie.desktop.wallpaperPath = mkOption {
    type = lib.types.str;
    # The generated set is reached through /etc so a finish switch can tell
    # "one of ours" from a person's own image.
    default =
      if cfg.wallpaper != null then
        toString cfg.wallpaper
      else if lib.elem cfg.finish tk.finishes then
        "/etc/nixie/desktop/${cfg.finish}/wallpapers/${cfg.finish}-1.png"
      else
        "/etc/nixie/desktop/${cfg.finish}/wallpapers";
    readOnly = true;
    description = "Internal: the wallpaper a session starts with.";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.elem cfg.finish finishes;
        message = "nixie.desktop.finish is \"${cfg.finish}\", which is not one of this desktop's finishes: ${lib.concatStringsSep ", " finishes}";
      }
    ];
    environment.etc =
      lib.listToAttrs (map (f: lib.nameValuePair "nixie/desktop/${f}" { source = finishDir f; }) finishes)
      // {
        # The declared default; the shell and scripts read the per-user choice first.
        "nixie/desktop/tokens.json".source = "${finishDir cfg.finish}/tokens.json";
        "nixie/desktop/default-finish".text = cfg.finish;
        "nixie/desktop/settings.json".text = builtins.toJSON {
          inherit (cfg)
            favourites
            clock
            accentFromWallpaper
            wallpaperCycle
            ;
          workspaces = cfg.workspaces.labels;
          inherit (cfg.look) barPosition;
          wallpapers = if cfg.wallpapers == null then null else toString cfg.wallpapers;
          wallpaper = cfg.wallpaperPath;
          inherit (cfg.look) cursor;
          inherit (cfg.look) rounding;
          inherit (cfg.look) blur;
          inherit (cfg.look) systemReadouts;
          visualiser = cfg.audioVisualiser.enable;
          inherit finishes;
          swatches = lib.listToAttrs (map (f: lib.nameValuePair f (tokensOf f).bg) finishes);
        };
        "xdg/gtk-3.0/settings.ini".text = ''
          [Settings]
          gtk-application-prefer-dark-theme=${if t.dark then "1" else "0"}
          gtk-theme-name=adw-gtk3${lib.optionalString t.dark "-dark"}
          gtk-icon-theme-name=${cfg.look.iconTheme}
          gtk-font-name=${uiFont} 11
          gtk-cursor-theme-name=${cfg.look.cursor.theme}
          gtk-cursor-theme-size=${toString cfg.look.cursor.size}
          gtk-decoration-layout=:close
        '';
        "xdg/gtk-4.0/settings.ini".text = config.environment.etc."xdg/gtk-3.0/settings.ini".text;
        "xdg/kitty/kitty.conf".text = template.fill ./conf/kitty.conf {
          inherit monoFont;
          opacity = cfg.look.terminalOpacity;
        };
        "xdg/nvim/sysinit.vim".text = template.fill ./conf/sysinit.vim (tk.marks t);
        "xdg/starship.toml".text = template.fill ./conf/starship.toml (tk.marks t);
        "xdg/fastfetch/config.jsonc".text = builtins.toJSON {
          logo = {
            type = "file";
            source = "/etc/nixie/desktop/mark.txt";
            color = {
              "1" = "blue";
              "2" = "cyan";
            };
            padding.right = 3;
          };
          display.separator = "  ";
          modules = [
            "title"
            "separator"
            "os"
            "kernel"
            "wm"
            "uptime"
            "packages"
            "cpu"
            "gpu"
            "memory"
            "disk"
            "colors"
          ];
        };
        "nixie/desktop/mark.txt".source = ./conf/mark.txt;
      };
    qt = {
      enable = true;
      platformTheme = "gtk2";
      style = "adwaita${lib.optionalString t.dark "-dark"}";
    };
    # Firefox accent through a policy: no extension, no profile edits.
    programs.firefox = {
      enable = true;
      policies.Preferences = {
        "browser.theme.content-theme" = {
          Value = if t.dark then 0 else 1;
          Status = "default";
        };
        "browser.theme.toolbar-theme" = {
          Value = if t.dark then 0 else 1;
          Status = "default";
        };
      };
    };
    environment.variables.NIXIE_FINISH = cfg.finish;
    environment.systemPackages = with pkgs; [
      adw-gtk3
      papirus-icon-theme
      bibata-cursors
      starship
      fastfetch
    ];
    fonts.packages = [
      (pkgs.google-fonts.override { fonts = [ "Archivo" ]; })
      pkgs.material-symbols
    ];
  };
}
