#!/usr/bin/env bash
# Phase 5: Secure Boot enrolment. The firmware trusts this machine's boot
# chain only once this machine's keys are in it, and systemd-boot enrols them
# on the next boot while the firmware is in Setup Mode. Secure Boot has to
# stay off until then: turned on while the firmware still holds other keys,
# it refuses the signed boot loader ("Access Denied"), and the installer too.
# Exit 10: Setup Mode; restart, and systemd-boot enrols the keys.
# Exit 11: the firmware holds other keys; clear them, leave Secure Boot off.
# Exit 12: this machine's keys are enrolled; turn Secure Boot on.
set -euo pipefail
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"
phase_start 5
feature secureBoot || { phase_finish; exit 0; }
need bootctl openssl od
: "${NIXIE_EFIVARS:=/sys/firmware/efi/efivars}"
: "${NIXIE_SBCTL:=/var/lib/sbctl}"
status=$(bootctl status 2>/dev/null || true)

# Whether the firmware's platform key is this machine's: its certificate is
# inside the PK variable. bootctl says "disabled" alike for a firmware that
# holds its vendor's keys and for one that holds ours with the switch off, and
# only the second may be told to turn Secure Boot on.
ours_enrolled() {
  local pk="$NIXIE_EFIVARS/PK-8be4df61-93ca-11d2-aa0d-00e098032b8c" mine
  [ -r "$pk" ] && [ -r "$NIXIE_SBCTL/keys/PK/PK.pem" ] || return 1
  mine=$(openssl x509 -in "$NIXIE_SBCTL/keys/PK/PK.pem" -outform DER | od -An -v -tx1 | tr -d ' \n')
  [ -n "$mine" ] && od -An -v -tx1 "$pk" | tr -d ' \n' | grep -q "$mine"
}

if printf '%s' "$status" | grep -qE 'Secure Boot: *enabled'; then
  log "Secure Boot is enabled with our keys"
  phase_finish; exit 0
fi
if printf '%s' "$status" | grep -qE 'Setup Mode: *setup|\(setup\)'; then
  log "firmware is in Setup Mode; the keys are staged on the boot partition."
  log "Restart: systemd-boot enrols them, and setup then says when to turn Secure Boot on."
  exit 10
fi
if ours_enrolled; then
  cat >&2 <<'MSG'
This machine's keys are in the firmware now, and Secure Boot is still off.
In the firmware settings, turn Secure Boot on, save, and boot again.
MSG
  exit 12
fi
if [ "$(systemd-detect-virt 2>/dev/null || true)" = oracle ]; then
  # VirtualBox's settings cannot do this: its Secure Boot checkbox refuses
  # without a PK, and "Reset Keys to Default" (and the checkbox on a VM that
  # never had keys) enrols Oracle's and Microsoft's, which refuse this
  # machine's loader. Its firmware menu can.
  cat >&2 <<'MSG'
VirtualBox holds its own Secure Boot keys. Restart into the firmware settings
(or press Esc as the VM starts), then:
  1. Device Manager > Secure Boot Configuration.
  2. Secure Boot Mode: Custom Mode.
  3. Custom Secure Boot Options > PK Options > Delete Pk, and answer Y.
  4. Esc back to the first menu and choose Reset.
The VM then enrols this machine's keys and turns Secure Boot on by itself.
Do not press "Reset Keys to Default" in the VM's settings: it puts
VirtualBox's keys back, and the VM then shows "Access Denied". If that
happened, untick Secure Boot there and repeat the steps.
MSG
  exit 11
fi
cat >&2 <<'MSG'
The firmware holds other Secure Boot keys. In the firmware settings, under
Secure Boot:
  1. If there is a "Secure Boot Mode", set it to Custom (some say User).
  2. Delete or reset the keys ("Delete all keys", "Reset to Setup Mode",
     "Clear Secure Boot keys"). That is Setup Mode.
  3. Leave Secure Boot itself off for now, save, and boot again.
This machine then enrols its own keys by itself, and setup says when to turn
Secure Boot on. Turned on while the old keys are still there, the firmware
refuses to start anything and shows "Access Denied"; if that has happened,
turn Secure Boot off again. Nothing is lost.
MSG
exit 11
