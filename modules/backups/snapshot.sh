# shellcheck shell=bash
root=@root@
datasets() {
  for p in "$root/state" $(jq -r '.declared[].backup[]?' /run/current-system/etc/nixie/guests.json 2>/dev/null); do
    zfs list -H -o name "$p" 2>/dev/null || true
  done | sort -u
}
case "${1:-}" in
  pre-apply)
    label=${2:?label}
    for ds in $(datasets); do
      zfs set com.sun:auto-snapshot=true "$ds"
      zfs snapshot -r "$ds@pre-apply-$label"
      zfs list -H -t snapshot -o name -s creation "$ds" | grep "@pre-apply-" | head -n -5 | xargs -r -n1 zfs destroy -r
    done ;;
  list) for ds in $(datasets); do zfs list -H -t snapshot -o name,creation -s creation "$ds"; done ;;
  *) echo "usage: nixie-snapshot pre-apply <label> | list" >&2; exit 2 ;;
esac
