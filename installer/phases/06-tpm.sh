#!/usr/bin/env bash
# Phase 6: bind the outer layer to the TPM with a PIN, start attestation, set
# the TPM lockout password, and produce the encrypted header backup bundle.
# Options: --backup-dest DIR copies the bundle there as well.
set -euo pipefail
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"
phase_start 6
dest=""; while [ $# -gt 0 ]; do case "$1" in --backup-dest) dest="$2"; shift 2 ;; *) shift ;; esac; done
feature encryption || { phase_finish; exit 0; }
need cryptsetup age tar openssl systemd-cryptenroll
have_secret passphrase || die "no passphrase given"
pass=$(secret_file passphrase)
recovery=""

if feature tpm; then
  need tpm2_changeauth
  have_secret pin || die "no PIN given"
  outer=$(layout '.luks[] | select(.name == "rpool-outer") | .device')
  pcrs=$(layout '.features.pcrs | join("+")')
  if cryptsetup luksDump "$outer" | grep -q 'systemd-tpm2'; then
    log "TPM slot already enrolled on $outer"
  else
    NEWPIN=$(cat "$(secret_file pin)") systemd-cryptenroll --unlock-key-file="$pass" \
      --tpm2-device=auto --tpm2-with-pin=yes --tpm2-pcrs="$pcrs" "$outer"
    recovery=$(systemd-cryptenroll --unlock-key-file="$pass" --recovery-key "$outer" | tail -1)
    # The install passphrase is only a bootstrap for the outer layer; from now
    # on it opens with the TPM and PIN, or the recovery key.
    systemd-cryptenroll --unlock-key-file="$pass" --wipe-slot=password "$outer"
    log "outer layer bound to TPM (PCRs $pcrs) with PIN"
  fi
  if [ ! -s /var/lib/nixie/tpm-lockout-auth ]; then
    auth=$(openssl rand -hex 32)
    if tpm2_changeauth -c lockout "$auth" 2>/dev/null; then
      (umask 077; echo "$auth" >/var/lib/nixie/tpm-lockout-auth)
      log "TPM lockout password set"
    else
      log "TPM lockout password already set elsewhere; not changed"
    fi
  fi
fi

if feature attestation; then
  need tpm2-totp
  if ! tpm2-totp show >/dev/null 2>&1; then
    tpm2-totp init -p 4,7,8,9 >"$(secret_file attestation-qr)" 2>&1
    log "attestation secret created; show $(secret_file attestation-qr) to the person once"
  fi
fi

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for pair in $(layout '.luks[] | .name + "=" + .device'); do
  cryptsetup luksHeaderBackup "${pair#*=}" --header-backup-file "$tmp/${pair%%=*}.header"
done
{
  echo "Nixie header backup for $(host), $(date -Is)"
  [ -n "$recovery" ] && echo "Outer layer recovery key: $recovery"
  [ -s /var/lib/nixie/tpm-lockout-auth ] && echo "TPM lockout password: $(cat /var/lib/nixie/tpm-lockout-auth)"
  echo "Restore a header with: cryptsetup luksHeaderRestore <device> --header-backup-file <name>.header"
} >"$tmp/RECOVERY.txt"
recipients=(-r "$(cat "$NIXIE_SETUP_DIR/age.pub" 2>/dev/null || age-keygen -y /var/lib/nixie/age.key)")
while read -r r; do recipients+=(-r "$r"); done < <(grep -oE 'age1[0-9a-z]+' "$NIXIE_SITE/.sops.yaml" | sort -u)
tar -C "$tmp" -cf - . | age "${recipients[@]}" >"$NIXIE_SETUP_DIR/header-backup.tar.age"
chmod 0600 "$NIXIE_SETUP_DIR/header-backup.tar.age"
[ -z "$dest" ] || install -m 0600 "$NIXIE_SETUP_DIR/header-backup.tar.age" "$dest/nixie-$(host)-headers.tar.age"
log "header backup bundle at $NIXIE_SETUP_DIR/header-backup.tar.age${dest:+ and $dest}"
phase_finish
