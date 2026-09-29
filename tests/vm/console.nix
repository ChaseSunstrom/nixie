# tty1 shows the front panel after boot (read back with OCR), and with the
# kiosk on the local display shows the lock page, takes the admin password
# and the authenticator code typed on the screen, renders the control panel
# through incusd's socket, and locks itself again when nobody touches it.
# Both closure states are checked in tests/default.nix.
{
  pkgs,
  nixieLib,
  exampleSite,
}:
let
  inherit (pkgs) lib;
  template = import ../../lib/template.nix lib;
  # The example secrets carry no TOTP secret; the test provides one.
  # base32 of "12345678901234567890".
  totp = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
  base = {
    imports = nixieLib.hostModules ../../examples/site "server" exampleSite.hosts.server ++ [
      ./qemu.nix
    ];
    virtualisation.sharedDirectories.nixie-site = {
      source = "${lib.cleanSource ../../examples/site}";
      target = "/etc/nixie/site";
    };
    virtualisation.resolution = {
      x = 1280;
      y = 800;
    };
    nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:01" ];
    nixie.network.address = "192.168.1.1/24";
    nixie.incus.pools.default = {
      driver = "dir";
      source = "/var/lib/incus/storage-pools/default";
    };
  };
in
pkgs.testers.runNixOSTest {
  name = "vm-console";
  enableOCR = true;
  nodes = {
    panel = base;
    kiosk = {
      imports = [ base ];
      virtualisation.memorySize = 3072;
      nixie.console.kiosk = {
        enable = true;
        idleLock = "2m";
      };
      nixie.auth.secondFactor = "totp";
      # Test only: stand in for the sops-provided secret.
      sops.secrets.totp-secret = lib.mkForce { };
      systemd.services.nixie-kiosk-gate.serviceConfig.ExecStartPre =
        pkgs.writeShellScript "seed" "mkdir -p /run/secrets && printf '${totp}' > /run/secrets/totp-secret";
      environment.systemPackages = [
        pkgs.curl
        pkgs.oath-toolkit
      ];
    };
  };
  testScript = template.fill ./console.py { inherit totp; };
}
