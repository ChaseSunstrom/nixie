#!/usr/bin/env bash
# Phase 6: bind the outer layer to the TPM with a PIN, enrol the recovery
# key, start attestation, set the TPM lockout password, and produce the
# encrypted header backup bundle.
# Options: --backup-dest DIR copies the bundle there as well; --force redoes
# the TPM binding, the recovery key and the attestation secret (reenroll).
set -euo pipefail
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"
phase_start 6
dest=""; force=0
while [ $# -gt 0 ]; do case "$1" in --backup-dest) dest="$2"; shift 2 ;; --force) force=1; shift ;; *) shift ;; esac; done
feature encryption || { phase_finish; exit 0; }
need cryptsetup age tar openssl systemd-cryptenroll
recovery=""

# Key slots holding recovery keys, from the token list.
recovery_slots() {
  cryptsetup luksDump "$1" | awk '/^Tokens:/{t=1} t && /^ +[0-9]+: systemd-recovery/{r=1; next} t && /^ +[0-9]+: /{r=0} r && /Keyslot:/{printf "%s%s", sep, $2; sep=","}'
}

if feature tpm; then
  need tpm2_changeauth tpm2_dictionarylockout
  have_secret pin || die "no PIN given"
  # The install passphrase opens the outer layer at setup; afterwards only
  # the recovery key can (a reenroll after a board or TPM change).
  if have_secret passphrase; then unlock=$(secret_file passphrase); wipe=0
  elif have_secret recovery-key; then unlock=$(secret_file recovery-key); wipe=""
  else die "no passphrase or recovery key given"; fi
  outer=$(layout '.luks[] | select(.name == "rpool-outer") | .device')
  pcrs=$(layout '.features.pcrs | join("+")')
  if cryptsetup luksDump "$outer" | grep -q 'systemd-tpm2'; then
    if [ "$force" = 1 ]; then
      systemd-cryptenroll --unlock-key-file="$unlock" --wipe-slot=tpm2 "$outer"
      log "old TPM binding removed from $outer"
    else log "TPM slot already enrolled on $outer"; fi
  fi
  if ! cryptsetup luksDump "$outer" | grep -q 'systemd-tpm2'; then
    NEWPIN=$(cat "$(secret_file pin)") systemd-cryptenroll --unlock-key-file="$unlock" \
      --tpm2-device=auto --tpm2-with-pin=yes --tpm2-pcrs="$pcrs" "$outer"
    # The recovery key is the only way in when the TPM cannot unseal. It is
    # shown once by the front end and kept nowhere on this machine; a new one
    # replaces every older one.
    old=$(recovery_slots "$outer")
    recovery=$(systemd-cryptenroll --unlock-key-file="$unlock" --recovery-key "$outer" | tail -1)
    mkdir -p "$NIXIE_KEYS"; (umask 077; printf '%s' "$recovery" >"$(secret_file recovery-key)")
    [ -n "$old" ] && wipe="${wipe:+$wipe,}$old"
    [ -z "$wipe" ] || systemd-cryptenroll --unlock-key-file="$(secret_file recovery-key)" --wipe-slot="$wipe" "$outer"
    log "outer layer bound to TPM (PCRs $pcrs) with PIN"
    log "recovery key (shown once, write it down): $recovery"
  fi
  if [ ! -s /var/lib/nixie/tpm-lockout-auth ] || [ "$force" = 1 ]; then
    oldauth=(); [ -s /var/lib/nixie/tpm-lockout-auth ] && oldauth=(-p "$(cat /var/lib/nixie/tpm-lockout-auth)")
    auth=$(openssl rand -hex 16)  # 32 chars: the TPM auth limit is one digest (32 bytes)
    # Reading the sealed objects during earlier boots can trip the TPM's
    # dictionary-attack lockout; clear it before setting our own auth. After
    # a TPM reset the old auth is gone, so both forms are tried.
    tpm2_dictionarylockout --clear-lockout "${oldauth[@]}" 2>/dev/null || tpm2_dictionarylockout --clear-lockout 2>/dev/null || true
    if tpm2_changeauth -c lockout "${oldauth[@]}" "$auth" 2>/dev/null || tpm2_changeauth -c lockout "$auth"; then
      (umask 077; echo "$auth" >/var/lib/nixie/tpm-lockout-auth)
      log "TPM lockout password set"
    else
      log "could not set the TPM lockout password; leaving it unset"
    fi
  fi
fi

if feature attestation; then
  need tpm2-totp
  if [ "$force" = 1 ] || ! tpm2-totp calculate >/dev/null 2>&1; then
    # A recovery password lets `nixie reseal` re-seal the same secret to a new
    # boot chain (after a kernel update) without changing the code the person
    # already scanned. It is kept root-only and travels in the header backup.
    [ -s /var/lib/nixie/totp-recovery ] || (umask 077; openssl rand -hex 16 >/var/lib/nixie/totp-recovery)
    tpm2-totp clean >/dev/null 2>&1 || true
    tpm2-totp generate -P "$(cat /var/lib/nixie/totp-recovery)" -p 4,7,8,9 >"$(secret_file attestation-qr)" 2>&1
    log "attestation secret created; show $(secret_file attestation-qr) to the person once"
  fi
  # The initrd compares its own generation label with this to refuse showing
  # a code that cannot match on another generation.
  mkdir -p /boot/nixie && cat /run/current-system/nixos-version >/boot/nixie/attestation-generation
fi

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for pair in $(layout '.luks[] | .name + "=" + .device'); do
  cryptsetup luksHeaderBackup "${pair#*=}" --header-backup-file "$tmp/${pair%%=*}.header"
done
{
  echo "Nixie header backup for $(host), $(date -Is)"
  echo "Outer layer recovery key: shown once at setup and not stored on the host; 'nixie backup kit' enrols a fresh one."
  [ -s /var/lib/nixie/tpm-lockout-auth ] && echo "TPM lockout password: $(cat /var/lib/nixie/tpm-lockout-auth)"
  [ -s /var/lib/nixie/totp-recovery ] && echo "Attestation reseal password: $(cat /var/lib/nixie/totp-recovery)"
  echo "Restore a header with: cryptsetup luksHeaderRestore <device> --header-backup-file <name>.header"
} >"$tmp/RECOVERY.txt"
# The host's own key is in .sops.yaml as well; age warns about a repeat.
recipients=()
while read -r r; do recipients+=(-r "$r"); done < <({
  cat "$NIXIE_SETUP_DIR/age.pub" 2>/dev/null || age-keygen -y /var/lib/nixie/age.key
  grep -oE 'age1[0-9a-z]+' "$NIXIE_SITE/.sops.yaml"
} | sort -u)
tar -C "$tmp" -cf - . | age "${recipients[@]}" >"$NIXIE_SETUP_DIR/header-backup.tar.age"
chmod 0600 "$NIXIE_SETUP_DIR/header-backup.tar.age"
[ -z "$dest" ] || install -m 0600 "$NIXIE_SETUP_DIR/header-backup.tar.age" "$dest/nixie-$(host)-headers.tar.age"
log "header backup bundle at $NIXIE_SETUP_DIR/header-backup.tar.age${dest:+ and $dest}"
phase_finish
