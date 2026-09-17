# Media: the control panel and the host page, screenshotted screen by
# screen in every finish and walked once on video, by Playwright against
# the real daemon with a trusted client certificate. Output lands in $out.
{
  pkgs,
  nixieLib,
  exampleSite,
  nixieCli,
}:
let
  template = import ../../lib/template.nix pkgs.lib;
  inherit (pkgs) lib;
  py = pkgs.python3.withPackages (p: [ p.playwright ]);
  script = pkgs.writeText "shoot.py" (builtins.readFile ./panel-shoot.py);
  cockpit = pkgs.writeText "cockpit.py" (builtins.readFile ./panel-cockpit.py);
in
pkgs.testers.runNixOSTest {
  name = "media-panel";
  nodes.host = {
    imports = nixieLib.hostModules ../../examples/site "server" exampleSite.hosts.server ++ [
      ../vm/qemu.nix
    ];
    virtualisation.sharedDirectories.nixie-site = {
      source = "${lib.cleanSource ../../examples/site}";
      target = "/etc/nixie/site";
    };
    virtualisation.memorySize = 4096;
    virtualisation.cores = 4;
    virtualisation.diskSize = 8 * 1024;
    nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:01" ];
    nixie.network.bridge.mode = "managed-nat";
    nixie.network.address = "192.168.1.1/24";
    nixie.incus.pools.default = {
      driver = "dir";
      source = "/var/lib/incus/storage-pools/default";
    };
    nixie.guests = lib.mkForce {
      web = (import ../../examples/site/guests.nix).web // {
        ip = "10.90.0.10/24";
      };
    };
    # What `lib.mkSite` writes for a site with more than one machine; this
    # host is built from the modules directly, so the test stands in for it.
    nixie.ui.machines = [
      {
        name = "server";
        profile = "server";
        url = "https://192.168.1.1:8443";
      }
      {
        name = "laptop";
        profile = "desktop";
      }
    ];
    nixie.monitoring.enable = true;
    nixie.monitoring.grafana.enable = true;
    nixie.hostUi = {
      enable = true;
      listen = "lan+tailnet";
    };
    nixie.auth.secondFactor = "totp";
    sops.secrets.totp-secret = lib.mkForce { };
    systemd.services.nixie-oath-users.serviceConfig.ExecStartPre =
      pkgs.writeShellScript "seed" "mkdir -p /run/secrets && printf 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ' > /run/secrets/totp-secret";
    environment.systemPackages = [
      nixieCli
      py
      pkgs.openssl
      pkgs.oath-toolkit
      # The test script itself reads guests.json; the CLI's own jq is inside
      # its wrapper and not on PATH here.
      pkgs.jq
    ];
    environment.variables.PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    environment.variables.PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "1";
  };
  testScript = template.fill ./panel.py {
    inherit cockpit;
    inherit script;
  };
}
