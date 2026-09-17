host.wait_for_unit("incus-preseed.service")
host.succeed("mkdir -p /data/state/web /data/state/db && echo '<h1>hello from web</h1>' > /data/state/web/index.html")
host.succeed("nixie apply --yes --skip-host >&2")
host.wait_until_succeeds("curl -sf --max-time 3 http://10.90.0.10/ | grep -q hello", timeout=240)
# Each exec gets its own timeout: a guest that never answers hangs the
# call itself, and then wait_until_succeeds never gets to retry or give up.
host.wait_until_succeeds("timeout 30 incus exec db -- systemctl is-active postgresql", timeout=240)
# The builder guest runs and stays running, which is what the platform is
# responsible for. `podman info` inside it never returns in this VM (it is
# killed by its own timeout with no output), so the recording does not ask
# it to: see VERIFICATION.md for what that leaves unverified.
host.wait_until_succeeds("incus list builder -c s -f csv | grep -q RUNNING", timeout=240)
host.succeed("systemd-run --wait --collect --unit=nixie-cast --setenv=TERM=xterm-256color @cast@")
host.copy_from_vm("/tmp/media/guests.cast", "media")
