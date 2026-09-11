#!/usr/bin/env bash
# Phase 7: after the verification reboot, prove each enabled feature did its
# job on this boot.
set -euo pipefail
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"
phase_start 7
fail=0
if feature tpm; then
  # systemd-cryptsetup is silent on a successful token unlock, so verify the
  # positive facts: the outer layer is open and its unlock is bound to the TPM.
  outer=$(layout '.luks[] | select(.name == "rpool-outer") | .device')
  if [ -e /dev/mapper/rpool-outer ] && cryptsetup luksDump "$outer" | grep -q systemd-tpm2; then
    log "outer layer is open and bound to the TPM"
  else log "outer layer is NOT open or not bound to the TPM"; fail=1; fi
fi
if feature attestation; then
  if tpm2-totp calculate >/dev/null 2>&1; then log "attestation code computes"; else log "attestation code does not compute"; fail=1; fi
fi
if feature secureBoot; then
  if bootctl status 2>/dev/null | grep -qE 'Secure Boot: *enabled'; then log "Secure Boot enabled"; else log "Secure Boot not enabled"; fail=1; fi
fi
[ "$fail" = 0 ] || die "verification failed"
phase_finish
