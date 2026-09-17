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
  template = import ../../lib/template.nix lib;
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
  ]
  # The same panel on the key HyDE-shaped desktops use for an overview.
  ++ lib.optional cfg.overview.enable [
    "SUPER + grave"
    "nixie-shell switcher"
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
  # The configuration itself is conf/hyprland.lua; what Nix works out -- the
  # look, the keys, the monitors -- goes in at its marks.
  conf = template.fill ./conf/hyprland.lua {
    inherit
      monitors
      execBinds
      mediaKeys
      anim
      ;
    finish = lua cfg.finish;
    cursorTheme = lua look.cursor.theme;
    cursorSize = lua (toString look.cursor.size);
    gapsIn = look.gaps.inner;
    gapsOut = look.gaps.outer;
    inherit (look) borderSize;
    inherit (look) rounding;
    blur = lib.boolToString look.blur;
    uiFont = lua cfg.fonts.ui;
    kbLayout = lua cfg.keyboard.layout;
    kbVariant = lua cfg.keyboard.variant;
    nightLight = lib.optionalString cfg.nightLight.enable ''hl.exec_cmd("uwsm app -- hyprsunset -t 4500")'';
    autostart = lib.concatMapStringsSep "\n  " (c: "hl.exec_cmd(${lua c})") cfg.autostart;
  };
in
{
  config = lib.mkIf cfg.enable {
    environment.etc."xdg/hypr/hyprland.lua".text = conf;
    # The dispatchers are Lua calls: against a Lua config `hyprctl dispatch
    # dpms off` parses as `hl.dispatch(dpms off)` and blanks nothing (D29).
    environment.etc."xdg/hypr/hypridle.conf".text = template.fill ./conf/hypridle.conf {
      inherit (cfg.idle) lockAfter;
      inherit (cfg.idle) screenOffAfter;
      suspend = lib.optionalString (cfg.idle.suspendAfter != null) ''
        listener {
          timeout = ${toString cfg.idle.suspendAfter}
          on-timeout = systemctl suspend
        }
      '';
    };
    environment.systemPackages = with pkgs; [
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
    ];
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
    system.userActivationScripts.nixie-hypr.text = template.fill ./link-config.sh {
      inherit (cfg) finish;
    };
  };
}
