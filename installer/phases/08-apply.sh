#!/usr/bin/env bash
# Phase 8: the everyday state. Runs `nixie apply` from the site checkout so
# guests, data and services exist before setup finishes.
set -euo pipefail
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"
phase_start 8
if command -v nixie >/dev/null; then nixie apply --yes; else log "nixie CLI not installed; nothing to apply"; fi
phase_finish
