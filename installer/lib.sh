# Shared by every phase. Sourced, never executed.
# shellcheck shell=bash
: "${NIXIE_SETUP_DIR:=/var/lib/nixie/setup}"
: "${NIXIE_KEYS:=/run/nixie/keys}"
: "${NIXIE_SITE:=/etc/nixie/site}"
: "${NIXIE_TOPLEVEL:=/run/current-system}"
STATE="$NIXIE_SETUP_DIR/state.json"

log() { printf '[nixie %s] %s\n' "${PHASE:-}" "$*" >&2; }
die() { log "$*"; exit 1; }
marker() { echo "$NIXIE_SETUP_DIR/$1.done"; }
need() { for c in "$@"; do command -v "$c" >/dev/null || die "missing tool: $c"; done; }

# Every phase is idempotent: a marker means it already ran to completion.
phase_start() {
  PHASE="$1"
  mkdir -p "$NIXIE_SETUP_DIR"
  if [ -e "$(marker "$PHASE")" ]; then log "already done, skipping"; exit 0; fi
  log "starting"
}
phase_finish() { date -Is >"$(marker "$PHASE")"; log "done"; }

state() { jq -r "$1" "$STATE"; }
host() { state .host; }
layout() { jq -r "$1" "$NIXIE_TOPLEVEL/etc/nixie/layout.json"; }
feature() { [ "$(layout ".features.$1")" = true ]; }
secret_file() { echo "$NIXIE_KEYS/$1"; }
have_secret() { [ -s "$(secret_file "$1")" ]; }
