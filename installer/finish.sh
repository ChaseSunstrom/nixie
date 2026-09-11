#!/usr/bin/env bash
# Finish: leave the setup generation behind. The pending flag goes, the site
# is applied (which switches to the plain generation), the boot default is
# cleared, and older generations with the kiosk are removed.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
PHASE=finish
h=$(host)
pending="$NIXIE_SITE/hosts/$h/setup-pending.nix"
if [ -e "$pending" ]; then
  printf '# Managed by setup: true until Finish, then empty.\n{ }\n' >"$pending"
  git -C "$NIXIE_SITE" add -A && git -C "$NIXIE_SITE" commit -qm "setup: finished on $h" || true
fi
nixie apply --yes
bootctl set-default "" 2>/dev/null || true
nix-env --profile /nix/var/nix/profiles/system --delete-generations old
nix-collect-garbage >/dev/null 2>&1 || true
date -Is >"$NIXIE_SETUP_DIR/finished"
log "setup finished; the kiosk and the wizard are gone from this system"
