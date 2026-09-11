# Hyprland's configuration, generated from the options and the finish. The
# person's ~/.config/hypr/local.conf is sourced last and needs no rebuild.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixie.desktop;
  tk = import ../../lib/tokens.nix { inherit lib; };
  t = tk.forFinish cfg.finish;
  rgb = c: "rgb(${tk.bare c})";
  pick = v: d: if v == null then d else v;
  apps = {
    terminal = pick cfg.defaultApps.terminal "kitty";
    browser = pick cfg.defaultApps.browser "firefox";
    fileManager = pick cfg.defaultApps.fileManager "nautilus";
  };
  binds = {
    "SUPER, Return" = "exec, uwsm app -- ${apps.terminal}";
    "SUPER, B" = "exec, uwsm app -- ${apps.browser}";
    "SUPER, E" = "exec, uwsm app -- ${apps.fileManager}";
    "SUPER, Space" = "exec, nixie-shell launcher";
    "SUPER, Q" = "killactive";
    "SUPER, F" = "fullscreen";
    "SUPER, V" = "togglefloating";
    "SUPER, J" = "togglesplit";
    "SUPER, H" = "movefocus, l";
    "SUPER, L" = "movefocus, r";
    "SUPER, K" = "movefocus, u";
    "SUPER SHIFT, H" = "movewindow, l";
    "SUPER SHIFT, L" = "movewindow, r";
    "SUPER, Tab" = "exec, nixie-shell switcher";
    "SUPER, N" = "exec, nixie-shell notifications";
    "SUPER, Escape" = "exec, nixie-shell power";
    "SUPER, slash" = "exec, nixie-shell cheatsheet";
    "SUPER SHIFT, S" = "exec, nixie-shell screenshot";
    "SUPER SHIFT, R" = "exec, nixie-shell record";
    "SUPER SHIFT, C" = "exec, hyprpicker -a";
    "SUPER, comma" = "exec, nixie-shell clipboard";
    "SUPER, period" = "exec, nixie-shell emoji";
    "SUPER, equal" = "exec, nixie-shell calculator";
    "SUPER CTRL, L" = "exec, loginctl lock-session";
    "SUPER, grave" = "overview:toggle";
    ", XF86AudioRaiseVolume" = "exec, nixie-shell osd volume +5";
    ", XF86AudioLowerVolume" = "exec, nixie-shell osd volume -5";
    ", XF86AudioMute" = "exec, nixie-shell osd volume mute";
    ", XF86MonBrightnessUp" = "exec, nixie-shell osd brightness +10";
    ", XF86MonBrightnessDown" = "exec, nixie-shell osd brightness -10";
  }
  // lib.listToAttrs (
    lib.concatMap (n: [
      (lib.nameValuePair "SUPER, ${toString n}" "workspace, ${toString n}")
      (lib.nameValuePair "SUPER SHIFT, ${toString n}" "movetoworkspace, ${toString n}")
    ]) (lib.range 1 9)
  )
  // cfg.keybinds;
  monitors =
    if cfg.monitors == [ ] then
      [ ", preferred, auto, 1" ]
    else
      map (m: "${m.name}, ${m.mode}, ${m.position}, ${m.scale}") cfg.monitors;
  conf = ''
    ${lib.concatMapStringsSep "\n" (m: "monitor = ${m}") monitors}
    exec-once = uwsm app -- nixie-shell daemon
    exec-once = uwsm app -- hyprpaper
    exec-once = uwsm app -- hypridle
    exec-once = wl-paste --watch cliphist store
    ${lib.optionalString cfg.nightLight.enable "exec-once = uwsm app -- hyprsunset -t 4500"}
    ${lib.concatMapStringsSep "\n" (c: "exec-once = ${c}") cfg.autostart}

    input {
      kb_layout = ${cfg.keyboard.layout}
      kb_variant = ${cfg.keyboard.variant}
      follow_mouse = 1
      touchpad { natural_scroll = true; tap-to-click = true }
    }
    general {
      gaps_in = 5
      gaps_out = 10
      border_size = 1
      col.active_border = ${rgb t.brand2}
      col.inactive_border = ${rgb t.line}
      layout = dwindle
      allow_tearing = false
    }
    decoration {
      rounding = 6
      active_opacity = 1.0
      inactive_opacity = 0.96
      shadow { enabled = true; range = 24; render_power = 3; color = rgba(00000059) }
      blur { enabled = true; size = 8; passes = 2; noise = 0.01; vibrancy = 0.15; popups = true }
    }
    # The motion set: one ease for state, a slower one for space. Overview and
    # workspace slide are the only long ones; everything else is under 200 ms.
    animations {
      enabled = true
      bezier = state, 0.2, 0.0, 0.0, 1.0
      bezier = space, 0.16, 1.0, 0.3, 1.0
      bezier = pop, 0.34, 1.4, 0.64, 1.0
      animation = windowsIn, 1, 2, pop, popin 92%
      animation = windowsOut, 1, 2, state, popin 92%
      animation = windowsMove, 1, 3, space
      animation = border, 1, 3, state
      animation = fade, 1, 2, state
      animation = layersIn, 1, 2, state, fade
      animation = layersOut, 1, 2, state, fade
      animation = workspaces, 1, 4, space, slide
    }
    dwindle { pseudotile = true; preserve_split = true }
    misc { disable_hyprland_logo = true; disable_splash_rendering = true; vfr = true; focus_on_activate = true }
    # Performance mode: fullscreen or a game drops blur and animations.
    windowrulev2 = noblur, fullscreen:1
    windowrulev2 = noanim, fullscreen:1
    windowrulev2 = immediate, class:^(steam_app_.*)$
    windowrulev2 = noblur, class:^(steam_app_.*)$
    layerrule = blur, nixie-shell
    layerrule = ignorezero, nixie-shell
    ${lib.optionalString cfg.overview.enable ''
      plugin = ${pkgs.hyprlandPlugins.hyprspace}/lib/libHyprspace.so
      plugin { hyprspace { bg_col = ${rgb t.bg}; workspace_border_col = ${rgb t.brand2}; } }
    ''}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "bind = ${k}, ${v}") binds)}
    bindm = SUPER, mouse:272, movewindow
    bindm = SUPER, mouse:273, resizewindow
    source = ~/.config/hypr/local.conf
  '';
in
{
  config = lib.mkIf cfg.enable {
    environment.etc."xdg/hypr/hyprland.conf".text = conf;
    # Hyprland reads ~/.config/hypr/hyprland.conf; the session seeds it once
    # from the generated file and leaves local.conf to the person.
    environment.etc."xdg/hypr/hyprpaper.conf".text = ''
      preload = ${cfg.wallpaperPath}
      wallpaper = , ${cfg.wallpaperPath}
      splash = false
    '';
    environment.etc."xdg/hypr/hypridle.conf".text = ''
      general { lock_cmd = pidof hyprlock || hyprlock; before_sleep_cmd = loginctl lock-session; after_sleep_cmd = hyprctl dispatch dpms on }
      listener { timeout = ${toString cfg.idle.lockAfter}; on-timeout = loginctl lock-session }
      listener { timeout = ${toString cfg.idle.screenOffAfter}; on-timeout = hyprctl dispatch dpms off; on-resume = hyprctl dispatch dpms on }
      ${lib.optionalString (
        cfg.idle.suspendAfter != null
      ) "listener { timeout = ${toString cfg.idle.suspendAfter}; on-timeout = systemctl suspend }"}
    '';
    environment.etc."xdg/hypr/hyprlock.conf".text = ''
      general { hide_cursor = true }
      background { path = ${cfg.wallpaperPath}; blur_passes = 3; blur_size = 8 }
      input-field { size = 300, 44; outline_thickness = 1; outer_color = ${rgb t.brand2}; inner_color = ${rgb t.s1}; font_color = ${rgb t.ink}; placeholder_text = <span foreground="##${tk.bare t.muted}">password</span>; position = 0, -80; halign = center; valign = center; rounding = 3 }
      label { text = $TIME; font_family = Archivo; font_size = 64; color = ${rgb t.ink}; position = 0, 60; halign = center; valign = center }
    '';
    environment.systemPackages =
      with pkgs;
      [
        hyprpaper
        hypridle
        hyprlock
        hyprpicker
        hyprsunset
        grim
        slurp
        satty
        wf-recorder
        wl-clipboard
        cliphist
        brightnessctl
        playerctl
        pamixer
        kitty
        nautilus
        firefox
      ]
      ++ lib.optional cfg.overview.enable pkgs.hyprlandPlugins.hyprspace;
    programs.hyprlock.enable = true;
    services.hypridle.enable = true;
    # First login: copy the generated files where Hyprland looks, keep local.conf.
    system.userActivationScripts.nixie-hypr.text = ''
      mkdir -p "$HOME/.config/hypr"
      for f in hyprland hyprpaper hypridle hyprlock; do ln -sfn /etc/xdg/hypr/$f.conf "$HOME/.config/hypr/$f.conf"; done
      [ -e "$HOME/.config/hypr/local.conf" ] || printf '# Your tweaks, sourced last; no rebuild needed.\n' >"$HOME/.config/hypr/local.conf"
    '';
  };
}
