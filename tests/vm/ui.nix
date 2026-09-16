# incusd serves the control panel bundle and this host's nixie.json on the
# UI port; the daemon answers on the same origin.
{
  pkgs,
  nixieLib,
  exampleSite,
}:
let
  inherit (pkgs) lib;
in
pkgs.testers.runNixOSTest {
  name = "vm-ui";
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
    nixie.ui.theme = "umber";
    nixie.ui.links = [
      {
        label = "Docs";
        url = "https://example.invalid/docs";
      }
    ];
    # What `lib.mkSite` writes from a site with more than one machine; this
    # test builds its host from the modules directly, so it stands in for it.
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
    environment.systemPackages = [
      pkgs.curl
      pkgs.jq
    ];
  };

  testScript = ''
    import re
    from urllib.parse import urljoin

    host.wait_for_unit("incus.service")
    host.wait_for_unit("incus-preseed.service")
    host.wait_for_open_port(8443)
    # incusd serves the bundle under /ui/ and redirects browsers there.
    page = host.wait_until_succeeds("curl -sfk https://127.0.0.1:8443/ui/")
    assert "<title>nixie</title>" in page, page
    site = host.succeed("curl -sfk https://127.0.0.1:8443/ui/nixie.json")
    cfg = __import__("json").loads(site)
    assert cfg["theme"] == "umber" and cfg["links"][0]["label"] == "Docs" and "web" in cfg["declared"], site
    # The Machines page is drawn from these: every machine of the site, and
    # which of them is the one answering.
    assert cfg["host"] == "server", site
    assert [m["name"] for m in cfg["machines"]] == ["server", "laptop"], site
    assert cfg["machines"][1]["url"] is None and cfg["machines"][1]["profile"] == "desktop", site
    js = host.succeed("curl -sfk https://127.0.0.1:8443/ui/ | grep -o 'assets/ui-[^\"]*\\.js'").strip()
    host.succeed(f"curl -sfk https://127.0.0.1:8443/ui/{js} -o /tmp/ui.js && grep -q 'Command palette' /tmp/ui.js")
    # Each font as the stylesheet names it, resolved against the stylesheet's
    # own URL: the files existing under /ui/fonts/ proved nothing while the CSS
    # pointed somewhere else and the panel fell back to system fonts.
    base = "https://127.0.0.1:8443/ui/"
    css = urljoin(base, re.findall(r'href="([^"]+\.css)"', page)[0])
    fonts = re.findall(r'url\(["\']?([^"\')]+\.ttf)', host.succeed(f"curl -sfk {css}"))
    assert len(fonts) == 3, fonts
    for f in fonts:
        magic = host.succeed(f"curl -sfk {urljoin(css, f)} -o /tmp/font && head -c 4 /tmp/font | od -An -tx1").split()
        assert magic == ["00", "01", "00", "00"], (f, magic)
    # The daemon itself answers on the same origin, untrusted without a client certificate.
    host.succeed("curl -sfk https://127.0.0.1:8443/1.0 | jq -e '.metadata.auth == \"untrusted\"'")
  '';
}
