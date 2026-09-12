# Hyprland's configuration, generated as Lua from the options. The palette is
# read at load time from the active finish's tokens (so a finish switch is a
# reload, not a rebuild), and ~/.config/hypr/local.lua is required last.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixie.desktop;
  inherit (cfg) look;
  pick = v: d: if v == null then d else v;
  apps = {
    terminal = pick cfg.defaultApps.terminal "kitty";
    browser = pick cfg.defaultApps.browser "firefox";
    fileManager = pick cfg.defaultApps.fileManager "nautilus";
  };
  lua = s: builtins.toJSON s; # a JSON string literal is a valid Lua string literal
  binds = [
    [
      "SUPER + Return"
      "uwsm app -- ${apps.terminal}"
    ]
    [
      "SUPER + B"
      "uwsm app -- ${apps.browser}"
    ]
    [
      "SUPER + E"
      "uwsm app -- ${apps.fileManager}"
    ]
    [
      "SUPER + Space"
      "nixie-shell launcher"
    ]
    [
      "SUPER + Tab"
      "nixie-shell switcher"
    ]
    [
      "SUPER + N"
      "nixie-shell notifications"
    ]
    [
      "SUPER + A"
      "nixie-shell control"
    ]
    [
      "SUPER + Escape"
      "nixie-shell power"
    ]
    [
      "SUPER + slash"
      "nixie-shell cheatsheet"
    ]
    [
      "SUPER + W"
      "nixie-shell wallpaper next"
    ]
    [
      "SUPER + SHIFT + W"
      "nixie-shell wallpapers"
    ]
    [
      "SUPER + T"
      "nixie-shell finish next"
    ]
    [
      "SUPER + SHIFT + S"
      "nixie-shell screenshot"
    ]
    [
      "SUPER + SHIFT + R"
      "nixie-shell record"
    ]
    [
      "SUPER + SHIFT + C"
      "hyprpicker -a"
    ]
    [
      "SUPER + comma"
      "nixie-shell clipboard"
    ]
    [
      "SUPER + period"
      "nixie-shell emoji"
    ]
    [
      "SUPER + equal"
      "nixie-shell calculator"
    ]
    [
      "SUPER + CTRL + L"
      "loginctl lock-session"
    ]
    [
      "SUPER + grave"
      "hyprctl dispatch overview:toggle"
    ]
  ]
  ++ lib.mapAttrsToList (k: v: [
    k
    v
  ]) cfg.keybinds;
  execBinds = lib.concatMapStringsSep "\n" (
    b: "hl.bind(${lua (builtins.elemAt b 0)}, hl.dsp.exec_cmd(${lua (builtins.elemAt b 1)}))"
  ) binds;
  mediaKeys =
    lib.concatMapStringsSep "\n"
      (
        b:
        "hl.bind(${lua (builtins.elemAt b 0)}, hl.dsp.exec_cmd(${lua (builtins.elemAt b 1)}), { locked = true, repeating = true })"
      )
      [
        [
          "XF86AudioRaiseVolume"
          "nixie-shell osd volume +5"
        ]
        [
          "XF86AudioLowerVolume"
          "nixie-shell osd volume -5"
        ]
        [
          "XF86AudioMute"
          "nixie-shell osd volume mute"
        ]
        [
          "XF86MonBrightnessUp"
          "nixie-shell osd brightness +10"
        ]
        [
          "XF86MonBrightnessDown"
          "nixie-shell osd brightness -10"
        ]
        [
          "XF86AudioPlay"
          "playerctl play-pause"
        ]
        [
          "XF86AudioNext"
          "playerctl next"
        ]
        [
          "XF86AudioPrev"
          "playerctl previous"
        ]
      ];
  monitors =
    if cfg.monitors == [ ] then
      ''hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })''
    else
      lib.concatMapStringsSep "\n" (
        m:
        "hl.monitor({ output = ${lua m.name}, mode = ${lua m.mode}, position = ${lua m.position}, scale = ${lua m.scale} })"
      ) cfg.monitors;
  # Speeds are in Hyprland's 100 ms units.
  anim =
    if look.animations == "none" then
      "hl.config({ animations = { enabled = false } })"
    else
      let
        k = if look.animations == "reduced" then 0.6 else 1.0;
        s = v: toString (v * k);
      in
      ''
        hl.config({ animations = { enabled = true } })
        hl.curve("state", { type = "bezier", points = { {0.2, 0}, {0, 1} } })
        hl.curve("space", { type = "bezier", points = { {0.16, 1}, {0.3, 1} } })
        hl.curve("pop",   { type = "bezier", points = { {0.34, 1.4}, {0.64, 1} } })
        hl.curve("soft",  { type = "spring", mass = 1, stiffness = 90, dampening = 16 })
        hl.animation({ leaf = "global",     enabled = true, speed = 10,      bezier = "default" })
        hl.animation({ leaf = "windowsIn",  enabled = true, speed = ${s 2.4}, bezier = "pop",   style = "popin 90%" })
        hl.animation({ leaf = "windowsOut", enabled = true, speed = ${s 1.6}, bezier = "state", style = "popin 92%" })
        hl.animation({ leaf = "windowsMove", enabled = true, speed = ${s 3.2}, spring = "soft" })
        hl.animation({ leaf = "border",     enabled = true, speed = ${s 4},   bezier = "state" })
        hl.animation({ leaf = "fade",       enabled = true, speed = ${s 2},   bezier = "state" })
        hl.animation({ leaf = "layersIn",   enabled = true, speed = ${s 2},   bezier = "state", style = "fade" })
        hl.animation({ leaf = "layersOut",  enabled = true, speed = ${s 1.6}, bezier = "state", style = "fade" })
        hl.animation({ leaf = "workspaces", enabled = true, speed = ${s 4},   bezier = "space", style = "slide" })
      '';
  conf = ''
    -- Generated by Nixie from nixie.desktop.*; edit ~/.config/hypr/local.lua instead.
    local home = os.getenv("HOME") or "/root"
    local function read(p)
      local f = io.open(p, "r")
      if not f then return nil end
      local s = f:read("a"); f:close()
      return (s:gsub("%s+$", ""))
    end
    local finish = read(home .. "/.config/nixie/finish") or read("/etc/nixie/desktop/default-finish") or ${lua cfg.finish}
    local tokens = read("/etc/nixie/desktop/" .. finish .. "/tokens.json") or ""
    local function tok(k, d) return tokens:match('"' .. k .. '"%s*:%s*"(#%x+)"') or d end
    local accent = read(home .. "/.config/nixie/accent") or tok("brand2", "#7ebae4")
    local function rgb(h) return "rgb(" .. h:sub(2) .. ")" end
    local function rgba(h, a) return "rgba(" .. h:sub(2) .. a .. ")" end

    ${monitors}
    hl.env("XCURSOR_THEME", ${lua look.cursor.theme})
    hl.env("XCURSOR_SIZE", ${lua (toString look.cursor.size)})
    hl.env("HYPRCURSOR_SIZE", ${lua (toString look.cursor.size)})
    hl.env("NIXIE_FINISH", finish)

    hl.config({
      general = {
        gaps_in = ${toString look.gaps.inner},
        gaps_out = ${toString look.gaps.outer},
        border_size = ${toString look.borderSize},
        col = {
          active_border = { colors = { rgb(accent), rgb(tok("brand", "#5277c3")) }, angle = 45 },
          inactive_border = rgb(tok("line", "#383e46")),
        },
        resize_on_border = true,
        allow_tearing = false,
        layout = "dwindle",
      },
      decoration = {
        rounding = ${toString look.rounding},
        rounding_power = 3,
        active_opacity = 1.0,
        inactive_opacity = 0.97,
        shadow = { enabled = true, range = 30, render_power = 3, color = rgba(tok("s2", "#181b1e"), "8c") },
        blur = { enabled = ${lib.boolToString look.blur}, size = 8, passes = 3, noise = 0.02, vibrancy = 0.17, popups = true },
      },
      dwindle = { preserve_split = true },
      misc = { disable_hyprland_logo = true, disable_splash_rendering = true, focus_on_activate = true, font_family = ${lua cfg.fonts.ui} },
      input = {
        kb_layout = ${lua cfg.keyboard.layout},
        kb_variant = ${lua cfg.keyboard.variant},
        follow_mouse = 1,
        touchpad = { natural_scroll = true },
      },
    })
    ${anim}
    hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

    -- Performance mode: a fullscreen window or a game drops blur and motion.
    hl.window_rule({ name = "perf-fullscreen", match = { fullscreen = true }, no_blur = true, no_anim = true, idle_inhibit = "fullscreen" })
    hl.window_rule({ name = "perf-games", match = { class = "^(steam_app_.*|gamescope)$" }, immediate = true, no_blur = true })
    hl.window_rule({ name = "no-maximize", match = { class = ".*" }, suppress_event = "maximize" })
    hl.window_rule({ name = "float-utilities", match = { class = "^(pavucontrol|org\\.pulseaudio\\.pavucontrol|blueman-manager|nm-connection-editor|xdg-desktop-portal-gtk)$" }, float = true, center = true, size = "720 520" })
    hl.window_rule({ name = "pip", match = { title = "^(Picture-in-Picture|Picture in picture)$" }, float = true, pin = true })
    hl.layer_rule({ name = "shell-blur", match = { namespace = "^nixie-shell$" }, blur = true, ignore_alpha = 0.3 })
    hl.layer_rule({ name = "lock-anim", match = { namespace = "^hyprlock$" }, no_anim = true })

    ${execBinds}
    ${mediaKeys}
    hl.bind("SUPER + Q", hl.dsp.window.close())
    hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = 0 }))
    hl.bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen({ mode = 1 }))
    hl.bind("SUPER + V", hl.dsp.window.float({ action = "toggle" }))
    hl.bind("SUPER + P", hl.dsp.window.pin())
    hl.bind("SUPER + J", hl.dsp.layout("togglesplit"))
    for key, dir in pairs({ H = "left", L = "right", K = "up" }) do
      hl.bind("SUPER + " .. key, hl.dsp.focus({ direction = dir }))
      hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ direction = dir }))
    end
    hl.bind("SUPER + SHIFT + J", hl.dsp.window.move({ direction = "down" }))
    for key, dir in pairs({ left = "left", right = "right", up = "up", down = "down" }) do
      hl.bind("SUPER + " .. key, hl.dsp.focus({ direction = dir }))
    end
    for i = 1, 10 do
      local key = i % 10
      hl.bind("SUPER + " .. key, hl.dsp.focus({ workspace = i }))
      hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
    end
    hl.bind("SUPER + S", hl.dsp.workspace.toggle_special("scratch"))
    hl.bind("SUPER + SHIFT + S", hl.dsp.window.move({ workspace = "special:scratch" }))
    hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
    hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" }))
    hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
    hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

    ${lib.optionalString cfg.overview.enable ''
      hl.plugin.load(${lua "${pkgs.hyprlandPlugins.hyprspace}/lib/libHyprspace.so"})
    ''}

    hl.on("hyprland.start", function()
      hl.exec_cmd("nixie-shell wallpaper restore")
      hl.exec_cmd("wl-paste --watch cliphist store")
      hl.exec_cmd("nixie-shell finish apply")
      ${lib.optionalString cfg.nightLight.enable ''hl.exec_cmd("uwsm app -- hyprsunset -t 4500")''}
      ${lib.concatMapStringsSep "\n  " (c: "hl.exec_cmd(${lua c})") cfg.autostart}
    end)

    -- Your tweaks: ~/.config/hypr/local.lua, loaded last, no rebuild needed.
    pcall(require, "local")
  '';
in
{
  config = lib.mkIf cfg.enable {
    environment.etc."xdg/hypr/hyprland.lua".text = conf;
    environment.etc."xdg/hypr/hypridle.conf".text = ''
      general {
        lock_cmd = pidof hyprlock || hyprlock
        before_sleep_cmd = loginctl lock-session
        after_sleep_cmd = hyprctl dispatch dpms on
      }
      listener {
        timeout = ${toString cfg.idle.lockAfter}
        on-timeout = loginctl lock-session
      }
      listener {
        timeout = ${toString cfg.idle.screenOffAfter}
        on-timeout = hyprctl dispatch dpms off
        on-resume = hyprctl dispatch dpms on
      }
      ${lib.optionalString (cfg.idle.suspendAfter != null) ''
        listener {
          timeout = ${toString cfg.idle.suspendAfter}
          on-timeout = systemctl suspend
        }
      ''}
    '';
    environment.systemPackages =
      with pkgs;
      [
        swaybg
        hypridle
        hyprlock
        hyprpicker
        hyprsunset
        hyprpolkitagent
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
    systemd.user.services.hyprpolkitagent = {
      description = "Hyprland polkit agent";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
        Restart = "on-failure";
      };
    };
    # First login: link the generated files where Hyprland looks, seed the
    # per-user choices from the site, keep local.lua.
    system.userActivationScripts.nixie-hypr.text = ''
      mkdir -p "$HOME/.config/hypr" "$HOME/.config/nixie" "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
      rm -f "$HOME/.config/hypr/hyprland.conf"
      ln -sfn /etc/xdg/hypr/hyprland.lua "$HOME/.config/hypr/hyprland.lua"
      ln -sfn /etc/xdg/hypr/hypridle.conf "$HOME/.config/hypr/hypridle.conf"
      [ -e "$HOME/.config/hypr/local.lua" ] || printf -- '-- Your tweaks, loaded last; no rebuild needed. Example:\n-- hl.config({ general = { gaps_out = 24 } })\n' >"$HOME/.config/hypr/local.lua"
      [ -e "$HOME/.config/nixie/local.conf" ] || printf '# kitty tweaks, included last\n' >"$HOME/.config/nixie/local.conf"
      [ -s "$HOME/.config/nixie/finish" ] || printf '%s' "${cfg.finish}" >"$HOME/.config/nixie/finish"
      f=$(cat "$HOME/.config/nixie/finish"); [ -d "/etc/nixie/desktop/$f" ] || f=${cfg.finish}
      ln -sfn "/etc/nixie/desktop/$f/kitty.conf" "$HOME/.config/nixie/kitty.conf"
      ln -sfn "/etc/nixie/desktop/$f/hyprlock.conf" "$HOME/.config/hypr/hyprlock.conf"
      ln -sfn "/etc/nixie/desktop/$f/gtk.css" "$HOME/.config/gtk-3.0/gtk.css"
      ln -sfn "/etc/nixie/desktop/$f/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"
    '';
  };
}
