# shellcheck shell=bash
finish=$(jq -r '.theme // "graphite"' /etc/nixie/ui.json 2>/dev/null || echo graphite)
ui=$(jq -r '.uiPort // 8443' /etc/nixie/ui.json 2>/dev/null || echo 8443)
tty=${1:-/dev/tty1}
# The console is both the input and the output; that is the point.
# shellcheck disable=SC2094
exec <"$tty" >"$tty" 2>&1
# 256-colour approximations of the three finishes.
case "$finish" in
  umber) BG=52; S1=94; INK=230; MUTED=137; ACC=117; OK=114; HOT=215; ERR=203 ;;
  paper) BG=255; S1=254; INK=234; MUTED=243; ACC=25; OK=29; HOT=130; ERR=160 ;;
  *) BG=235; S1=237; INK=254; MUTED=246; ACC=117; OK=114; HOT=215; ERR=203 ;;
esac
c() { printf '\033[38;5;%sm' "$1"; }
b() { printf '\033[48;5;%sm' "$1"; }
r() { printf '\033[0m'; }
incus() { curl -s --unix-socket /var/lib/incus/unix.socket "http://incus/1.0$1" 2>/dev/null; }
draw() {
  cols=$(tput cols 2>/dev/null || echo 120); rows=$(tput lines 2>/dev/null || echo 40)
  host=$(hostname); addrs=$(ip -4 -o addr show scope global | awk '{print $2": "$4}' | paste -sd '  ')
  url="https://$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | head -1):$ui/ui/"
  printf '\033[H\033[2J'; b "$BG"; printf '\033[J'
  c "$ACC"; printf '  nixie'; c "$MUTED"; printf '  ·  %s  ·  %s\n' "$host" "$(date '+%a %d %b %H:%M')"; r
  b "$BG"; c "$MUTED"; printf '  %s\n\n' "$addrs"; r
  # left: instances as lanes; right: QR of the control panel URL
  lanes=$(incus "/instances?recursion=2" | jq -r '.metadata[]? | [.name, .status, ((.state.cpu.usage // 0) / 1e9 | floor), ((.state.memory.usage // 0) / 1048576 | floor)] | @tsv' 2>/dev/null || true)
  qr=$(qrencode -t UTF8 -m 0 "$url" 2>/dev/null || true)
  mapfile -t ql <<<"$qr"
  i=0
  b "$BG"; c "$INK"; printf '  %-18s %-10s %8s %9s' name state 'cpu s' 'mem MB'; r; printf '\n'
  while IFS=$'\t' read -r n st cpu mem; do
    [ -n "$n" ] || continue
    b "$BG"
    case "$st" in Running) dot=$OK ;; Frozen) dot=$ACC ;; *) dot=$MUTED ;; esac
    c "$dot"; printf '  ● '; c "$INK"; printf '%-16s ' "$n"; c "$MUTED"; printf '%-10s ' "$st"
    heat=$(( cpu > 60 ? HOT : INK )); c "$heat"; printf '%8s ' "$cpu"; c "$INK"; printf '%9s' "$mem"
    # heat strip: one cell per 5% of a 4-core budget, in the two block
    # glyphs the console font has (it draws ▮ and ▯ both as #)
    printf '  '; k=$(( cpu / 5 )); [ "$k" -gt 20 ] && k=20; for ((j=0;j<20;j++)); do if [ $j -lt $k ]; then c "$HOT"; printf '█'; else c "$S1"; printf '░'; fi; done
    r; printf '\n'; i=$((i+1))
  done <<<"$lanes"
  [ "$i" = 0 ] && { b "$BG"; c "$MUTED"; printf '  no instances (or incusd not running)\n'; r; }
  printf '\n'
  # pools and doctor
  pools=$(incus "/storage-pools?recursion=1" | jq -r '.metadata[]? | .name' 2>/dev/null || true)
  for p in $pools; do
    res=$(incus "/storage-pools/$p/resources" | jq -r '.metadata.space | "\(.used) \(.total)"' 2>/dev/null || echo "0 1")
    used=${res% *}; total=${res#* }; pct=$(( total > 0 ? used * 100 / total : 0 ))
    b "$BG"; c "$INK"; printf '  pool %-10s ' "$p"; col=$(( pct > 85 ? ERR : ACC )); c "$col"; for ((j=0;j<30;j++)); do if [ $((j*100/30)) -lt "$pct" ]; then printf '█'; else c "$S1"; printf '░'; c "$col"; fi; done; printf ' %3d%%' "$pct"; r; printf '\n'
  done
  if [ -e /sys/class/drm/card0/device/hwmon ]; then
    for h in /sys/class/drm/card*/device/hwmon/hwmon*/temp1_input; do [ -e "$h" ] && { b "$BG"; c "$INK"; printf '  gpu %s°C' "$(( $(cat "$h") / 1000 ))"; r; printf '\n'; }; done
  fi
  if [ -e /run/current-system/sw/bin/nixie ]; then
    # Doctor writes problems in capitals; matching without case put "usb
    # nothing blocked" in red on a healthy host.
    doc=$(timeout 5 nixie doctor 2>/dev/null | grep -E 'MISSING|NEEDED|NOT ENABLED|BLOCKED|RECOVERY|DRIFT|FAILED|% full' || true)
    [ -n "$doc" ] && { b "$BG"; c "$ERR"; printf '  doctor: %s\n' "$doc"; r; }
  fi
  # QR at the right
  qy=3; qx=$(( cols - ${#ql[0]} - 4 )); [ "$qx" -lt 60 ] && qx=60
  for l in "${ql[@]}"; do printf '\033[%d;%dH' "$qy" "$qx"; b "$BG"; c "$INK"; printf '%s' "$l"; r; qy=$((qy+1)); done
  printf '\033[%d;%dH' "$qy" "$qx"; b "$BG"; c "$MUTED"; printf '%s' "$url"; r
  printf '\033[%d;1H' "$((rows-1))"; b "$BG"; c "$MUTED"; printf '  any key: log in · r: roll back to the previous system · b: boot the previous one next time · e: re-enrol Secure Boot, TPM and attestation · Ctrl+Alt+F3: plain console'; r
}
stty -echo 2>/dev/null || true
while true; do
  draw
  if read -r -t 5 -n 1 -s k; then
    stty sane 2>/dev/null || true
    printf '\033[H\033[2J'
    case "$k" in
      # A broken new generation is undone from here, no UI needed.
      # Their output also lands in the journal, so an action taken at the
      # console can be read back later.
      r) nixie rollback 2>&1 | tee >(logger -t nixie-panel) | tail -3; sleep 3; stty -echo 2>/dev/null || true ;;
      b) nixie rollback --boot-previous 2>&1 | tee >(logger -t nixie-panel) | tail -2; sleep 3; stty -echo 2>/dev/null || true ;;
      # Re-enrolment asks for the recovery key and PIN on this console.
      e) nixie security reenroll || true; read -r -s -n 1 -p "press any key"; stty -echo 2>/dev/null || true ;;
      *) exec login ;;
    esac
  fi
done
