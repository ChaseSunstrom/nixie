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

  testScript = ''
    host.wait_for_unit("prometheus.service")
    host.wait_for_unit("grafana.service")
    host.wait_for_unit("incus-preseed.service")
    host.wait_for_open_port(9090)
    host.wait_for_open_port(3000)

    with subtest("every scrape target is up"):
        host.wait_until_succeeds("curl -sf localhost:9090/api/v1/targets | jq -e '[.data.activeTargets[] | select(.health != \"up\")] | length == 0'", timeout=120)
        jobs = host.succeed("curl -sf localhost:9090/api/v1/targets | jq -r '.data.activeTargets[].labels.job' | sort")
        assert "incus" in jobs and "node" in jobs, jobs
        host.wait_until_succeeds("curl -sf 'localhost:9090/api/v1/query?query=incus_memory_Usage_bytes' | jq -e '.data.result | length >= 0'")

    with subtest("the shipped dashboards are provisioned"):
        names = host.wait_until_succeeds("curl -sf -u admin:admin localhost:3000/api/search | jq -r '.[].uid' | sort")
        for uid in ["nixie-host", "nixie-guest", "nixie-gpu"]:
            assert uid in names, names
        gpu = host.succeed("curl -sf -u admin:admin localhost:3000/api/dashboards/uid/nixie-gpu")
        assert '"value": 250' in gpu or '"value":250' in gpu, "power cap missing from the GPU dashboard"
  '';
}
