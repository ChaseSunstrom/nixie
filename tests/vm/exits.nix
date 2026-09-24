# Egress through named exits (ARCHITECTURE 4.12). Two WireGuard providers sit
# on the LAN, each masquerading its tunnel onto an "internet" network the host
# is not on, where a web server answers with the caller's address -- so the
# answer says which exit carried a request. The second provider also plays
# NordVPN: its API (server list, credentials) is a static file server.
# Guests are network namespaces on the bridge, named as Incus names ports.
# Addresses are the test driver's: 192.168.<vlan>.<node>, nodes numbered
# alphabetically -- host 1, inet 2, lanbox 3, nord 4, vpn 5.
{
  pkgs,
  nixieLib,
  exampleSite,
}:
let
  whoami = {
    services.nginx = {
      enable = true;
      virtualHosts.default.locations."/".return = "200 $remote_addr";
    };
    networking.firewall.allowedTCPPorts = [ 80 ];
  };
  provider = {
    virtualisation.vlans = [
      1
      3
    ];
    networking.firewall.enable = false;
    networking.nat = {
      enable = true;
      externalInterface = "eth2";
      internalInterfaces = [ "wg0" ];
    };
    environment.systemPackages = [
      pkgs.wireguard-tools
      pkgs.python3
    ];
  };
in
pkgs.testers.runNixOSTest {
  name = "vm-exits";
  nodes = {
    inet = {
      imports = [ whoami ];
      virtualisation.vlans = [ 3 ];
    };
    lanbox = {
      imports = [ whoami ];
      virtualisation.vlans = [ 1 ];
    };
    vpn = provider;
    nord = provider;
    host =
      { lib, ... }:
      {
        imports = nixieLib.hostModules ../../examples/site "server" exampleSite.hosts.server ++ [
          ./qemu.nix
        ];
        virtualisation.vlans = [ 1 ];
        virtualisation.sharedDirectories.nixie-site = {
          source = "${lib.cleanSource ../../examples/site}";
          target = "/etc/nixie/site";
        };
        nixie.network = {
          bridge.uplinks = lib.mkForce [ "52:54:00:12:01:01" ];
          bridge.mode = "managed-nat";
          address = "192.168.1.1/24";
          # The secrets are written by the test before the exits start.
          exits = {
            wg1 = {
              type = "wireguard";
              configFile = "/run/secrets/wg1";
            };
            nord = {
              type = "nordvpn";
              tokenFile = "/run/secrets/nord";
              country = "ch";
            };
            tor = {
              type = "tor";
              via = "wg1";
            };
          };
          nordApi = "http://192.168.1.4:8000";
          guestEgress = [
            "wg1"
            "nord"
          ];
          hostEgress = [ "nord" ];
        };
        nixie.guests.app = { };
        nixie.guests.dir.egress = "direct";
        nixie.guests.web.egress = [ "tor" ];
        environment.systemPackages = [
          pkgs.curl
          pkgs.iproute2
          pkgs.netcat
          pkgs.wireguard-tools
        ];
      };
  };

  testScript = builtins.readFile ./exits.py;
}
