import json

start_all()
nas.wait_for_unit("nfs-server.service")
host.wait_for_unit("multi-user.target")

with subtest("cache/ lives on the share, read through a local cache"):
    host.succeed("echo hello > /data/cache/hello")
    nas.succeed("grep -q hello /export/cache/hello")
    host.succeed("grep ' /nas/tank ' /proc/mounts | grep -q fsc")
    host.succeed("systemctl is-active cachefilesd.service")

with subtest("dated copies share unchanged files and keep the newest"):
    host.succeed("mkdir -p /data/state && echo precious > /data/state/f")
    for _ in range(3):
        host.succeed("systemctl start nixie-copy-state.service")
        host.sleep(1)
    copies = nas.succeed("ls -1 /export/copies/state").split()
    assert len(copies) == 2, copies
    inodes = {nas.succeed(f"stat -c %i /export/copies/state/{c}/f").strip() for c in copies}
    assert len(inodes) == 1, f"the copies do not share the unchanged file: {inodes}"

with subtest("backups go to the share"):
    host.succeed("systemctl start restic-backups-nixie.service")
    nas.succeed("test -e /export/restic/config")

with subtest("the share goes away: reported, and the guest that needs it is named"):
    nas.succeed("ip link set eth1 down")
    host.succeed("systemctl start nixie-nas-watch.service")
    st = json.loads(host.succeed("cat /run/nixie/nas.json"))
    assert st["shares"]["tank"]["up"] is False, st
    assert st["shares"]["tank"]["guests"] == ["app"], st
    host.succeed("nixie notices --write >/dev/null; grep -q 'The NAS share tank is unreachable' /run/nixie/notices.json")
    print(host.succeed("nixie nas status"))

with subtest("the machine still starts with the NAS down"):
    host.shutdown()
    host.start()
    host.wait_for_unit("multi-user.target", timeout=300)
    host.succeed("systemctl start nixie-nas-watch.service")
    assert json.loads(host.succeed("cat /run/nixie/nas.json"))["shares"]["tank"]["up"] is False

with subtest("the share comes back"):
    nas.succeed("ip link set eth1 up")
    host.wait_until_succeeds("systemctl start nixie-nas-watch.service && grep -q '\"up\": true' /run/nixie/nas.json", timeout=120)
    host.succeed("grep -q hello /data/cache/hello")
