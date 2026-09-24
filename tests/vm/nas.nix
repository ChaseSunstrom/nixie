# A NAS as first-class storage (ARCHITECTURE 4.13): an NFS server, and a host
# with cache/ on it (read-cached locally), dated copies of state/ and the
# backup repository there, and a guest that needs it held while it is gone.
# Addresses are the driver's: host 192.168.1.1, nas 192.168.1.2.
{
  pkgs,
  nixieLib,
  exampleSite,
}:
pkgs.testers.runNixOSTest {
  name = "vm-nas";
  nodes = {
    nas = {
      virtualisation.vlans = [ 1 ];
      services.nfs.server = {
        enable = true;
        exports = "/export 192.168.1.0/24(rw,no_root_squash,no_subtree_check)";
      };
      systemd.tmpfiles.rules = [ "d /export 0755 root root -" ];
      networking.firewall.allowedTCPPorts = [ 2049 ];
    };
    host =
      { lib, ... }:
      {
        imports = nixieLib.hostModules ../../examples/site "server" exampleSite.hosts.server ++ [
          ./qemu.nix
        ];
        virtualisation.vlans = [ 1 ];
        virtualisation.sharedDirectories.nixie-site = {
          source = "${lib.cleanSource ../../examples/site}";
          target = "/etc/nixie/site";
        };
        nixie.network = {
          bridge.uplinks = lib.mkForce [ "52:54:00:12:01:01" ];
          address = "192.168.1.1/24";
        };
        nixie.nas.tank = {
          server = "192.168.1.2";
          export = "/export";
          cache = true;
          whenDown = "hold";
        };
        nixie.data.cache.on = "tank";
        nixie.data.copies.state = {
          from = "state";
          to = "tank:copies/state";
          keep = 2;
        };
        nixie.guests.app.mounts."/data/cache/models" = "/models";
        nixie.backups = {
          enable = true;
          repository = "nas:tank/restic";
          # A test password; a site's comes from its secrets.
          passwordFile = lib.mkForce "${pkgs.writeText "restic-password" "test"}";
        };
      };
  };

  testScript = builtins.readFile ./nas.py;
}
