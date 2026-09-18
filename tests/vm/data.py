image = "@image@"

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

with subtest("the images a site keeps are served from the machine itself"):
    host.wait_for_unit("docker-registry.service")
    host.wait_for_open_port(5000)
    # cache/ was cleared above, which took the registry's storage with it:
    # `nixie fetch` puts it back, because clearing cache/ is meant to be
    # safe and the registry cannot make that directory for itself.
    host.succeed("test -d /data/cache/registry")
    # The same push the `oci` fetcher makes once it has pulled an image.
    # --policy as the fetcher passes it: a Nixie host has no /etc/containers,
    # and skopeo copies nothing without a trust policy.
    host.succeed(
        "printf '%s' '{\"default\":[{\"type\":\"insecureAcceptAnything\"}]}' >/tmp/policy.json"
    )
    host.succeed(f"skopeo --policy /tmp/policy.json copy --dest-tls-verify=false docker-archive:{image} docker://127.0.0.1:5000/hello:latest >&2")
    tags = host.succeed("curl -sf http://127.0.0.1:5000/v2/hello/tags/list")
    print(tags)
    assert '"latest"' in tags, tags
    # It can be pulled back, which is what a guest does.
    host.succeed("skopeo --policy /tmp/policy.json inspect --tls-verify=false docker://127.0.0.1:5000/hello:latest >&2")
    # And what it holds is under cache/: re-fetchable, and never backed up.
    host.succeed("test -d /data/cache/registry/docker")
    host.succeed("systemctl start restic-backups-nixie.service")
    host.fail("restic-nixie ls latest | grep -q /data/cache/")
