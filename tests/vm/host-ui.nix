# The host page answers on its port with Nixie branding, and a login with
# the admin password and a valid TOTP code succeeds while a wrong code fails.
{
  pkgs,
  nixieLib,
  exampleSite,
  nixieCli,
}:
let
  template = import ../../lib/template.nix pkgs.lib;
  inherit (pkgs) lib;
  # The example secrets carry no TOTP secret; the test provides one so the
  # PAM path can be exercised. base32 of "12345678901234567890".
  totp = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
in
pkgs.testers.runNixOSTest {
  name = "vm-host-ui";
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
    nixie.hostUi = {
      enable = true;
      listen = "lan+tailnet";
    };
    nixie.auth.secondFactor = "totp";
    # Test only: stand in for the sops-provided secret.
    sops.secrets.totp-secret = lib.mkForce { };
    systemd.services.nixie-oath-users.serviceConfig.ExecStartPre =
      pkgs.writeShellScript "seed" "mkdir -p /run/secrets && printf '${totp}' > /run/secrets/totp-secret";
    environment.systemPackages = [
      pkgs.curl
      pkgs.oath-toolkit
      nixieCli
    ];
  };

  testScript = template.fill ./host-ui.py {
    inherit totp;
  };
}
