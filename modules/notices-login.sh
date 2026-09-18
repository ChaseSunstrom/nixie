# shellcheck shell=sh
# What this machine wants you to know, on an interactive login: a newer site
# waiting, an apply to confirm, a backup check that failed. The file is
# written by nixie-notices.service (modules/updates.nix).
if [ -s /run/nixie/notices.json ]; then
  @jq@ -r '.notices[] | "  \(.title): \(.detail) -- \(.action)"' /run/nixie/notices.json 2>/dev/null
fi
