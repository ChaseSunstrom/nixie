#!/usr/bin/env bash
# Phase 3: partition, format and install. Runs on the ISO or under
# nixos-anywhere. Expects the passphrase and other secrets in $NIXIE_KEYS.
set -euo pipefail
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"
phase_start 3
need jq nixos-install cryptsetup zpool ssh-keygen sops
h=$(host)

# A front end that already built the system passes NIXIE_TOPLEVEL and
# NIXIE_DISKO (tests, deploy). Otherwise only the small pieces are built in
# the installer's memory-backed store and nixos-install builds the system
# straight into the target disk.
flake=0
if [ "$NIXIE_TOPLEVEL" = /run/current-system ]; then
  flake=1
  # A git flake sees only tracked files, and phases 1 and 2 have just written
  # hardware.nix, the secrets and the sops rules.
  [ ! -d "$NIXIE_SITE/.git" ] || git -C "$NIXIE_SITE" add -A
  log "evaluating $h from $NIXIE_SITE"
  layoutFile=$(nix build --no-link --print-out-paths "$NIXIE_SITE#nixosConfigurations.$h.config.environment.etc.\"nixie/layout.json\".source")
  mkdir -p "$NIXIE_SETUP_DIR/layout/etc/nixie"
  cp "$layoutFile" "$NIXIE_SETUP_DIR/layout/etc/nixie/layout.json"
  NIXIE_TOPLEVEL="$NIXIE_SETUP_DIR/layout"
  NIXIE_DISKO=$(nix build --no-link --print-out-paths "$NIXIE_SITE#nixosConfigurations.$h.config.system.build.diskoScript")
fi
: "${NIXIE_DISKO:?disko script path}"

# The disko layout reads each layer's passphrase from /run/nixie/keys/<name>.
mkdir -p /run/nixie/keys; chmod 700 /run/nixie/keys
if feature encryption; then
  have_secret passphrase || die "no passphrase given"
  for name in $(layout '.luks[].name'); do install -m 0600 "$(secret_file passphrase)" "/run/nixie/keys/$name"; done
  [ "$(layout .data)" = null ] || (umask 077; head -c 64 /dev/urandom >/run/nixie/keys/dpool.key)
fi

log "partitioning and formatting"
"$NIXIE_DISKO"

if feature duress; then
  have_secret duress || die "no duress passphrase given"
  dev=$(layout '.luks[] | select(.name == "rpool") | .device')
  cryptsetup luksAddKey --key-slot 7 --key-file "$(secret_file passphrase)" "$dev" "$(secret_file duress)"
  log "duress passphrase enrolled in slot 7 of $dev"
fi

install -d -m 0700 /mnt/var/lib/nixie /mnt/var/lib/nixie/setup
install -m 0600 "$NIXIE_SETUP_DIR/age.key" /mnt/var/lib/nixie/age.key
export SOPS_AGE_KEY_FILE="$NIXIE_SETUP_DIR/age.key"
if [ -s /run/nixie/keys/dpool.key ]; then
  install -d -m 0700 /mnt/etc/nixie/keys
  install -m 0400 /run/nixie/keys/dpool.key /mnt/etc/nixie/keys/dpool.key
fi
if feature secureBoot; then
  # lanzaboote signs during nixos-install, so the keys must be in place first.
  s="$NIXIE_SITE/secrets/$h.yaml"
  install -d -m 0700 /mnt/var/lib/sbctl/keys/{PK,KEK,db}
  sops -d --extract '["secureboot"]["GUID"]' "$s" >/mnt/var/lib/sbctl/GUID
  for k in PK KEK db; do for ext in key pem; do
    sops -d --extract "[\"secureboot\"][\"$k.$ext\"]" "$s" >"/mnt/var/lib/sbctl/keys/$k/$k.$ext"
  done; done
  chmod -R go-rwx /mnt/var/lib/sbctl
fi
if feature remoteUnlock; then
  mkdir -p /mnt/boot/nixie
  ssh-keygen -q -t ed25519 -N "" -f /mnt/boot/nixie/ssh_host_ed25519_key
  log "early-boot SSH host key: $(ssh-keygen -lf /mnt/boot/nixie/ssh_host_ed25519_key.pub)"
fi

# The site checkout travels to the installed system first: activation reads
# the secrets from it, and any front end resumes from phase 4 after the reboot.
mkdir -p /mnt/etc/nixie && cp -a "$NIXIE_SITE" /mnt/etc/nixie/site
if [ "$flake" = 1 ]; then
  log "installing $h from the site (built on the target disk)"
  nixos-install --flake "$NIXIE_SITE#$h" --root /mnt --no-root-passwd --no-channel-copy
else
  log "installing $NIXIE_TOPLEVEL"
  nixos-install --system "$NIXIE_TOPLEVEL" --root /mnt --no-root-passwd --no-channel-copy
fi
# Which loader entry comes up is loader.conf's business (modules/setup.nix).
# Firmware that keeps a still-attached installer first (VirtualBox rebuilds the
# order from the VM's device list at every start) would boot the installer
# again; BootNext sends the next boot to the installed loader regardless. The
# entry is picked by this ESP's partition GUID: a machine installed before
# keeps a stale "Linux Boot Manager" pointing at a partition that is gone.
esp=$(lsblk -no PARTUUID "$(findmnt -no SOURCE /mnt/boot)" 2>/dev/null || true)
n=$(efibootmgr 2>/dev/null | grep -i "Linux Boot Manager.*GPT,${esp:-none}," | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\).*/\1/p' | head -1 || true)
[ -z "$n" ] || efibootmgr -q --bootnext "$n" || log "could not point the next boot at the installed system"
phase_finish
cp -a "$NIXIE_SETUP_DIR"/*.done "$STATE" /mnt/var/lib/nixie/setup/

umount -R /mnt
zpool export -a
for name in $(layout '.luks[].name' | tac); do cryptsetup close "$name" 2>/dev/null || true; done
rm -rf /run/nixie/keys
log "installed; reboot into the new system"
