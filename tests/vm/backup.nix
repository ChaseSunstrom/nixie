# Local history and backups: state/ on a ZFS dataset gets pre-apply snapshots
# (kept: five) and is marked for zfs-auto-snapshot; restic backs it up on
# demand, restores in place and beside, verifies the repository, and the
# disaster kit decrypts to the pieces a rebuild needs.
{
  pkgs,
  nixieLib,
  exampleSite,
  nixieCli,
}:
let
  inherit (pkgs) lib;
in
pkgs.testers.runNixOSTest {
  name = "vm-backup";
  nodes.host = {
    imports = nixieLib.hostModules ../../examples/site "server" exampleSite.hosts.server ++ [
      ./qemu.nix
    ];
    virtualisation.sharedDirectories.nixie-site = {
      source = "${lib.cleanSource ../../examples/site}";
      target = "/etc/nixie/site";
    };
    # A second disk becomes the ZFS pool that carries the data root.
    virtualisation.emptyDiskImages = [ 1024 ];
    boot.supportedFilesystems.zfs = true;
    networking.hostId = "8425e349";
    nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:01" ];
    nixie.network.address = "192.168.1.1/24";
    nixie.backups = {
      enable = true;
      repository = "/var/backup";
      passwordFile = "/etc/nixie-test/restic-password";
    };
    environment.etc."nixie-test/restic-password".text = "test";
    environment.systemPackages = [
      nixieCli
      pkgs.age
      pkgs.jq
    ];
  };

  testScript = ''
    host.wait_for_unit("multi-user.target")
    host.succeed("zpool create -f -O mountpoint=none tpool /dev/vdb && zfs create -o mountpoint=/data tpool/data && zfs create -o mountpoint=/data/state tpool/data/state")
    host.succeed("mkdir -p /data/state/web && echo precious > /data/state/web/index.html")
    # An installed host carries its age key from phase 2; this node was not.
    host.succeed("mkdir -p /var/lib/nixie && age-keygen -o /var/lib/nixie/age.key 2>/dev/null")

    with subtest("pre-apply snapshots are taken and pruned to five; the dataset is marked for auto-snapshot"):
        for i in range(6):
            host.succeed(f"nixie-snapshot pre-apply t{i}")
        snaps = host.succeed("zfs list -H -t snapshot -o name tpool/data/state")
        assert snaps.count("@pre-apply-") == 5 and "t0" not in snaps and "t5" in snaps, snaps
        host.succeed("zfs get -H -o value com.sun:auto-snapshot tpool/data/state | grep -qx true")
        host.succeed("systemctl list-timers --all | grep -q zfs-snapshot-hourly")

    with subtest("backup now, list, restore in place and beside, verify"):
        host.succeed("nixie backup now >&2")
        assert int(host.succeed("nixie backup list --json | jq length").strip()) >= 1
        host.succeed("unlink /data/state/web/index.html")
        host.succeed("nixie restore latest --path /data/state/web/index.html >&2")
        host.succeed("grep -q precious /data/state/web/index.html")
        host.succeed("nixie restore latest --to /root/beside >&2")
        host.succeed("grep -q precious /root/beside/data/state/web/index.html")
        host.succeed("nixie backup verify >&2")
        host.succeed("jq -e .ok /var/lib/nixie/backup-check.json")
        doc = host.succeed("nixie doctor || true")
        assert "backup check" in doc and "ok" in doc, doc

    with subtest("the disaster kit holds the host key, the restic secret and the rebuild steps"):
        host.succeed("age-keygen -o /root/kit.key 2>/dev/null; age-keygen -y /root/kit.key > /root/kit.pub")
        host.succeed("nixie backup kit /root/kit.tar.age --recipient $(cat /root/kit.pub) >&2")
        listing = host.succeed("age -d -i /root/kit.key /root/kit.tar.age | tar -tf -")
        for name in ("age.key", "restic-password", "README.txt", "recovery-key.txt"):
            assert name in listing, listing
        host.succeed("age -d -i /root/kit.key /root/kit.tar.age | tar -xOf - ./README.txt | grep -q 'Rebuild from nothing'")
  '';
}
