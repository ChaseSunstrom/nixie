import re
broken = "@broken_config_system_build_toplevel@"

host.wait_for_unit("multi-user.target")
host.succeed("zpool create -f -O mountpoint=none tpool /dev/vdb && zfs create -o mountpoint=/data tpool/data && zfs create -o mountpoint=/data/state tpool/data/state")
# Test VMs have no system profile; seed it with the running system as generation 1.
host.succeed("nix-env --profile /nix/var/nix/profiles/system --set \"$(readlink -f /run/current-system)\"")
host.wait_for_unit("incus.service")
host.wait_until_succeeds("incus storage list -f csv | grep -q default")

with subtest("a broken new generation is undone from the front panel"):
    host.wait_until_succeeds("curl -sk -o /dev/null https://127.0.0.1:8443/ui/", timeout=120)
    host.succeed(f"nix-env --profile /nix/var/nix/profiles/system --set {broken} && {broken}/bin/switch-to-configuration switch >&2")
    host.wait_until_succeeds("curl -sk -o /dev/null https://127.0.0.1:8444/ui/", timeout=120)
    host.fail("curl -sk -o /dev/null --max-time 3 https://127.0.0.1:8443/ui/")
    listing = host.succeed("nixie rollback --list")
    print(listing)
    assert re.search(r"^2 .*current", listing, re.M) and re.search(r"^1 ", listing, re.M), listing
    # First from the shell, where errors are visible; then the same through the panel key.
    host.succeed("nixie rollback >&2")
    host.wait_until_succeeds("test \"$(readlink -f /run/current-system)\" = \"$(readlink -f /nix/var/nix/profiles/system-1-link)\"", timeout=180)
    host.wait_until_succeeds("curl -sk -o /dev/null https://127.0.0.1:8443/ui/", timeout=120)
    host.succeed(f"nix-env --profile /nix/var/nix/profiles/system --set {broken} && {broken}/bin/switch-to-configuration switch >&2")
    host.wait_until_succeeds("curl -sk -o /dev/null https://127.0.0.1:8444/ui/", timeout=120)
    host.wait_for_unit("nixie-panel.service")
    host.wait_for_text("(instances|log in)", timeout=180)
    host.send_key("r")
    host.wait_until_succeeds("test \"$(readlink -f /run/current-system)\" = \"$(readlink -f /nix/var/nix/profiles/system-1-link)\"", timeout=180)
    host.wait_until_succeeds("curl -sk -o /dev/null https://127.0.0.1:8443/ui/", timeout=120)

with subtest("an apply that is not confirmed in time reverts host and guests"):
    host.succeed("mkdir -p /data/state/web && echo hello-from-web > /data/state/web/index.html")
    host.succeed("nixie apply --yes --skip-host >&2")
    host.wait_until_succeeds("incus list web -c s -f csv | grep -q RUNNING")
    host.succeed("incus exec web -- sh -c 'echo before > /var/lib/marker'")
    # The host part is a prebuilt broken system; the guest part changes web's config so it is snapshotted.
    host.succeed("incus config set web user.drift=1")
    host.succeed(f"NIXIE_TOPLEVEL={broken} nixie apply --yes --confirm-within 20s >&2")
    host.wait_until_succeeds("curl -sk -o /dev/null https://127.0.0.1:8444/ui/", timeout=120)
    host.succeed("test -e /run/nixie/apply-pending.json")
    host.wait_until_succeeds("test \"$(readlink -f /run/current-system)\" = \"$(readlink -f /nix/var/nix/profiles/system-1-link)\"", timeout=180)
    host.succeed("test ! -e /run/nixie/apply-pending.json")
    host.wait_until_succeeds("curl -sk -o /dev/null https://127.0.0.1:8443/ui/", timeout=120)
    # A confirmed apply keeps its generation.
    host.succeed(f"NIXIE_TOPLEVEL={broken} nixie apply --yes --skip-host --confirm-within 20s >&2 && nixie apply --confirm >&2")
    host.succeed("sleep 25; test ! -e /run/nixie/apply-pending.json")

with subtest("a guest snapshot restore leaves /data/state untouched"):
    host.wait_until_succeeds("incus list web -c s -f csv | grep -q RUNNING")
    host.succeed("incus snapshot create web s1")
    host.succeed("incus exec web -- sh -c 'echo after > /var/lib/marker'")
    host.succeed("echo changed-state > /data/state/web/index.html")
    host.succeed("nixie rollback guest web --snapshot s1 >&2")
    host.wait_until_succeeds("incus list web -c s -f csv | grep -q RUNNING")
    # Never pipe `incus exec` into `grep -q`: the early exit leaves the
    # client hanging on its websocket. Read the file once and compare.
    host.sleep(5)
    marker = host.succeed("incus exec web -- cat /var/lib/marker").strip()
    assert marker == "before", marker
    host.succeed("grep -q changed-state /data/state/web/index.html")

with subtest("a data snapshot restores beside and in place"):
    host.succeed("nixie-snapshot pre-apply d1")
    host.succeed("echo newer > /data/state/web/index.html")
    out = host.succeed("nixie rollback data web --snapshot pre-apply-d1")
    print(out)
    host.succeed("grep -q changed-state /data/state/web.restored-*/index.html")
    host.succeed("grep -q newer /data/state/web/index.html")
    host.succeed("nixie rollback data web --snapshot pre-apply-d1 --in-place --yes >&2")
    host.succeed("grep -q changed-state /data/state/web/index.html")
