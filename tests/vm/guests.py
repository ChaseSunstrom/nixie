host.wait_for_unit("incus.service")
host.wait_for_unit("incus-preseed.service")
host.wait_until_succeeds("incus storage list -f csv | grep -q default")

with subtest("apply creates the declared guest and it serves"):
    host.succeed("mkdir -p /data/state/web && echo hello-from-web > /data/state/web/index.html")
    host.succeed("nixie apply --yes --skip-host >&2")
    host.wait_until_succeeds("incus list web -c s -f csv | grep -q RUNNING")
    print(host.succeed("ip -br addr; incus list; incus exec web -- ip -br addr || true; incus exec web -- systemctl --failed --no-pager || true"))
    host.wait_until_succeeds("curl -sf --max-time 3 http://10.90.0.10/ | grep -q hello-from-web", timeout=120)
    host.succeed("ip link show veth-web")
    host.succeed("nft list chain bridge nixie-guests guest-web")
    # The control panel and the guest dashboard read these names; both
    # once asked for ones incusd does not export and showed 0 silently.
    metrics = host.succeed("curl -s --unix-socket /var/lib/incus/unix.socket http://incus/1.0/metrics")
    for name in ["incus_cpu_seconds_total", "incus_memory_MemTotal_bytes", "incus_memory_MemAvailable_bytes"]:
        assert f'{name}{{' in metrics and 'name="web"' in metrics, name
    print(host.succeed("nixie doctor || true"))

with subtest("a scratch instance is left alone by apply"):
    alias = host.succeed("cat /etc/nixie-test-alias").strip()
    host.succeed(f"incus launch {alias} scratch")
    host.succeed("nixie apply --yes --skip-host >&2")
    host.succeed("incus list scratch -c s -f csv | grep -q RUNNING")

with subtest("a deleted guest is recreated; state survives"):
    host.succeed("incus delete -f web")
    host.succeed("nixie apply --yes --skip-host >&2")
    host.wait_until_succeeds("curl -sf --max-time 3 http://10.90.0.10/ | grep -q hello-from-web", timeout=180)

with subtest("an apply that changes a guest snapshots it first"):
    # A config drift on the instance makes the next plan replace it; the
    # pre-apply snapshot is taken before tofu acts (Incus keeps it with the
    # instance for a replace-in-place, and it is listed here either way).
    host.succeed("incus config set web user.drift=1")
    host.succeed("nixie apply --yes --skip-host >&2")
    print(host.succeed("incus snapshot list web -f csv -c n || true"))
    host.succeed("incus snapshot list web -f csv -c n | grep -q '^pre-apply-' || incus info web | grep -q pre-apply-")

with subtest("export emits a guests.nix entry"):
    out = host.succeed("nixie export scratch")
    print(out)
    assert "scratch = {" in out and 'kind = "nixos"' in out, out

with subtest("declare writes that entry into the site"):
    # A writable copy: the site is mounted from the store here.
    host.succeed("cp -r /etc/nixie/site /tmp/site && chmod -R u+w /tmp/site")
    # --skip-host reaches the apply that declare ends with, because
    # rebuilding a NixOS inside this machine is the subject of no test.
    host.succeed("NIXIE_SITE=/tmp/site nixie declare scratch --skip-host >&2")
    out = host.succeed("cat /tmp/site/guests.nix")
    print(out[-400:])
    assert "scratch = {" in out, out
    # Still an attrset, and still one nix can read.
    host.succeed("nix-instantiate --eval -E 'builtins.attrNames (import /tmp/site/guests.nix)' | grep -q scratch")
    host.succeed("incus list scratch -c s -f csv | grep -q RUNNING")
    # A name the site already carries, and a name no instance has.
    host.fail("NIXIE_SITE=/tmp/site nixie declare web --skip-host")
    host.fail("NIXIE_SITE=/tmp/site nixie declare nosuchthing --skip-host")

with subtest("an instance the state has never seen is adopted, not made again"):
    # What a declare leaves behind once the host has rebuilt with it: a guest
    # the site declares that is already running. Incus gives each instance a
    # uuid of its own, so it tells this one from a replacement -- and unlike
    # a config key set by hand it is not drift for the next apply to undo.
    uuid = host.succeed("incus config get web volatile.uuid").strip()
    assert uuid, "the instance has no uuid to recognise it by"
    host.succeed("cd /var/lib/nixie/tofu && tofu state rm incus_instance.web >&2")
    host.succeed("nixie apply --yes --skip-host >&2")
    host.succeed("cd /var/lib/nixie/tofu && tofu state list | grep -qx incus_instance.web")
    assert host.succeed("incus config get web volatile.uuid").strip() == uuid, "it was replaced, not adopted"
    # And the plan that follows the adoption changes nothing, which is the
    # whole point: an import alone leaves the image unset, and the next plan
    # replaces the instance it has just taken over.
    print(host.succeed("cd /var/lib/nixie/tofu && tofu plan -input=false -no-color 2>&1 || true"))
    host.succeed("cd /var/lib/nixie/tofu && tofu plan -input=false -detailed-exitcode >&2")
