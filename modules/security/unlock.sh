devices=(@devices@)
duress=@duress@
plymouth=@plymouth@
nixieTheme=@nixieTheme@
remote=""
if [ -n "${SSH_CONNECTION:-}" ]; then
  remote=1
  # Without a terminal the answer would be a cancellation, which
  # systemd-cryptsetup takes as a failure: one `ssh root@<host> true`
  # left a machine in emergency mode.
  if [ ! -t 0 ]; then
    echo "remote unlock needs a terminal: ssh -t -p <port> root@<host>" >&2
    exit 1
  fi
fi

# The splash is this machine's own screen, which a remote session must
# never wait on.
splash() { [ -z "$remote" ] && [ -n "$plymouth" ] && "$plymouth" --ping 2>/dev/null; }
# A line for the person, which any theme shows (the Nixie one under
# the field), each replacing the last.
said=""
say() {
  splash || return 0
  [ -z "$said" ] || "$plymouth" hide-message --text="$said" 2>/dev/null || true
  said=$1
  [ -z "$said" ] || "$plymouth" display-message --text="$said" 2>/dev/null || true
}
# Instructions only the Nixie theme (packages/nixie-plymouth.nix)
# reads, as status updates: Plymouth's text view, on a serial console
# or behind Escape, prints messages but not these.
tell() {
  [ -n "$nixieTheme" ] && splash || return 0
  "$plymouth" update --status="nixie-$1" 2>/dev/null || true
}

# Plymouth cannot withdraw a question. One answered elsewhere stays on
# screen, so it is kept and the next request takes it over rather than
# queueing behind it.
ply_pid=""
ply_fd=""
ask_splash() { # label
  tell "prompt:$1"
  if [ -z "$ply_pid" ]; then
    coproc PLY { exec "$plymouth" ask-for-password --prompt="$1" 2>/dev/null; }
    ply_pid=$!
    exec {ply_fd}<&"${PLY[0]}"
  fi
  pw=""
  local chunk rc
  while :; do
    chunk=""
    IFS= read -r -d "" -t 0.3 -u "$ply_fd" chunk && rc=0 || rc=$?
    pw+=$chunk
    if [ "$rc" -le 128 ]; then
      # The answer, or Ctrl+C, which ends the question with nothing.
      wait "$ply_pid" && rc=0 || rc=$?
      exec {ply_fd}<&-
      ply_pid=""
      [ "$rc" = 0 ] && return 0
      pw=""
      return 1
    fi
    if [ ! -e "$ask" ]; then
      tell idle
      pw=""
      return 1
    fi
  done
}

last=""
while true; do
  handled=0
  for ask in /run/systemd/ask-password/ask.*; do
    [ -e "$ask" ] || continue
    handled=1
    # Only bash builtins read these files: the initrd copies this
    # script, not the tools on its PATH.
    msg=""; sock=""; pid=""
    while IFS='=' read -r k v; do
      case $k in Message) msg=$v ;; Socket) sock=$v ;; PID) pid=$v ;; esac
    done <"$ask"
    # The layer being opened, from systemd-cryptsetup's arguments: its
    # PIN request carries no name.
    name=""; dev=""; args=()
    [ -z "$pid" ] || mapfile -d "" -t args <"/proc/$pid/cmdline" 2>/dev/null || true
    if [ "${args[1]:-}" = attach ]; then name=${args[2]:-}; dev=${args[3]:-}; fi
    # The same process asking again means the last answer was wrong.
    again=""
    [ "$pid:$msg" != "$last" ] || again="That did not open the disk. Try again."
    if splash; then
      # systemd asks every token's PIN alike; the TPM's is the outer
      # layer's, a security key's the passphrase layer's.
      # A machine with a TPM layer is asked twice at every start once that
      # layer is bound: the PIN opens the outer one, and the inner one has
      # no answer to reuse, so it asks for its own. Saying which of the two
      # is being asked for is the difference between a second lock and the
      # same question apparently asked twice.
      two=""; [ ! -e /dev/mapper/rpool-outer ] || two=" (2 of 2)"
      case $msg in
        *PIN*) if [[ $name == *-outer ]]; then label="PIN (1 of 2)"; else label="Security key PIN$two"; fi ;;
        *) if [[ $name == *-outer ]]; then label="Passphrase or recovery key"; else label="Disk passphrase$two"; fi ;;
      esac
      say "$again"
      # For the journal: nothing on the screen says what was asked.
      echo "<5>nixie-unlock: asking for $label on the splash${again:+ again}" >/dev/kmsg 2>/dev/null || true
      ask_splash "$label" || continue
      say "Unlocking…"
    else
      [ -z "$again" ] || echo "$again"
      printf '%s ' "$msg"
      IFS= read -rs pw
      echo
    fi
    last="$pid:$msg"
    # Slot 7 is the duress passphrase, on every layer a person types at,
    # as a slot that opens nothing (phase 3); testing that one slot is
    # a single key derivation, not one per slot.
    if [ -n "$duress" ] && [ -n "$dev" ] &&
      printf '%s' "$pw" | cryptsetup open --test-passphrase --key-slot 7 --key-file=- "$dev" 2>/dev/null; then
      for d in "${devices[@]}"; do
        cryptsetup -q erase "$d" || true
        # erase leaves slots that open nothing.
        cryptsetup -q luksKillSlot "$d" 7 </dev/null || true
      done
      sync
      systemctl --force --force poweroff
      exit 0
    fi
    printf '%s' "$pw" | systemd-reply-password 1 "$sock"
    pw=""
    while [ -e "$ask" ]; do sleep 0.2; done
  done
  if [ "$handled" = 0 ]; then
    # Nothing pending and the root file system is up: done. Lingering
    # would hold the initrd's sshd stop job for its whole timeout.
    if systemctl -q is-active initrd-root-fs.target; then
      say ""
      exit 0
    fi
    sleep 0.5
  fi
done
