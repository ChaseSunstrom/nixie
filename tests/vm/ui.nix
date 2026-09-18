# incusd serves the control panel bundle and this host's nixie.json on the
# UI port; the daemon answers on the same origin.
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
  name = "vm-ui";
  nodes.host = {
    imports = nixieLib.hostModules ../../examples/site "server" exampleSite.hosts.server ++ [
      ./qemu.nix
    ];
    virtualisation.sharedDirectories.nixie-site = {
      source = "${lib.cleanSource ../../examples/site}";
      target = "/etc/nixie/site";
    };
    nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:01" ];
    nixie.network.address = "192.168.1.1/24";
    nixie.incus.pools.default = {
      driver = "dir";
      source = "/var/lib/incus/storage-pools/default";
    };
    nixie.ui.theme = "umber";
    nixie.ui.links = [
      {
        label = "Docs";
        url = "https://example.invalid/docs";
      }
    ];
    # What `lib.mkSite` writes from a site with more than one machine; this
    # test builds its host from the modules directly, so it stands in for it.
    nixie.ui.machines = [
      {
        name = "server";
        profile = "server";
        url = "https://192.168.1.1:8443";
      }
      {
        name = "laptop";
        profile = "desktop";
      }
    ];
    environment.systemPackages = [
      nixieCli
      pkgs.curl
      pkgs.jq
    ];
  };

  testScript = builtins.readFile ./ui.py;
}
