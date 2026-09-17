# Media: the example guests answering, as a terminal recording.
{
  pkgs,
  nixieLib,
  exampleSite,
  nixieCli,
}:
let
  template = import ../../lib/template.nix pkgs.lib;
  inherit (pkgs) lib;
  # asciinema drives a terminal of its own and writes to /dev/tty, which
  # corrupts the frames the test driver reads over the same shell. Run as a
  # transient unit it has no terminal to interfere with, and keeping the
  # script in the store keeps its quoting out of the driver's way.
  cast = pkgs.writeShellScript "guests-cast" ''
    set -eu
    mkdir -p /tmp/media
    exec asciinema rec --overwrite -c 'bash -c "incus list; sleep 1; curl -s http://10.90.0.10/; sleep 1; timeout 30 incus exec db -- sudo -u postgres psql -c \"select version()\"; sleep 2; nixie doctor; sleep 2"' /tmp/media/guests.cast
  '';
in
pkgs.testers.runNixOSTest {
  name = "media-guests";
  nodes.host = {
    imports = nixieLib.hostModules ../../examples/site "server" exampleSite.hosts.server ++ [
      ../vm/qemu.nix
    ];
    virtualisation.sharedDirectories.nixie-site = {
      source = "${lib.cleanSource ../../examples/site}";
      target = "/etc/nixie/site";
    };
    virtualisation.memorySize = 4096;
    virtualisation.cores = 4;
    virtualisation.diskSize = 10 * 1024;
    nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:01" ];
    nixie.network.bridge.mode = "managed-nat";
    nixie.network.address = "192.168.1.1/24";
    nixie.incus.pools.default = {
      driver = "dir";
      source = "/var/lib/incus/storage-pools/default";
    };
    # The NixOS guests only: foreign images and the VM need the network and
    # nested virtualisation, which the recording VM has neither of.
    nixie.guests = lib.mkForce (
      lib.filterAttrs (
        n: _:
        lib.elem n [
          "web"
          "db"
          "builder"
        ]
      ) (import ../../examples/site/guests.nix)
      // {
        web = (import ../../examples/site/guests.nix).web // {
          ip = "10.90.0.10/24";
        };
        db = (import ../../examples/site/guests.nix).db // {
          ip = "10.90.0.20/24";
        };
      }
    );
    environment.systemPackages = [
      nixieCli
      pkgs.asciinema
      pkgs.curl
      pkgs.postgresql
    ];
  };
  testScript = template.fill ./guests.py {
    inherit cast;
  };
}
