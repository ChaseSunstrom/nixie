# shellcheck shell=bash
url=@url@
# The display comes up before the page's service can answer (the setup
# service waits for the network), and a browser that starts first shows
# a connection error, or the pairing form without the local token, whose
# code is on the console this kiosk covers. Neither is retried, so wait.
for _ in $(seq 300); do curl -sk --max-time 2 -o /dev/null "$url" && break; sleep 1; done
@token@
# The certificate is the setup service's own, made on this machine.
# --kiosk alone never goes full screen under cage on Wayland and leaves
# the tab strip and address bar; --app opens a window without them.
exec chromium --app="$url" --kiosk --start-fullscreen --no-first-run --disable-translate --noerrdialogs \
  --disable-infobars --password-store=basic --ozone-platform=wayland \
  --ignore-certificate-errors --user-data-dir=/var/lib/nixie-kiosk/chromium
