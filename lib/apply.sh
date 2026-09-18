# shellcheck shell=bash
# `nix run .#apply` from a site checkout: the thin wrapper the brief asks for.
# It puts this checkout on a machine of the site and runs `nixie apply` there,
# which is the same command the machine runs for itself. With no machine named
# it is this one.
#
# The site's own .git is left alone: the host's checkout has commits of its
# own (its hardware.nix, what setup wrote), and `nixie apply` commits what
# arrives here as a hand edit and pushes it like any other change.
site=${NIXIE_SITE_DIR:-$PWD}
[ -e "$site/site.nix" ] || { echo "nix run .#apply: run it from a site checkout (no site.nix in $site)" >&2; exit 2; }
target=""
if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then
  target=$1
  shift
fi
if [ -z "$target" ]; then
  exec sudo nixie apply "$@"
fi
echo "nixie: copying $site to $target and applying it there"
rsync -a --delete --exclude .git --rsync-path="sudo rsync" "$site/" "$target:@sitePath@/"
# shellcheck disable=SC2029  # the arguments are meant to expand here
exec ssh -t "$target" sudo nixie apply "$@"
