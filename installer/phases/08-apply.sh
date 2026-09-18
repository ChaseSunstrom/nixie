#!/usr/bin/env bash
# Phase 8: the everyday state. Runs `nixie apply` from the site checkout so
# guests, data and services exist before setup finishes. The host is left
# alone: it already runs the site's system, and switching it here would leave
# the setup generation, stopping the wizard (and this phase with it) before
# Finish, which does that switch.
set -euo pipefail
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"
phase_start 8
STEPS=2
step "guests, data and services from the site"
if command -v nixie >/dev/null; then nixie apply --skip-host --yes; else log "nixie CLI not installed; nothing to apply"; fi
step "filling the cache the site's data manifest lists"
# Started, not waited on: a manifest can name tens of gigabytes, and setup
# has no business holding the wizard open for that. It is re-runnable, and
# nixie.data.fetch.timer keeps it current afterwards.
if systemctl cat nixie-fetch.service >/dev/null 2>&1; then
  systemctl start --no-block nixie-fetch.service || log "the cache fetch did not start; run nixie fetch later"
else
  log "this host declares no data to fetch"
fi
phase_finish
