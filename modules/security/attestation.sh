# shellcheck shell=bash
# The boot attestation code, in the initrd. `once` prints it on the console
# and puts it on the splash before the first prompt; `watch` keeps the
# splash's code current until the disks are open. Values from attestation.nix.
set -u
plymouth=@plymouth@
esp=@esp@
tpm2totp=@tpm2totp@
sealedFile=@sealedFile@

# Which system this is, for comparing with the one the secret is sealed for.
booted=""
read -r cmdline </proc/cmdline
for w in $cmdline; do
  case $w in init=*) booted=${w#init=}; booted=${booted%/init} ;; esac
done

state() {
  sealed=$(cat /run/nixie-attestation-sealed 2>/dev/null || true)
  if [ -n "$sealed" ] && [ "$sealed" != "$booted" ]; then
    # Sealed for another system, so no code can match.
    kind=warn
    text="No attestation code: this system changed since it was sealed. Unlock only if you updated it."
  elif code=$("$tpm2totp" calculate 2>/dev/null); then
    kind=code
    text=$code
  elif [ -z "$sealed" ]; then
    # Before setup seals one; a machine set up long ago that says this has
    # had its ESP changed.
    kind=warn
    text="No attestation code yet: setup seals one. If this machine was set up before, do not unlock it."
  else
    kind=warn
    text="ATTESTATION FAILED: the boot chain was changed. Do not unlock unless you know why."
  fi
}

# Put a line on the splash, replacing the one shown before; any theme shows
# it, and the Nixie one draws a code large.
tell() {
  [ -n "$plymouth" ] || return 0
  old=$(cat /run/nixie-attestation-shown 2>/dev/null || true)
  [ "$old" != "$1" ] || return 0
  [ -z "$old" ] || "$plymouth" hide-message --text="$old" 2>/dev/null || true
  printf '%s' "$1" >/run/nixie-attestation-shown
  [ -z "$1" ] || "$plymouth" display-message --text="$1" 2>/dev/null || true
}
line() { if [ "$kind" = code ]; then echo "Attestation code $text"; else echo "$text"; fi; }

case ${1:-once} in
  once)
    # The TPM's device node, for a few seconds only: this runs in front of
    # every disk prompt, so waiting here is waiting the person does. A
    # machine without one says there is no code and gets out of the way.
    for _ in $(seq 20); do [ -e /dev/tpmrm0 ] && break; sleep 0.25; done
    # The ESP's link too: on a SATA disk (VirtualBox's) udev makes it after
    # this starts, and without the record a failed code reads "not yet".
    for _ in $(seq 20); do [ -z "$esp" ] || [ -e "$esp" ] && break; sleep 0.25; done
    if [ -n "$esp" ] && [ -e "$esp" ]; then
      mkdir -p /run/nixie-esp
      if mount -o ro "$esp" /run/nixie-esp 2>/dev/null; then
        cat "/run/nixie-esp/$sealedFile" >/run/nixie-attestation-sealed 2>/dev/null || true
        umount /run/nixie-esp 2>/dev/null || true
      fi
    fi
    state
    echo
    if [ "$kind" = code ]; then echo "  Attestation code: $text"; else echo "  $text"; fi
    echo
    tell "$(line)"
    # For the journal, without the code: Plymouth keeps what is written to
    # the console while it runs.
    echo "<5>nixie-attestation: $kind shown" >/dev/kmsg 2>/dev/null || true
    ;;
  watch)
    window=$(($(date +%s) / 30))
    until systemctl -q is-active cryptsetup.target; do
      sleep 1
      now=$(($(date +%s) / 30))
      [ "$now" != "$window" ] || continue
      window=$now
      state
      tell "$(line)"
    done
    tell ""
    ;;
esac
