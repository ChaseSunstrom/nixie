#!/usr/bin/env bash
# Phase 2: the host's age identity, the site's sops wiring and the secrets the
# chosen features need. A host that already has a decryptable secrets file is
# being reinstalled and keeps it.
set -euo pipefail
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"
phase_start 2
need age age-keygen sops jq mkpasswd openssl uuidgen
h=$(host); secrets="$NIXIE_SITE/secrets/$h.yaml"; mkdir -p "$NIXIE_SITE/secrets"
key="$NIXIE_SETUP_DIR/age.key"

if have_secret age.key; then
  install -m 0600 "$(secret_file age.key)" "$key"
elif [ ! -s "$key" ]; then
  (umask 077; age-keygen -o "$key" 2>/dev/null)
fi
pub=$(age-keygen -y "$key"); echo "$pub" >"$NIXIE_SETUP_DIR/age.pub"
export SOPS_AGE_KEY_FILE="$key"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
existing=""
if [ -s "$secrets" ] && existing=$(sops -d "$secrets" 2>/dev/null); then
  log "extending existing secrets for $h"
fi
{
  if printf '%s\n' "$existing" | grep -q '^admin-password:'; then
    printf '%s\n' "$existing"
  else
    have_secret admin-password || die "no administrator password given"
    echo "admin-password: $(mkpasswd -m yescrypt -s <"$(secret_file admin-password)")"
  fi
  if have_secret totp-secret && ! printf '%s\n' "$existing" | grep -q '^totp-secret:'; then
    echo "totp-secret: $(cat "$(secret_file totp-secret)")"
  fi
  if [ "$(state '.options.secureBoot // false')" = true ] && ! printf '%s\n' "$existing" | grep -q '^secureboot:'; then
    echo "secureboot:"
    echo "  GUID: $(uuidgen)"
    for k in PK KEK db; do
      openssl req -quiet -newkey rsa:4096 -nodes -keyout "$tmp/$k.key" -new -x509 -sha256 -days 3650 \
        -subj "/CN=Nixie $k/" -out "$tmp/$k.pem" 2>/dev/null
      for ext in key pem; do
        echo "  $k.$ext: |"; sed 's/^/    /' "$tmp/$k.$ext"
      done
    done
  fi
} >"$tmp/plain.yaml"

# Recipients: this host, plus anyone already listed for it in .sops.yaml.
rules="$NIXIE_SITE/.sops.yaml"
if [ ! -s "$rules" ]; then
  cat >"$rules" <<YAML
# Recipients per host. The host key is made by the installer; add your own
# age or PGP key here to be able to edit secrets from your machine.
keys:
  - &$h $pub
creation_rules:
  - path_regex: secrets/$h\\.yaml\$
    key_groups:
      - age:
          - *$h
YAML
elif ! grep -q "$pub" "$rules"; then
  # Append an anchor for this host; existing rules stay untouched.
  printf '  - &%s %s\n' "$h" "$pub" >>"$rules"
fi
# sops takes recipients from a .sops.yaml whenever one is in scope, so encrypt
# away from the site with every recipient it lists for this host plus ours.
recipients=$( (grep -oE 'age1[0-9a-z]+' "$rules"; echo "$pub") | sort -u | paste -sd,)
(cd "$tmp" && sops --encrypt --age "$recipients" plain.yaml) >"$secrets"
log "wrote $secrets (recipients $recipients)"
phase_finish
