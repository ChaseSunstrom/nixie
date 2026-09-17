# shellcheck shell=bash
site=${NIXIE_SITE:-@sitePath@}
f="$site/site.nix"
setopt() { # key value: replace or add a `nixie.<key> = ...;` line inside this host's settings
  if grep -qE "^\s*$1 = " "$f"; then sed -i -E "s|^(\s*)$1 = .*;|\1$1 = $2;|" "$f"
  else sed -i -E "0,/settings = \{/s|(settings = \{)|\1\n      $1 = $2;|" "$f"; fi
}
applyChanges() {
  git -C "$site" --no-pager diff --color=always || true
  if gum confirm "Apply this to the running system?"; then
    git -C "$site" add -A && git -C "$site" commit -qm "nixie menu: $1" || true
    sudo nixie apply --yes
  else git -C "$site" checkout -- . ; fi
}
while true; do
  c=$(gum choose --header "nixie menu" "Finish" "Wallpaper" "Packages" "Update" "Keybinds" "System info" "Quit")
  case "$c" in
    Finish) fin=$(gum choose --header "Default finish in the site (now: @finish@); Super+T switches for this session only" graphite umber paper); setopt nixie.desktop.finish "\"$fin\""; applyChanges "finish $fin" ;;
    Wallpaper) w=$(gum file "$HOME" --file); setopt nixie.desktop.wallpaper "$w"; applyChanges "wallpaper" ;;
    Packages) cat=$(gum choose browsers terminals editors media office communication gaming creative); cur=$(grep -oE "nixie.desktop.packages.categories.$cat = \[[^]]*\]" "$f" | sed -E 's/.*\[(.*)\]/\1/' || true)
      gum style "current: ${cur:-(defaults)}"; new=$(gum input --placeholder "package names, space separated" --value "$cur")
      setopt "nixie.desktop.packages.categories.$cat" "[ $(for p in $new; do printf '"%s" ' "$p"; done)]"; applyChanges "packages $cat" ;;
    Update) (cd "$site" && nix flake update) && applyChanges "update inputs" ;;
    Keybinds) gum pager </etc/nixie/desktop/keys.txt ;;
    "System info") { hostnamectl; echo; nixie doctor || true; } | gum pager ;;
    Quit) exit 0 ;;
  esac
done
