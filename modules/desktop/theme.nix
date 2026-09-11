# One token source for everything on the desktop: GTK, Qt, the terminal, the
# editor and the shell all read colours generated here. Changing the finish
# is one option and an apply.
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
  t = tk.forFinish cfg.finish;
  wallpaper =
    pkgs.runCommand "nixie-wallpaper-${cfg.finish}.png" { nativeBuildInputs = [ pkgs.imagemagick ]; }
      ''
        magick -size 3840x2160 gradient:${t.bg}-${t.s2} \
          \( -size 3840x2160 xc:none -fill "${t.brand}" -draw "roundrectangle 1720,880 1880,1280 30,30" -draw "roundrectangle 1960,880 2120,1280 30,30" \) -composite \
          \( -size 3840x2160 xc:none -fill "${t.brand2}" -draw "circle 1850,1000 1850,1040" -draw "circle 1900,1090 1900,1130" -draw "circle 1950,1180 1950,1220" \) -composite \
          -quality 92 $out
      '';
  shellJson = builtins.toJSON (t // { inherit (cfg) finish; });
in
{
  options.nixie.desktop.wallpaperPath = mkOption {
    type = lib.types.str;
    default = if cfg.wallpaper == null then "${wallpaper}" else toString cfg.wallpaper;
    readOnly = true;
    description = "Internal: the resolved wallpaper path.";
  };

  config = lib.mkIf cfg.enable {
    environment.etc."nixie/desktop/tokens.json".text = shellJson;
    environment.etc."xdg/gtk-3.0/settings.ini".text = ''
      [Settings]
      gtk-application-prefer-dark-theme=${if t.dark then "1" else "0"}
      gtk-theme-name=Adwaita${lib.optionalString t.dark "-dark"}
      gtk-icon-theme-name=Adwaita
      gtk-font-name=Inter 11
      gtk-cursor-theme-name=Adwaita
    '';
    environment.etc."xdg/gtk-4.0/settings.ini".text =
      config.environment.etc."xdg/gtk-3.0/settings.ini".text;
    # GTK accent and surfaces from the tokens.
    environment.etc."xdg/gtk-4.0/gtk.css".text = ''
      :root, window { --accent-bg-color: ${t.brand}; --accent-color: ${t.brand2}; --window-bg-color: ${t.bg}; --view-bg-color: ${t.s2}; --card-bg-color: ${t.s1}; }
    '';
    environment.etc."xdg/gtk-3.0/gtk.css".text = ''
      @define-color accent_bg_color ${t.brand}; @define-color accent_color ${t.brand2}; @define-color theme_bg_color ${t.bg}; @define-color theme_base_color ${t.s2};
    '';
    qt = {
      enable = true;
      platformTheme = "gtk2";
      style = "adwaita${lib.optionalString t.dark "-dark"}";
    };
    environment.etc."xdg/kitty/kitty.conf".text = ''
      font_family JetBrains Mono
      font_size 11
      background ${t.bg}
      foreground ${t.ink}
      cursor ${t.brand2}
      selection_background ${t.s3}
      selection_foreground ${t.ink}
      url_color ${t.brand2}
      color0 ${t.s2}
      color8 ${t.line2}
      color1 ${t.err}
      color9 ${t.err}
      color2 ${t.ok}
      color10 ${t.ok}
      color3 ${t.hot}
      color11 ${t.hot}
      color4 ${t.brand2}
      color12 ${t.cpu}
      color5 ${t.mem}
      color13 ${t.mem}
      color6 ${t.net}
      color14 ${t.ice}
      color7 ${t.muted}
      color15 ${t.ink}
      window_padding_width 8
      confirm_os_window_close 0
      include ~/.config/nixie/local.conf
    '';
    environment.etc."xdg/nvim/sysinit.vim".text = ''
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
  };
}
