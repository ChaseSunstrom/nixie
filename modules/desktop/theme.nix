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
  rgb = c: "rgb(${tk.bare c})";

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

  gtkCss =
    c:
    pkgs.writeText "gtk.css" ''
      @define-color accent_bg_color ${c.brand};
      @define-color accent_fg_color #ffffff;
      @define-color accent_color ${c.brand2};
      @define-color window_bg_color ${c.bg};
      @define-color window_fg_color ${c.ink};
      @define-color view_bg_color ${c.s2};
      @define-color view_fg_color ${c.ink};
      @define-color card_bg_color ${c.s1};
      @define-color card_fg_color ${c.ink};
      @define-color headerbar_bg_color ${c.s1};
      @define-color headerbar_fg_color ${c.ink};
      @define-color headerbar_border_color ${c.line};
      @define-color popover_bg_color ${c.s1};
      @define-color popover_fg_color ${c.ink};
      @define-color dialog_bg_color ${c.s1};
      @define-color dialog_fg_color ${c.ink};
      @define-color sidebar_bg_color ${c.s1};
      @define-color sidebar_fg_color ${c.ink};
      @define-color borders ${c.line};
      @define-color theme_bg_color ${c.bg};
      @define-color theme_fg_color ${c.ink};
      @define-color theme_base_color ${c.s2};
      @define-color theme_text_color ${c.ink};
      @define-color theme_selected_bg_color ${c.brand};
      @define-color theme_selected_fg_color #ffffff;
    '';

  kittyColors =
    c:
    pkgs.writeText "kitty-colors.conf" ''
      background ${c.bg}
      foreground ${c.ink}
      cursor ${c.brand2}
      cursor_text_color ${c.bg}
      selection_background ${c.s3}
      selection_foreground ${c.ink}
      url_color ${c.brand2}
      active_border_color ${c.brand2}
      inactive_border_color ${c.line}
      active_tab_background ${c.s1}
      active_tab_foreground ${c.ink}
      inactive_tab_background ${c.s2}
      inactive_tab_foreground ${c.muted}
      tab_bar_background ${c.s2}
      color0 ${c.s2}
      color8 ${c.line2}
      color1 ${c.err}
      color9 ${c.err}
      color2 ${c.ok}
      color10 ${c.ok}
      color3 ${c.hot}
      color11 ${c.hot}
      color4 ${c.brand2}
      color12 ${c.cpu}
      color5 ${c.mem}
      color13 ${c.mem}
      color6 ${c.net}
      color14 ${c.ice}
      color7 ${c.muted}
      color15 ${c.ink}
    '';

  hyprlockConf =
    c: f:
    pkgs.writeText "hyprlock.conf" ''
      general {
        hide_cursor = true
        ignore_empty_input = true
      }
      background {
        path = ${wallpapers f}/${f}-1.png
        blur_passes = 3
        blur_size = 7
        brightness = ${if c.dark then "0.7" else "1.05"}
      }
      label {
        text = $TIME
        font_family = ${uiFont}
        font_size = 96
        color = ${rgb c.ink}
        position = 0, 140
        halign = center
        valign = center
      }
      label {
        text = cmd[update:60000] date +'%A %-d %B'
        font_family = ${uiFont}
        font_size = 20
        color = ${rgb c.muted}
        position = 0, 60
        halign = center
        valign = center
      }
      label {
        text = $USER
        font_family = ${uiFont}
        font_size = 15
        color = ${rgb c.muted}
        position = 0, -46
        halign = center
        valign = center
      }
      input-field {
        size = 320, 48
        outline_thickness = 1
        outer_color = ${rgb c.line2}
        check_color = ${rgb c.brand}
        fail_color = ${rgb c.err}
        inner_color = ${rgb c.s1}
        font_color = ${rgb c.ink}
        font_family = ${uiFont}
        placeholder_text = <span foreground="##${tk.bare c.muted}">password</span>
        fail_text = <span foreground="##${tk.bare c.err}">wrong</span>
        rounding = 12
        position = 0, -110
        halign = center
        valign = center
      }
      label {
        text = cmd[update:30000] cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1 | sed 's/$/% battery/'
        font_family = ${monoFont}
        font_size = 12
        color = ${rgb c.muted}
        position = -24, 24
        halign = right
        valign = bottom
      }
    '';

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
              rounding = cfg.look.rounding;
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
          barPosition = cfg.look.barPosition;
          wallpapers = if cfg.wallpapers == null then null else toString cfg.wallpapers;
          wallpaper = cfg.wallpaperPath;
          cursor = cfg.look.cursor;
          rounding = cfg.look.rounding;
          blur = cfg.look.blur;
          systemReadouts = cfg.look.systemReadouts;
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
        "xdg/kitty/kitty.conf".text = ''
          font_family ${monoFont}
          bold_font auto
          italic_font auto
          font_size 11.5
          background_opacity ${toString cfg.look.terminalOpacity}
          background_blur 24
          window_padding_width 14
          placement_strategy center
          hide_window_decorations yes
          confirm_os_window_close 0
          cursor_shape beam
          cursor_blink_interval 0.6
          tab_bar_style powerline
          tab_powerline_style slanted
          enable_audio_bell no
          scrollback_lines 10000
          # Colours follow the active finish; `nixie-shell finish` relinks and signals a reload.
          include ~/.config/nixie/kitty.conf
          include ~/.config/nixie/local.conf
        '';
        "xdg/nvim/sysinit.vim".text = ''
          set termguicolors
          hi Normal guibg=${t.bg} guifg=${t.ink}
          hi Comment guifg=${t.muted}
          hi String guifg=${t.ok}
          hi Keyword guifg=${t.brand2}
          hi Function guifg=${t.mem}
          hi Number guifg=${t.hot}
          hi Error guifg=${t.err}
          hi LineNr guifg=${t.line2}
          hi CursorLine guibg=${t.s1}
          hi Visual guibg=${t.s3}
          hi StatusLine guibg=${t.s1} guifg=${t.ink}
        '';
        "xdg/starship.toml".text = ''
          add_newline = true
          format = "$directory$git_branch$git_status$nix_shell$cmd_duration$line_break$character"
          [character]
          success_symbol = "[›](bold ${t.brand2})"
          error_symbol = "[›](bold ${t.err})"
          [directory]
          style = "bold ${t.ink}"
          truncation_length = 3
          [git_branch]
          style = "${t.mem}"
          symbol = " "
          [git_status]
          style = "${t.hot}"
          [nix_shell]
          symbol = " "
          style = "${t.net}"
          [cmd_duration]
          style = "${t.muted}"
        '';
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
        "nixie/desktop/mark.txt".text = ''
          $1▐████████▌
          $1▐█▌    $2▐█▌
          $1▐█▌    $2▐█▌
          $1▐█▌    $2▐█▌
          $1▐█▌    $2▐█▌
        '';
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
