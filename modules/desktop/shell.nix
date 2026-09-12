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
    text = ''
      sock="$XDG_RUNTIME_DIR/nixie-shell.sock"
      send() { printf '%s\n' "$*" | socat - "UNIX-CONNECT:$sock"; }
      cfgdir="$HOME/.config/nixie"; mkdir -p "$cfgdir"
      finish() { f=$(cat "$cfgdir/finish" 2>/dev/null || cat /etc/nixie/desktop/default-finish); if [ -d "/etc/nixie/desktop/$f" ]; then echo "$f"; else cat /etc/nixie/desktop/default-finish; fi; }
      wallpapers() { # the generated set for the active finish, then the person's own
        find "/etc/nixie/desktop/$(finish)/wallpapers/" -maxdepth 1 -type f | sort
        d=$(jq -r '.wallpapers // empty' /etc/nixie/desktop/settings.json)
        if [ -n "$d" ] && [ -d "$d" ]; then find "$d" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) | sort; fi
      }
      setwall() {
        [ -f "$1" ] || { echo "no such image: $1" >&2; return 1; }
        printf '%s' "$1" >"$cfgdir/wallpaper"
        # swaybg draws one image per process and has no IPC to lose; a switch
        # is a new process behind the old one, then the old one goes.
        # nixpkgs wraps swaybg, so match the command line, not the name.
        mapfile -t old < <(pgrep -f 'swaybg -m fill' || true)
        setsid swaybg -m fill -i "$1" >/dev/null 2>&1 &
        sleep 0.3; [ "''${#old[@]}" = 0 ] || kill "''${old[@]}" 2>/dev/null || true
        send "wallpaper $1" 2>/dev/null || true
      }
      case "''${1:-}" in
        daemon) exec quickshell -p ${shellDir}/shell.qml ;;
        finish)
          case "''${2:-}" in
            apply) f=$(finish) ;;
            next) cur=$(finish); f=""; prev=""; for x in ${finishes} ${finishes}; do if [ "$prev" = "$cur" ]; then f=$x; break; fi; prev=$x; done; [ -n "$f" ] || f=$(cat /etc/nixie/desktop/default-finish) ;;
            *) f=''${2:?finish name}; [ -d "/etc/nixie/desktop/$f" ] || { echo "no finish $f (have: ${finishes})" >&2; exit 2; } ;;
          esac
          printf '%s' "$f" >"$cfgdir/finish"
          mkdir -p "$HOME/.config/hypr" "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
          ln -sfn "/etc/nixie/desktop/$f/kitty.conf" "$cfgdir/kitty.conf"
          ln -sfn "/etc/nixie/desktop/$f/hyprlock.conf" "$HOME/.config/hypr/hyprlock.conf"
          ln -sfn "/etc/nixie/desktop/$f/gtk.css" "$HOME/.config/gtk-3.0/gtk.css"
          ln -sfn "/etc/nixie/desktop/$f/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"
          dark=$(jq -r .dark "/etc/nixie/desktop/$f/tokens.json")
          if [ "$dark" = true ]; then scheme=prefer-dark; theme=adw-gtk3-dark; icons=Papirus-Dark; else scheme=default; theme=adw-gtk3; icons=Papirus; fi
          # GTK apps follow these live through the settings portal.
          dconf write /org/gnome/desktop/interface/color-scheme "'$scheme'" 2>/dev/null || true
          dconf write /org/gnome/desktop/interface/gtk-theme "'$theme'" 2>/dev/null || true
          dconf write /org/gnome/desktop/interface/icon-theme "'$icons'" 2>/dev/null || true
          if [ "''${2:-}" != apply ]; then
            hyprctl reload >/dev/null 2>&1 || true
            pkill -USR1 -x kitty 2>/dev/null || true # kitty rereads its config on SIGUSR1
            if [ -s "$cfgdir/wallpaper" ]; then case "$(cat "$cfgdir/wallpaper")" in /etc/nixie/desktop/*|*/nixie-wallpapers-*) setwall "$(wallpapers | head -1)" ;; esac; fi
            send "finish $f" 2>/dev/null || true
          fi
          echo "$f" ;;
        wallpaper)
          case "''${2:-}" in
            restore) w=$(cat "$cfgdir/wallpaper" 2>/dev/null || true); [ -f "$w" ] || w=$(jq -r .wallpaper /etc/nixie/desktop/settings.json); setwall "$w" ;;
            next|prev)
              cur=$(cat "$cfgdir/wallpaper" 2>/dev/null || true); mapfile -t all < <(wallpapers); n=''${#all[@]}; [ "$n" -gt 0 ] || exit 0
              i=0; for k in "''${!all[@]}"; do [ "''${all[$k]}" = "$cur" ] && i=$k; done
              if [ "$2" = next ]; then i=$(( (i + 1) % n )); else i=$(( (i + n - 1) % n )); fi
              setwall "''${all[$i]}" ;;
            list) wallpapers ;;
            output) shift 2; out=''${1:?output name}; img=''${2:?image path}
              # Per-monitor: one swaybg for that output, replacing its own.
              mapfile -t old < <(pgrep -f "swaybg -o $out " || true)
              setsid swaybg -o "$out" -m fill -i "$img" >/dev/null 2>&1 &
              sleep 0.3; [ "''${#old[@]}" = 0 ] || kill "''${old[@]}" 2>/dev/null || true ;;
            *) setwall "''${2:?image path}" ;;
          esac ;;
        screenshot)
          f="$HOME/Pictures/shot-$(date +%Y%m%d-%H%M%S).png"; mkdir -p "$HOME/Pictures"
          case "''${2:-region}" in
            screen) grim - ;;
            window) grim -g "$(hyprctl -j activewindow | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')" - ;;
            delay) sleep 5; grim - ;;
            *) grim -g "$(slurp)" - ;;
          esac | satty --filename - --output-filename "$f" --copy-command wl-copy
          notify-send -a nixie "Screenshot" "$f" ;;
        net)
          case "''${2:-list}" in
            list) nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list 2>/dev/null | awk -F: 'length($2)' | head -24 ;;
            connect)
              ssid=''${3:?network name}
              if [ -n "''${4:-}" ]; then nmcli device wifi connect "$ssid" password "$4"; else nmcli device wifi connect "$ssid"; fi ;;
            scan) nmcli device wifi rescan 2>/dev/null || true ;;
            *) echo "usage: nixie-shell net [list|scan|connect <ssid> [password]]" >&2; exit 2 ;;
          esac ;;
        bt)
          case "''${2:-list}" in
            list) bluetoothctl devices 2>/dev/null | sed 's/^Device //' | head -24 ;;
            scan) (bluetoothctl --timeout 12 scan on >/dev/null 2>&1 &) ;;
            connect) bluetoothctl connect "''${3:?device address}" ;;
            disconnect) bluetoothctl disconnect "''${3:?device address}" ;;
            *) echo "usage: nixie-shell bt [list|scan|connect <mac>|disconnect <mac>]" >&2; exit 2 ;;
          esac ;;
        streams)
          case "''${2:-list}" in
            list) pactl -f json list sink-inputs 2>/dev/null | jq -r '.[] | "\(.index)\t\(.properties["application.name"] // "audio")\t\(.volume["front-left"].value_percent // "0%")"' ;;
            set) pactl set-sink-input-volume "''${3:?index}" "''${4:?percent}%" ;;
            *) echo "usage: nixie-shell streams [list|set <index> <percent>]" >&2; exit 2 ;;
          esac ;;
        caffeine)
          # An idle inhibitor a person can see: hypridle and the lock stay off
          # while this holds, and the bar shows it.
          if pkill -f "systemd-inhibit --what=idle --who=nixie" 2>/dev/null; then send "caffeine 0"; echo off
          else
            setsid systemd-inhibit --what=idle --who=nixie --why="keep awake" sleep 86400 >/dev/null 2>&1 &
            sleep 0.4
            if pgrep -f "systemd-inhibit --what=idle --who=nixie" >/dev/null; then send "caffeine 1"; echo on
            else echo "could not take the idle inhibitor" >&2; exit 1; fi
          fi ;;
        record)
          if pgrep -x wf-recorder >/dev/null; then pkill -INT -x wf-recorder; notify-send -a nixie "Recording" "stopped"; else
            f="$HOME/Videos/rec-$(date +%Y%m%d-%H%M%S).mp4"; mkdir -p "$HOME/Videos"
            notify-send -a nixie "Recording" "started; Super+Shift+R stops"; wf-recorder -g "$(slurp)" -f "$f" & fi ;;
        osd)
          case "$2" in
            volume) if [ "$3" = mute ]; then pamixer -t; else pamixer --allow-boost -i 0 >/dev/null; pamixer -"$( [ "''${3:0:1}" = + ] && echo i || echo d)" "''${3:1}"; fi
                    v=$(pamixer --get-volume); [ "$(pamixer --get-mute)" = true ] && v=0; send "osd volume $v" ;;
            brightness) brightnessctl -q set "''${3:1}%''${3:0:1}"; send "osd brightness $(( $(brightnessctl g) * 100 / $(brightnessctl m) ))" ;;
            *) send "osd $2 $3" ;;
          esac ;;
        *) send "$@" ;;
      esac
    '';
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
