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
kiosk.wait_for_unit("incus-preseed.service")
kiosk.wait_for_text("(Unlock|authenticator)", timeout=300)
kiosk.screenshot("kiosk-lock")

with subtest("the lock refuses, and passes nothing of the daemon's, while locked"):
    kiosk.succeed("curl -s -H 'Accept: application/json' -d password=nixie http://127.0.0.1:9444/__nixie/unlock | grep -q 'authenticator app is needed'")
    kiosk.succeed("curl -s -H 'Accept: application/json' -d password=wrong -d code=000000 http://127.0.0.1:9444/__nixie/unlock | grep -q 'not right'")
    kiosk.succeed("curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9444/1.0 | grep -q 403")
    # The old lock read a secret file nobody wrote, dropped the connection,
    # and the kiosk was left on a browser error page with no way back.
    kiosk.succeed("curl -s -o /dev/null -w '%{http_code}' -d password=nixie -d code=000000 http://127.0.0.1:9444/__nixie/unlock | grep -q 303")
    kiosk.succeed("systemctl is-active nixie-kiosk-gate.service")

with subtest("a person at the screen unlocks it and gets the trusted panel"):
    # The password field has the focus; the code comes from the app.
    kiosk.send_chars("nixie")
    kiosk.send_key("tab")
    code = kiosk.succeed("oathtool --totp -b @totp@").strip()
    kiosk.send_chars(code + "\n")
    # "Overview" is the panel's own navigation: neither the lock page nor
    # the page a browser without a certificate gets has the word.
    kiosk.wait_for_text("Overview", timeout=240)
    kiosk.screenshot("kiosk-panel")

with subtest("left alone, it locks itself again"):
    kiosk.wait_for_text("Unlock the control panel", timeout=400)
    kiosk.screenshot("kiosk-relocked")

kiosk.succeed("systemctl is-active nixie-panel.service && systemctl show -p TTYPath nixie-panel.service | grep -q tty2")
