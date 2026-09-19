# The example server hosts its declared guest: `nixie apply` imports the
# image built with the host and creates the instance through tofu; the guest
# answers; a scratch instance is left alone; deleting the guest and applying
# again recreates it; `nixie export` round-trips the scratch instance and
# `nixie declare` writes it into the site, which apply adopts rather than
# making a second instance of.
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
  name = "vm-guests";
  nodes.host =
    { config, ... }:
    {
      imports = nixieLib.hostModules ../../examples/site "server" exampleSite.hosts.server ++ [
        ./qemu.nix
      ];
      virtualisation.sharedDirectories.nixie-site = {
        source = "${lib.cleanSource ../../examples/site}";
        target = "/etc/nixie/site";
      };
      virtualisation.memorySize = 3072;
      virtualisation.cores = 4;
      virtualisation.diskSize = 12 * 1024; # a dir pool snapshots a guest by copying it
      nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:01" ];
      nixie.network.bridge.mode = "managed-nat";
      nixie.network.address = "192.168.1.1/24";
      # No pool on a test disk: a directory pool instead of ZFS.
      nixie.incus.pools.default = {
        driver = "dir";
        source = "/var/lib/incus/storage-pools/default";
      };
      # Only the NixOS web guest: foreign images need the network and the
      # VM needs nested virtualisation, neither of which a test has.
      nixie.guests = lib.mkForce {
        web = (import ../../examples/site/guests.nix).web // {
          ip = "10.90.0.10/24";
        };
      };
      environment.systemPackages = [
        nixieCli
        pkgs.curl
        # The same one the CLI carries: the adoption subtest makes the state
        # forget an instance that is still running.
        (pkgs.opentofu.withPlugins (p: [ p.lxc_incus ]))
      ];
      # The scratch instance reuses the declared image so no download is needed.
      environment.etc."nixie-test-alias".text = config.nixie.build.guestImages.web.alias;
    };

  testScript = builtins.readFile ./guests.py;
}
