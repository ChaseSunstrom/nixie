# shellcheck shell=bash
# Each notice as a desktop notification, once: what was shown last time is
# remembered, so a notice that is still waiting does not pop up every
# quarter of an hour.
set -u
state=${XDG_RUNTIME_DIR:-/tmp}/nixie-notified
[ -s /run/nixie/notices.json ] || exit 0
seen=$(cat "$state" 2>/dev/null || true)
now=""
while IFS=$'\t' read -r id level title detail action; do
  [ -n "$id" ] || continue
  now="$now $id"
  case " $seen " in *" $id "*) continue ;; esac
  urgency=normal; [ "$level" = warn ] && urgency=critical
  @notifySend@ -a nixie -u "$urgency" "$title" "$detail
$action"
done < <(@jq@ -r '.notices[] | [.id, .level, .title, .detail, .action] | @tsv' /run/nixie/notices.json)
printf '%s\n' "${now# }" >"$state"
