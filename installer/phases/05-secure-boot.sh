#!/usr/bin/env bash
# Phase 5: Secure Boot enrolment. systemd-boot enrols the keys on the next
# boot while the firmware is in Setup Mode; this phase tells the person what
# state the firmware is in and finishes once Secure Boot is on.
# Exit 10 means: reboot now, then run again.
set -euo pipefail
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"
phase_start 5
feature secureBoot || { phase_finish; exit 0; }
need bootctl
status=$(bootctl status 2>/dev/null || true)
if printf '%s' "$status" | grep -qE 'Secure Boot: *enabled'; then
  log "Secure Boot is enabled with our keys"
  phase_finish; exit 0
fi
if printf '%s' "$status" | grep -qE 'Setup Mode: *setup|\(setup\)'; then
  log "firmware is in Setup Mode; the keys are staged on the boot partition."
  log "Reboot: systemd-boot will enrol them and Secure Boot turns on."
  exit 10
fi
cat >&2 <<'MSG'
Secure Boot is off and the firmware is not in Setup Mode. In the firmware
setup: clear (delete) the existing Secure Boot keys, which puts it in Setup
Mode, keep Secure Boot itself set to enabled, save, and boot again.
MSG
exit 11
