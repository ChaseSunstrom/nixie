start_all()
mirror.wait_for_unit("nginx.service")
host.wait_for_unit("multi-user.target")
host.wait_until_succeeds("ip addr show nixie-br | grep -q 192.168.1.1")

with subtest("fetch fills the cache and is idempotent"):
    host.succeed("nixie fetch >&2")
    host.succeed("test -e /data/cache/http/dataset/.complete && grep -q 'the dataset' /data/cache/http/dataset/dataset.txt")
    assert "complete" in host.succeed("nixie fetch")

with subtest("deleting cache/ and fetching restores it"):
    host.succeed("find /data/cache -mindepth 1 -delete")
    host.succeed("nixie fetch >&2")
    host.succeed("grep -q 'the dataset' /data/cache/http/dataset/dataset.txt")

with subtest("backup of state/ and restore of a deleted file"):
    host.succeed("mkdir -p /data/state/web && echo precious > /data/state/web/index.html")
    host.succeed("systemctl start restic-backups-nixie.service")
    # grep reads everything: -q would close the pipe on restic (SIGPIPE, 141).
    host.succeed("restic-nixie snapshots | grep /data/state >/dev/null")
    host.succeed("unlink /data/state/web/index.html")
    host.succeed("nixie restore latest >&2")
    host.succeed("grep -q precious /data/state/web/index.html")
    # cache/ is never in a backup.
    host.fail("restic-nixie ls latest | grep -q /data/cache/")
