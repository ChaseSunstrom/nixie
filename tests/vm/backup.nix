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

  testScript = builtins.readFile ./backup.py;
}
