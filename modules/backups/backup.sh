# shellcheck shell=bash
case "${1:-}" in
  now) systemctl start restic-backups-nixie.service && restic-nixie snapshots --latest 1 ;;
  list) shift; exec restic-nixie snapshots "$@" ;;
  verify)
    systemctl start nixie-backup-check.service || true
    cat /var/lib/nixie/backup-check.json; echo
    jq -e .ok /var/lib/nixie/backup-check.json >/dev/null ;;
  kit)
    out=${2:?output file}; shift 2
    recipient=""
    while [ $# -gt 0 ]; do case "$1" in --recipient) recipient=$2; shift 2 ;; *) shift ;; esac; done
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/headers"
    # The header bundle (headers, TPM lockout auth, TOTP reseal password) is
    # encrypted to this host's key; the kit carries it in the clear inside
    # its own passphrase-encrypted envelope.
    if [ -e /var/lib/nixie/setup/header-backup.tar.age ]; then
      age -d -i /var/lib/nixie/age.key /var/lib/nixie/setup/header-backup.tar.age | tar -C "$tmp/headers" -xf -
    fi
    if [ -e /var/lib/nixie/age.key ]; then cp /var/lib/nixie/age.key "$tmp/age.key"
    else echo "no /var/lib/nixie/age.key on this host (not installed by setup); the site's sops secrets need another recipient" >"$tmp/age.key.missing"; fi
    cp @passwordFile@ "$tmp/restic-password"
    @kitEnv@
    @kitRclone@
    outer=$(jq -r '.luks[] | select(.name == "rpool-outer") | .device' /run/current-system/etc/nixie/layout.json)
    if [ "$(jq -r .features.tpm /run/current-system/etc/nixie/layout.json)" = true ] && [ -t 0 ]; then
      # A fresh recovery key for the outer layer replaces the old one; the
      # TPM unlocks with the PIN asked here.
      systemd-cryptenroll --unlock-tpm2-device=auto --wipe-slot=recovery "$outer" >/dev/null
      systemd-cryptenroll --unlock-tpm2-device=auto --recovery-key "$outer" | tail -1 >"$tmp/recovery-key.txt"
    else
      echo "Run 'nixie backup kit' from a terminal on the host to enrol a fresh recovery key for the outer layer; the previous one still opens it." >"$tmp/recovery-key.txt"
    fi
    cat >"$tmp/README.txt" <<EOF
Nixie disaster kit for $(hostname), $(date -Is). Keep it offline.
Rebuild from nothing: install from the ISO with the site repository,
give the wizard age.key when it asks for the host key, put
restic-password (and restic-env / rclone.conf) back as the site's
sops secrets, then on the new machine: nixie apply; nixie restore latest.
headers/: cryptsetup luksHeaderRestore <device> --header-backup-file <name>.header
recovery-key.txt: opens the TPM layer when the TPM cannot.
EOF
    if [ -n "$recipient" ]; then tar -C "$tmp" -cf - . | age -r "$recipient" >"$out"
    else tar -C "$tmp" -cf - . | age -p >"$out"; fi
    chmod 0600 "$out"; echo "kit written to $out" ;;
  *) echo "usage: nixie backup now | list [--json] | verify | kit <file> [--recipient <age key>]" >&2; exit 2 ;;
esac
