#!/usr/bin/env bash
# Phase 4: the installed system is up. Confirm the identity and network are in
# place before any enrolment touches the hardware.
set -euo pipefail
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"
phase_start 4
[ -s /var/lib/nixie/age.key ] || die "host identity missing"
[ -d "$NIXIE_SITE" ] || die "site checkout missing at $NIXIE_SITE"
systemctl is-active -q systemd-networkd NetworkManager 2>/dev/null || log "no network manager active yet"
phase_finish
