#!/usr/bin/env bash
# Phase 7: after the verification reboot, prove each enabled feature did its
# job on this boot.
set -euo pipefail
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"
phase_start 7
fail=0
if feature tpm; then
  if journalctl -b -o cat | grep -q 'Unlocked volume via automatically discovered security TPM2 token'; then
    log "outer layer was unlocked by the TPM this boot"
  else log "outer layer was NOT unlocked by the TPM"; fail=1; fi
fi
if feature attestation; then
  if tpm2-totp show >/dev/null 2>&1; then log "attestation code computes"; else log "attestation code does not compute"; fail=1; fi
fi
if feature secureBoot; then
  if bootctl status 2>/dev/null | grep -qE 'Secure Boot: *enabled'; then log "Secure Boot enabled"; else log "Secure Boot not enabled"; fail=1; fi
fi
[ "$fail" = 0 ] || die "verification failed"
phase_finish
