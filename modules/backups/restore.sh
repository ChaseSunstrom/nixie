# shellcheck shell=bash
snap=latest; target=/; args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --path) args+=(--include "$2"); shift 2 ;;
    --to) target=$2; shift 2 ;;
    --*) args+=("$1"); shift ;;
    *) snap=$1; shift ;;
  esac
done
mkdir -p "$target"
exec restic-nixie restore "$snap" --target "$target" "${args[@]}"
