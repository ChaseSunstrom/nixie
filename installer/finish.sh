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
# The kiosk goes first: the switch stops it, and switch-to-configuration then
# fails the half-torn-down session's user activation ("Failed to open dbus
# connection", status 4), which stops Finish here.
systemctl stop cage-tty1.service 2>/dev/null || true
loginctl terminate-user nixie-kiosk 2>/dev/null || true
for _ in $(seq 30); do loginctl show-user nixie-kiosk >/dev/null 2>&1 || break; sleep 1; done
# The kiosk's screen went with it and the console panel only comes with the
# switch: a minute or more of black screen looked like a hang, and a machine
# turned off then loses the switch (in VirtualBox, the TPM and the keys too).
chvt 1 2>/dev/null || true
printf '\033[2J\033[H\n\n  Finishing setup: switching to the normal system.\n  This takes a minute or two. Do not turn the machine off.\n' >/dev/tty1 2>/dev/null || true
nixie apply --yes
bootctl set-default "" 2>/dev/null || true
nix-env --profile /nix/var/nix/profiles/system --delete-generations old
nix-collect-garbage >/dev/null 2>&1 || true
date -Is >"$NIXIE_SETUP_DIR/finished"
# What the panel says was collected before setup sealed the attestation code
# and would say "does not compute" until its next run.
systemctl start --no-block nixie-notices.service 2>/dev/null || true
log "setup finished; the kiosk and the wizard are gone from this system"
