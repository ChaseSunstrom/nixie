# The example server hosts its declared guest: `nixie apply` imports the
# image built with the host and creates the instance through tofu; the guest
# answers; a scratch instance is left alone; deleting the guest and applying
# again recreates it; `nixie export` round-trips the scratch instance.
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
      virtualisation.diskSize = 6 * 1024;
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
      ];
      # The scratch instance reuses the declared image so no download is needed.
      environment.etc."nixie-test-alias".text = config.nixie.build.guestImages.web.alias;
    };

  testScript = ''
    host.wait_for_unit("incus.service")
    host.wait_for_unit("incus-preseed.service")
    host.wait_until_succeeds("incus storage list -f csv | grep -q default")

    with subtest("apply creates the declared guest and it serves"):
        host.succeed("mkdir -p /data/state/web && echo hello-from-web > /data/state/web/index.html")
        host.succeed("nixie apply --yes --skip-host >&2")
        host.wait_until_succeeds("incus list web -c s -f csv | grep -q RUNNING")
        print(host.succeed("ip -br addr; incus list; incus exec web -- ip -br addr || true; incus exec web -- systemctl --failed --no-pager || true"))
        host.wait_until_succeeds("curl -sf --max-time 3 http://10.90.0.10/ | grep -q hello-from-web", timeout=120)
        host.succeed("ip link show veth-web")
        host.succeed("nft list chain bridge nixie-guests guest-web")
        print(host.succeed("nixie doctor || true"))

    with subtest("a scratch instance is left alone by apply"):
        alias = host.succeed("cat /etc/nixie-test-alias").strip()
        host.succeed(f"incus launch {alias} scratch")
        host.succeed("nixie apply --yes --skip-host >&2")
        host.succeed("incus list scratch -c s -f csv | grep -q RUNNING")

    with subtest("a deleted guest is recreated; state survives"):
        host.succeed("incus delete -f web")
        host.succeed("nixie apply --yes --skip-host >&2")
        host.wait_until_succeeds("curl -sf --max-time 3 http://10.90.0.10/ | grep -q hello-from-web", timeout=180)

    with subtest("export emits a guests.nix entry"):
        out = host.succeed("nixie export scratch")
        print(out)
        assert "scratch = {" in out and 'kind = "nixos"' in out, out
  '';
}
