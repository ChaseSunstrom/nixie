# The shell layer: Quickshell running the QML under ./shell, and
# `nixie-shell`, the one command every keybind calls. Finish and wallpaper
# switching, screenshots, recording and OSD adjustments are small scripts
# here so the QML stays declarative.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  template = import ../../lib/template.nix lib;
  cfg = config.nixie.desktop;
  shellDir = pkgs.runCommand "nixie-shell-qml" { } ''
    mkdir -p $out
    cp ${./shell}/*.qml $out/
  '';
  emoji = pkgs.runCommand "emoji.txt" { } ''
    ${pkgs.python3}/bin/python3 - >$out <<'PY'
    import unicodedata, sys
    for cp in range(0x1F300, 0x1FAFF):
        ch = chr(cp)
        try:
            print(ch, unicodedata.name(ch).lower())
        except ValueError:
            pass
    PY
  '';
  keys = pkgs.writeText "keys.txt" ''
    Super+Return terminal · Super+B browser · Super+E files · Super+Space launcher (Tab cycles apps, files, calc, emoji, clipboard)
    Super+Q close · Super+F fullscreen · Super+Shift+F maximise · Super+V float · Super+P pin · Super+H/J/K/L focus · Super+Shift+H/J/K/L move
    Super+1..9 workspace · Super+Shift+1..9 send there · Super+S scratchpad · Super+Tab or Super+` all windows
    Super+A control centre · Super+N notifications · Super+Esc power · Super+/ this sheet
    Super+W next wallpaper · Super+Shift+W wallpaper picker · Super+T next finish
    Super+Shift+S screenshot (annotate) · Super+Shift+R record · Super+Shift+C colour picker · Super+, clipboard · Super+. emoji · Super+= calculator · Super+Ctrl+L lock
  '';
  finishes = lib.concatStringsSep " " cfg.finishes;
  nixieShell = pkgs.writeShellApplication {
    name = "nixie-shell";
    # Quickshell inherits this PATH: every tool the QML spawns is here.
    runtimeInputs =
      with pkgs;
      [
        quickshell
        bash
        socat
        networkmanager
        bluez
        gnugrep
        util-linux
        cliphist
        fd
        libqalculate
        xdg-utils
        hyprsunset
        grim
        slurp
        satty
        wf-recorder
        pamixer
        brightnessctl
        wl-clipboard
        libnotify
        coreutils
        findutils
        procps
        hyprland
        swaybg
        dconf
        gnused
        jq
        networkmanager
        bluez
        pulseaudio
        systemd
        gawk
        procps
      ]
      ++ lib.optional cfg.audioVisualiser.enable pkgs.cava;
    # The command itself is shell/nixie-shell.sh.
    text = template.fill ./nixie-shell.sh { inherit shellDir finishes; };
  };
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      nixieShell
      pkgs.quickshell
      pkgs.libqalculate
      pkgs.fd
      pkgs.jq
    ];
    environment.etc."nixie/desktop/emoji.txt".source = emoji;
    environment.etc."nixie/desktop/keys.txt".source = keys;
    # xdg-desktop-portal needs a notification daemon on the bus; the shell is it.
    systemd.user.services.nixie-shell = {
      description = "nixie shell";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      path = [ "/run/current-system/sw" ];
      # Desktop entries and icon themes are found through these, whatever the
      # session manager exported.
      environment.XDG_DATA_DIRS = "/run/current-system/sw/share:/etc/profiles/per-user/${cfg.user}/share";
      serviceConfig = {
        ExecStart = "${nixieShell}/bin/nixie-shell daemon";
        Restart = "on-failure";
      };
    };
  };
}
