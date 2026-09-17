host.wait_for_unit("prometheus.service")
host.wait_for_unit("grafana.service")
host.wait_for_unit("incus-preseed.service")
host.wait_for_open_port(9091)
host.wait_for_open_port(3000)

with subtest("every scrape target is up"):
    host.wait_until_succeeds("curl -sf localhost:9091/api/v1/targets | jq -e '[.data.activeTargets[] | select(.health != \"up\")] | length == 0'", timeout=120)
    jobs = host.succeed("curl -sf localhost:9091/api/v1/targets | jq -r '.data.activeTargets[].labels.job' | sort")
    assert "incus" in jobs and "node" in jobs, jobs
    host.wait_until_succeeds("curl -sf 'localhost:9091/api/v1/query?query=incus_memory_Usage_bytes' | jq -e '.data.result | length >= 0'")

with subtest("the shipped dashboards are provisioned"):
    names = host.wait_until_succeeds("curl -sf -u admin:admin localhost:3000/api/search | jq -r '.[].uid' | sort")
    for uid in ["nixie-host", "nixie-guest", "nixie-gpu"]:
        assert uid in names, names
    gpu = host.succeed("curl -sf -u admin:admin localhost:3000/api/dashboards/uid/nixie-gpu")
    assert '"value": 250' in gpu or '"value":250' in gpu, "power cap missing from the GPU dashboard"
