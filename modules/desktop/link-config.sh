# shellcheck shell=bash
# Links each user's configuration at the finish they chose; run at login.
mkdir -p "$HOME/.config/hypr" "$HOME/.config/nixie" "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
rm -f "$HOME/.config/hypr/hyprland.conf"
ln -sfn /etc/xdg/hypr/hyprland.lua "$HOME/.config/hypr/hyprland.lua"
ln -sfn /etc/xdg/hypr/hypridle.conf "$HOME/.config/hypr/hypridle.conf"
[ -e "$HOME/.config/hypr/local.lua" ] || printf -- '-- Your tweaks, loaded last; no rebuild needed. Example:\n-- hl.config({ general = { gaps_out = 24 } })\n' >"$HOME/.config/hypr/local.lua"
[ -e "$HOME/.config/nixie/local.conf" ] || printf '# kitty tweaks, included last\n' >"$HOME/.config/nixie/local.conf"
[ -s "$HOME/.config/nixie/finish" ] || printf '%s' "@finish@" >"$HOME/.config/nixie/finish"
f=$(cat "$HOME/.config/nixie/finish"); [ -d "/etc/nixie/desktop/$f" ] || f=@finish@
ln -sfn "/etc/nixie/desktop/$f/kitty.conf" "$HOME/.config/nixie/kitty.conf"
ln -sfn "/etc/nixie/desktop/$f/hyprlock.conf" "$HOME/.config/hypr/hyprlock.conf"
ln -sfn "/etc/nixie/desktop/$f/gtk.css" "$HOME/.config/gtk-3.0/gtk.css"
ln -sfn "/etc/nixie/desktop/$f/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"
