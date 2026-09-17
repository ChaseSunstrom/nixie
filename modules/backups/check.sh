# shellcheck shell=bash
set -u
mkdir -p /var/lib/nixie
out=$(restic-nixie check 2>&1); rc=$?
@jq@/bin/jq -n --arg t "$(date -Is)" --arg o "$(printf '%s' "$out" | tail -n 5)" --argjson ok "$([ $rc = 0 ] && echo true || echo false)" \
  '{ok: $ok, time: $t, output: $o}' >/var/lib/nixie/backup-check.json
exit $rc
