# tty1 shows the front panel after boot (read back with OCR), and with the
# kiosk on the local display shows the lock page, accepts the admin login and
# renders the control panel. Both closure states are checked in tests/default.nix.
{
  pkgs,
  nixieLib,
  exampleSite,
}:
let
  inherit (pkgs) lib;
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
      nixie.console.kiosk.enable = true;
    };
  };
  testScript = ''
    panel.start()
    panel.wait_for_unit("nixie-panel.service")
    panel.wait_for_text("(nixie|press any key)", timeout=180)
    panel.screenshot("front-panel")
    # The wordmark is drawn in block glyphs OCR cannot read; the lane list is
    # plain text, so it stands in for the page.
    text = panel.get_screen_text()
    assert "instances" in text.lower(), text
    panel.send_key("ret")
    panel.wait_for_text("login", timeout=60)
    panel.screenshot("front-panel-login")
    panel.shutdown()

    kiosk.start()
    kiosk.wait_for_unit("nixie-kiosk-gate.service")
    kiosk.wait_for_unit("cage-tty1.service")
    kiosk.wait_for_text("(Administrator|Unlock)", timeout=300)
    kiosk.screenshot("kiosk-lock")
    kiosk.succeed("curl -s -o /dev/null -w '%{http_code}' -d 'password=nixie' http://127.0.0.1:9444/unlock | grep -q 302")
    kiosk.succeed("curl -s -o /dev/null -w '%{http_code}' -d 'password=wrong' http://127.0.0.1:9444/unlock | grep -q 303")
    kiosk.wait_for_text("(nixie|Overview|Instances)", timeout=120)
    kiosk.screenshot("kiosk-panel")
    kiosk.succeed("systemctl is-active nixie-panel.service && systemctl show -p TTYPath nixie-panel.service | grep -q tty2")
  '';
}
