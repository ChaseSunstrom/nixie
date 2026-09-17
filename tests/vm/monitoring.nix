# Prometheus scrapes the host and the Incus metrics endpoint; Grafana serves
# the shipped dashboards.
{
  pkgs,
  nixieLib,
  exampleSite,
}:
let
  inherit (pkgs) lib;
in
pkgs.testers.runNixOSTest {
  name = "vm-monitoring";
  nodes.host = {
    imports = nixieLib.hostModules ../../examples/site "server" exampleSite.hosts.server ++ [
      ./qemu.nix
    ];
    virtualisation.sharedDirectories.nixie-site = {
      source = "${lib.cleanSource ../../examples/site}";
      target = "/etc/nixie/site";
    };
    virtualisation.memorySize = 2048;
    nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:01" ];
    nixie.network.address = "192.168.1.1/24";
    nixie.incus.pools.default = {
      driver = "dir";
      source = "/var/lib/incus/storage-pools/default";
    };
    nixie.monitoring = {
      enable = true;
      grafana.enable = true;
      gpuPowerCap = 250;
    };
    environment.systemPackages = [
      pkgs.curl
      pkgs.jq
    ];
  };

  testScript = builtins.readFile ./monitoring.py;
}
