import json

# Declared guests' ports are veth-<name>; Incus names anyone else's veth<hex>.
def guest(name, addr, port=None):
    port = port or f"veth-{name}"
    host.succeed(f"ip link add {port} type veth peer name g-{name}")
    host.succeed(f"ip link set {port} master nixie-br up")
    host.succeed(f"ip netns add {name} && ip link set g-{name} netns {name}")
    host.succeed(f"ip -n {name} addr add {addr}/24 dev g-{name} && ip -n {name} link set g-{name} up && ip -n {name} link set lo up")
    host.succeed(f"ip -n {name} route add default via 10.90.0.1")

def fetch(ns, url):
    """The body a guest gets (the caller's address, as the web server saw it), or None."""
    prefix = f"ip netns exec {ns} " if ns else ""
    rc, out = host.execute(f"{prefix}curl -sS --max-time 4 {url}")
    return out.strip() if rc == 0 else None

INET = "http://192.168.3.2/"   # only reachable through a provider
LAN = "http://192.168.1.3/"
VPN_OUT, NORD_OUT = "192.168.3.5", "192.168.3.4"  # how each provider appears there

def wg_server(m, addr, peer_pub, peer_ip):
    m.succeed("umask 077; wg genkey > /root/k; wg pubkey < /root/k > /root/k.pub")
    m.succeed(f"ip link add wg0 type wireguard && wg set wg0 listen-port 51820 private-key /root/k "
              f"peer {peer_pub} allowed-ips {peer_ip}/32 && ip addr add {addr} dev wg0 && ip link set wg0 up")
    return m.succeed("cat /root/k.pub").strip()

start_all()
inet.wait_for_unit("nginx.service")
lanbox.wait_for_unit("nginx.service")
host.wait_for_unit("nftables.service")
host.wait_until_succeeds("ip addr show nixie-br | grep -q 10.90.0.1", timeout=60)

with subtest("the providers: a WireGuard server, and one that is also NordVPN's API"):
    host.succeed("mkdir -p /run/secrets && umask 077 && wg genkey > /root/h1 && wg genkey > /root/h2")
    h1pub = host.succeed("wg pubkey < /root/h1").strip()
    h2pub = host.succeed("wg pubkey < /root/h2").strip()
    h2key = host.succeed("cat /root/h2").strip()
    vpn_pub = wg_server(vpn, "10.66.0.1/24", h1pub, "10.66.0.2")
    nord_pub = wg_server(nord, "10.5.0.1/24", h2pub, "10.5.0.2")
    host.succeed(
        "umask 077; printf '[Interface]\\nPrivateKey = %s\\nAddress = 10.66.0.2/32\\nDNS = 10.66.0.1\\n"
        f"[Peer]\\nPublicKey = {vpn_pub}\\nEndpoint = 192.168.1.5:51820\\nAllowedIPs = 0.0.0.0/0\\n' "
        "\"$(cat /root/h1)\" > /run/secrets/wg1"
    )
    host.succeed("umask 077; echo test-token > /run/secrets/nord")
    api = {
        "servers/countries": [{"id": 209, "code": "CH", "name": "Switzerland"}],
        "servers/recommendations": [{"hostname": "ch1.test", "station": "192.168.1.4", "technologies": [
            {"identifier": "wireguard_udp", "metadata": [{"name": "public_key", "value": nord_pub}]}]}],
        "users/services/credentials": {"nordlynx_private_key": h2key},
    }
    for path, body in api.items():
        nord.succeed(f"mkdir -p /srv/v1/$(dirname {path}) && echo '{json.dumps(body)}' > /srv/v1/{path}")
    nord.succeed("systemd-run --unit nord-api -p WorkingDirectory=/srv python3 -m http.server 8000")
    nord.wait_for_open_port(8000)
    host.succeed("systemctl restart nixie-exit-wg1.service nixie-exit-nord.service")
    host.succeed("systemctl restart nixie-egress.service")
    print(host.succeed("wg show; ip rule; cat /run/nixie-exit-nord/server"))
    guest("app", "10.90.0.10")
    guest("scratch", "10.90.0.11", port="veth8ddc20dc")
    guest("dir", "10.90.0.12")
    guest("web", "10.90.0.13")

with subtest("guests leave by the first working exit in their list, never directly"):
    for ns in ["app", "scratch"]:
        host.wait_until_succeeds(f"test \"$(ip netns exec {ns} curl -sS --max-time 4 {INET})\" = {VPN_OUT}", timeout=120)
        assert fetch(ns, LAN) is None, f"{ns} reached the LAN directly"

with subtest("a direct guest uses the uplinks"):
    assert fetch("dir", LAN) == "192.168.1.1", "the direct guest cannot reach the LAN"

with subtest("the machine's own traffic uses its own list, and the LAN still reaches it"):
    host.wait_until_succeeds(f"test \"$(curl -sS --max-time 4 {INET})\" = {NORD_OUT}", timeout=120)
    assert fetch(None, LAN) == "192.168.1.1", "the host lost its LAN"
    lanbox.succeed("nc -z -w 3 192.168.1.1 22")

with subtest("nixie egress: status, pin, back to the list"):
    status = json.loads(host.succeed("nixie egress status --json"))
    assert status["exits"]["wg1"]["up"] and status["exits"]["nord"]["up"], status
    assert status["scopes"]["guests"]["using"] == "wg1", status
    assert status["servers"]["nord"] == "ch1.test", status
    print(host.succeed("nixie egress"))
    host.succeed("nixie egress use nord --guests")
    host.wait_until_succeeds(f"test \"$(ip netns exec app curl -sS --max-time 4 {INET})\" = {NORD_OUT}", timeout=30)
    host.succeed("nixie egress auto --guests")
    host.wait_until_succeeds(f"test \"$(ip netns exec app curl -sS --max-time 4 {INET})\" = {VPN_OUT}", timeout=30)
    host.fail("nixie egress use tor --guest app")  # app follows the guests' list

with subtest("Tor: cut off until it works; pinned, TCP goes to Tor and nothing else leaves"):
    # This network has no Tor directory, so Tor never finishes starting.
    host.fail("ip netns exec web nc -z -w 3 192.168.1.3 80")
    host.succeed("nixie egress use tor --guest web")
    # A private address only this far: Tor takes the connection on its
    # transparent port and then refuses to carry it, and says so -- which is
    # what shows the guest's TCP went to Tor, since nothing else routes there.
    host.execute("ip netns exec web nc -w 3 192.168.3.2 80 </dev/null")
    host.wait_until_succeeds("journalctl -u nixie-tor-tor -b | grep -q 'on a TransPort'", timeout=20)
    host.fail("ip netns exec web ping -c 1 -W 2 192.168.1.3")
    host.succeed("nixie egress auto --guest web")

with subtest("failover: the first exit goes down, the next takes over"):
    vpn.succeed("ip link set wg0 down")
    host.wait_until_succeeds(f"test \"$(ip netns exec app curl -sS --max-time 4 {INET})\" = {NORD_OUT}", timeout=400)
    assert fetch("scratch", INET) == NORD_OUT

with subtest("kill switch: with every exit down, guests and the machine are cut off"):
    nord.succeed("ip link set wg0 down")
    host.wait_until_succeeds(f"! ip netns exec app curl -sS --max-time 4 {INET}", timeout=400)
    host.wait_until_succeeds(f"! curl -sS --max-time 4 {INET}", timeout=60)
    # Still routed into the dead tunnel until its last handshake is old enough
    # to call it down; then into the blackhole. Neither is the LAN.
    host.wait_until_succeeds("nixie egress status --json | tr -d ' \\n' | grep -q '\"guests\":{\"using\":\"none\"'", timeout=300)
    for ns in ["app", "scratch"]:
        assert fetch(ns, LAN) is None, f"{ns} leaked to the LAN with every exit down"
        assert fetch(ns, INET) is None, f"{ns} got out with every exit down"
    assert fetch(None, LAN) == "192.168.1.1", "the host lost its LAN with every exit down"
