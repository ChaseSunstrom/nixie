# Media: the example guests answering, as a terminal recording.
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
  testScript = ''
    host.wait_for_unit("incus-preseed.service")
    host.succeed("mkdir -p /data/state/web /data/state/db && echo '<h1>hello from web</h1>' > /data/state/web/index.html")
    host.succeed("nixie apply --yes --skip-host >&2")
    host.wait_until_succeeds("curl -sf --max-time 3 http://10.90.0.10/ | grep -q hello", timeout=240)
    host.wait_until_succeeds("incus exec db -- systemctl is-active postgresql", timeout=240)
    host.wait_until_succeeds("incus exec builder -- podman info >/dev/null", timeout=240)
    host.succeed("mkdir -p /tmp/media && asciinema rec --overwrite -c 'bash -c \"incus list; sleep 1; curl -s http://10.90.0.10/; sleep 1; incus exec db -- sudo -u postgres psql -c \\\"select version()\\\"; sleep 1; incus exec builder -- podman info | head -5; sleep 1; nixie doctor; sleep 2\"' /tmp/media/guests.cast")
    host.copy_from_vm("/tmp/media/guests.cast", "media")
  '';
}
