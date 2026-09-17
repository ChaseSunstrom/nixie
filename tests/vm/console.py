panel.start()
panel.wait_for_unit("nixie-panel.service")
panel.wait_for_unit("incus-preseed.service")
# A lane to show: "instances" alone also matched "no instances", which
# the panel printed while it asked a socket path that does not exist.
panel.succeed("incus create --empty probe")
# The wordmark is drawn in block glyphs OCR cannot read; the lane and the
# pool line are plain text, so they stand in for the page. The panel
# redraws every few seconds, so a single read can land on a blank screen.
panel.wait_for_text("probe", timeout=180)
panel.wait_for_text("pool", timeout=60)
panel.screenshot("front-panel")
panel.send_key("ret")
panel.wait_for_text("login", timeout=60)
panel.screenshot("front-panel-login")
# The splash the initrd shows, started again on this display: the same
# theme, asking for a passphrase. The test VM's serial console would put
# Plymouth in text mode, as it does in test-iso, hence the flag.
panel.succeed("systemctl stop nixie-panel.service")
panel.succeed("plymouthd --mode=boot --tty=/dev/tty1 --ignore-serial-consoles && plymouth show-splash")
panel.succeed("(plymouth ask-for-password --prompt='Disk passphrase' </dev/null >/dev/null 2>&1 &)")
# What the unlock agent puts under it (modules/security/unlock.nix).
panel.succeed("plymouth display-message --text='Attestation code 314159'")
panel.sleep(8)
panel.succeed("plymouth --ping")
panel.screenshot("boot-splash")
panel.execute("plymouth quit")
panel.shutdown()

kiosk.start()
kiosk.wait_for_unit("nixie-kiosk-gate.service")
kiosk.wait_for_unit("cage-tty1.service")
kiosk.wait_for_text("(Administrator|Unlock)", timeout=300)
kiosk.screenshot("kiosk-lock")
kiosk.succeed("curl -s -o /dev/null -w '%{http_code}' -d 'password=nixie' http://127.0.0.1:9444/unlock | grep -q 302")
kiosk.succeed("curl -s -o /dev/null -w '%{http_code}' -d 'password=wrong' http://127.0.0.1:9444/unlock | grep -q 303")
kiosk.wait_for_text("(nixie|Overview|Instances)", timeout=120)
kiosk.screenshot("kiosk-panel")
kiosk.succeed("systemctl is-active nixie-panel.service && systemctl show -p TTYPath nixie-panel.service | grep -q tty2")
