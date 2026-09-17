# Deleting cache/ and running fetch restores it from the manifest (http kind
# against a mirror VM); a restic backup of state/ and `nixie restore` bring a
# deleted file back.
{
  pkgs,
  nixieLib,
  exampleSite,
  nixieCli,
}:
let
  inherit (pkgs) lib;
  dataset = pkgs.writeText "dataset.txt" "the dataset\n";
in
pkgs.testers.runNixOSTest {
  name = "vm-data";
  nodes = {
    # Node numbers are alphabetical: host = 1, mirror = 2.
    mirror = {
      services.nginx = {
        enable = true;
        virtualHosts.default.root = pkgs.runCommand "root" { } "mkdir $out; cp ${dataset} $out/dataset.txt";
      };
      networking.firewall.allowedTCPPorts = [ 80 ];
    };
    host = {
      imports = nixieLib.hostModules ../../examples/site "server" exampleSite.hosts.server ++ [
        ./qemu.nix
      ];
      virtualisation.sharedDirectories.nixie-site = {
        source = "${lib.cleanSource ../../examples/site}";
        target = "/etc/nixie/site";
      };
      nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:01" ];
      nixie.network.address = "192.168.1.1/24";
      nixie.data.manifest = lib.mkForce {
        http.dataset = {
          url = "http://192.168.1.2/dataset.txt";
          sha256 = builtins.hashFile "sha256" dataset;
        };
      };
      nixie.backups = {
        enable = true;
        repository = "/var/backup";
        passwordFile = "/etc/nixie-test/restic-password";
      };
      environment.etc."nixie-test/restic-password".text = "test";
      environment.systemPackages = [ nixieCli ];
    };
  };

  testScript = builtins.readFile ./data.py;
}
