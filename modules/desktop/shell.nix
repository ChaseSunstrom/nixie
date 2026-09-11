# The shell layer: Quickshell running shell.qml, and `nixie-shell`, the one
# command every keybind calls. Screenshot, recording and OSD adjustments are
# small scripts here so the QML stays declarative.
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
    cp ${./shell/shell.qml} $out/shell.qml
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
    Super+Return terminal · Super+B browser · Super+E files · Super+Space launcher (Tab cycles apps/files/calc/emoji/clipboard)
    Super+Q close · Super+F fullscreen · Super+V float · Super+H/L/K focus · Super+Shift+H/L move · Super+1..9 workspace · Super+Shift+1..9 send
    Super+Tab windows · Super+N notifications · Super+Esc power · Super+/ this sheet · Super+` overview
    Super+Shift+S screenshot (annotate) · Super+Shift+R record · Super+Shift+C colour picker · Super+, clipboard · Super+. emoji · Super+= calculator · Super+Ctrl+L lock
  '';
  nixieShell = pkgs.writeShellApplication {
    name = "nixie-shell";
    runtimeInputs = with pkgs; [
      quickshell
      socat
      grim
      slurp
      satty
      wf-recorder
      pamixer
      brightnessctl
      wl-clipboard
      libnotify
      coreutils
      procps
    ];
    text = ''
      sock="$XDG_RUNTIME_DIR/nixie-shell.sock"
      send() { printf '%s\n' "$*" | socat - "UNIX-CONNECT:$sock"; }
      case "''${1:-}" in
        daemon) exec quickshell -p ${shellDir}/shell.qml ;;
        screenshot)
          f="$HOME/Pictures/shot-$(date +%Y%m%d-%H%M%S).png"; mkdir -p "$HOME/Pictures"
          grim -g "$(slurp)" - | satty --filename - --output-filename "$f" --copy-command wl-copy
          notify-send "Screenshot" "$f" ;;
        record)
          if pgrep -x wf-recorder >/dev/null; then pkill -INT -x wf-recorder; notify-send "Recording" "stopped"; else
            f="$HOME/Videos/rec-$(date +%Y%m%d-%H%M%S).mp4"; mkdir -p "$HOME/Videos"
            notify-send "Recording" "started; Super+Shift+R stops"; wf-recorder -g "$(slurp)" -f "$f" & fi ;;
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
    ];
    environment.etc."nixie/desktop/emoji.txt".source = emoji;
    environment.etc."nixie/desktop/keys.txt".source = keys;
    # xdg-desktop-portal needs a notification daemon on the bus; the shell is it.
    systemd.user.services.nixie-shell = {
      description = "nixie shell";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${nixieShell}/bin/nixie-shell daemon";
        Restart = "on-failure";
      };
    };
  };
}
