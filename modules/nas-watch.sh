# Once a minute: whether each NAS share answers, for the notices and `nixie
# nas status`; for "hold" shares, the running guests that need it stopped
# while it is gone and started again when it is back.
set -uo pipefail
set +e # one share or guest failing must not stop the others being checked
cfg=${NIXIE_NAS:-/etc/nixie/nas.json}
held=/run/nixie/nas-held # guests this stopped, one per line
mkdir -p /run/nixie
touch "$held"

running() { [ "$(incus list "^$1\$" -c s -f csv 2>/dev/null)" = RUNNING ]; }

out='{}'
for n in $(jq -r 'keys[]' "$cfg"); do
  m=$(jq -r --arg n "$n" '.[$n].mount' "$cfg")
  mode=$(jq -r --arg n "$n" '.[$n].whenDown' "$cfg")
  # A share that stopped answering hangs whatever touches it; KILL is what
  # reaches a process waiting on NFS.
  up=false
  timeout -s KILL 10 stat -f "$m" >/dev/null 2>&1 && timeout -s KILL 10 ls "$m" >/dev/null 2>&1 && up=true
  # A data folder placed on the share whose bind failed while the share was
  # gone (it is nofail) is bound again once the share answers.
  if [ "$up" = true ]; then
    for b in $(jq -r --arg n "$n" '.[$n].binds[]' "$cfg"); do
      mountpoint -q "$b" || { systemctl start "$(systemd-escape -p --suffix=mount "$b")" && echo "bound $b again"; }
    done
  fi
  for g in $(jq -r --arg n "$n" '.[$n].guests[]' "$cfg"); do
    if [ "$up" = false ] && [ "$mode" = hold ] && ! grep -qx "$g" "$held" && running "$g"; then
      incus stop --force "$g" && echo "$g" >>"$held" && echo "stopped $g: NAS share $n is unreachable"
    elif [ "$up" = true ] && grep -qx "$g" "$held"; then
      incus start "$g" && echo "started $g: NAS share $n is back"
      grep -vx "$g" "$held" >"$held.new"
      mv "$held.new" "$held"
    fi
  done
  out=$(jq --arg n "$n" --argjson up "$up" --arg mode "$mode" --arg m "$m" \
    --argjson guests "$(jq --arg n "$n" '.[$n].guests' "$cfg")" \
    --argjson stopped "$(jq -Rn '[inputs | select(. != "")]' <"$held")" \
    '. + {($n): {up: $up, whenDown: $mode, mount: $m, guests: $guests, held: ($guests - ($guests - $stopped))}}' <<<"$out")
done
jq --arg at "$(date -Is)" '{checked: $at, shares: .}' <<<"$out" >/run/nixie/nas.json.tmp && mv /run/nixie/nas.json.tmp /run/nixie/nas.json
chmod 644 /run/nixie/nas.json
