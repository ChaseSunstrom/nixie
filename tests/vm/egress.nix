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
        # The default mode, where the bridge is the LAN port as well as the
        # guests': a rule meant for guests once dropped the LAN's SSH too.
        specialisation.lan.configuration = {
          nixie.network.bridge.mode = lib.mkForce "unmanaged-lan";
          nixie.network.egress = lib.mkForce "direct";
          nixie.network.tailscale.enable = lib.mkForce false;
        };
      };
  };

  testScript = builtins.readFile ./egress.py;
}
