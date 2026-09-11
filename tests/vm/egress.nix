# Proves the egress policy: under exit-node, a declared guest and an
# undeclared one can only leave through the tunnel interface; under direct
# they reach the LAN. Guests are network namespaces on the bridge with the
# same veth names Incus would give them; the tunnel is a second test VLAN
# whose host-side port is named like Tailscale's.
{
  pkgs,
  nixieLib,
  exampleSite,
}:
let
  inherit (pkgs) lib;
  web = pkgs.writeText "index.html" "hello";
  serve = {
    services.nginx = {
      enable = true;
      virtualHosts.default.root = pkgs.runCommand "root" { } "mkdir $out; cp ${web} $out/index.html";
    };
    networking.firewall.allowedTCPPorts = [ 80 ];
  };
in
pkgs.testers.runNixOSTest {
  name = "vm-egress";
  nodes = {
    # Node numbers are alphabetical: exit = 1, host = 2, internet = 3.
    exit = {
      imports = [ serve ];
      virtualisation.vlans = [ 2 ];
    };
    internet = {
      imports = [ serve ];
      virtualisation.vlans = [ 1 ];
    };
    host =
      { lib, ... }:
      {
        imports = nixieLib.hostModules ../../examples/site "server" exampleSite.hosts.server ++ [
          ./qemu.nix
        ];
        virtualisation.vlans = [
          1
          2
        ];
        virtualisation.sharedDirectories.nixie-site = {
          source = "${lib.cleanSource ../../examples/site}";
          target = "/etc/nixie/site";
        };
        nixie.network = {
          bridge.uplinks = lib.mkForce [ "52:54:00:12:01:02" ];
          bridge.mode = "managed-nat";
          address = "192.168.1.2/24";
          egress = "exit-node";
          exitNode = "exit";
          tailscale.enable = true;
        };
        nixie.guests.web = { };
        # The second VLAN plays the tunnel: named like Tailscale's interface and
        # carrying the host's default route, as an exit node would.
        systemd.network.links."10-tunnel" = {
          matchConfig.MACAddress = "52:54:00:12:02:02";
          linkConfig.Name = "tailscale0";
        };
        systemd.network.networks."30-tunnel" = {
          matchConfig.Name = "tailscale0";
          address = [ "192.168.2.2/24" ];
          gateway = [ "192.168.2.1" ];
        };
        environment.systemPackages = [
          pkgs.curl
          pkgs.iproute2
          pkgs.netcat
        ];
        specialisation.direct.configuration = {
          nixie.network.egress = lib.mkForce "direct";
          nixie.network.tailscale.enable = lib.mkForce false;
        };
      };
  };

  testScript = ''
    def guest(name, addr):
        host.succeed(f"ip link add veth-{name} type veth peer name g-{name}")
        host.succeed(f"ip link set veth-{name} master nixie-br up")
        host.succeed(f"ip netns add {name} && ip link set g-{name} netns {name}")
        host.succeed(f"ip -n {name} addr add {addr}/24 dev g-{name} && ip -n {name} link set g-{name} up && ip -n {name} link set lo up")
        host.succeed(f"ip -n {name} route add default via 10.90.0.1")

    def can_fetch(ns, url):
        rc, _ = host.execute(f"ip netns exec {ns} curl -sS --max-time 3 {url}")
        return rc == 0

    start_all()
    exit.wait_for_unit("nginx.service")
    internet.wait_for_unit("nginx.service")
    host.wait_for_unit("systemd-networkd.service")
    host.wait_for_unit("nftables.service")
    print(host.succeed("networkctl list; ip -br addr; journalctl -b -u systemd-networkd --no-pager | tail -20"))
    host.wait_until_succeeds("ip addr show nixie-br | grep -q 10.90.0.1", timeout=60)
    host.succeed("ip link show uplink0 && ip link show nixie-br && ip link show tailscale0")
    host.succeed("nft list chain bridge nixie-guests guest-web && nft list chain bridge nixie-guests guest-undeclared")
    guest("web", "10.90.0.10")
    guest("scratch", "10.90.0.11")

    with subtest("exit-node: guests reach only the tunnel side"):
        for ns in ["web", "scratch"]:
            assert can_fetch(ns, "http://192.168.2.1/"), f"{ns} cannot reach the exit node"
            assert not can_fetch(ns, "http://192.168.1.3/"), f"{ns} reached the LAN directly"

    with subtest("guests cannot reach the host's SSH"):
        host.fail("ip netns exec web nc -z -w 2 10.90.0.1 22")
        internet.succeed("nc -z -w 2 192.168.1.2 22")

    with subtest("direct: guests reach the LAN through the host"):
        host.succeed("/run/current-system/specialisation/direct/bin/switch-to-configuration test >&2")
        host.wait_for_unit("nftables.service")
        assert can_fetch("web", "http://192.168.1.3/"), "declared guest cannot reach the LAN under direct"
        assert can_fetch("scratch", "http://192.168.1.3/"), "scratch guest cannot reach the LAN under direct"
  '';
}
