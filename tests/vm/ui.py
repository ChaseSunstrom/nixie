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
# The store, which reads the host's notices, is in the shared chunk the page
# preloads beside the one above.
base = host.succeed("curl -sfk https://127.0.0.1:8443/ui/ | grep -o 'assets/base-[^\"]*\\.js'").strip()
host.succeed(f"curl -sfk https://127.0.0.1:8443/ui/{base} -o /tmp/base.js && grep -q user.nixie.notices /tmp/base.js")
# Each font as the stylesheet names it, resolved against the stylesheet's
# own URL: the files existing under /ui/fonts/ proved nothing while the CSS
# pointed somewhere else and the panel fell back to system fonts.
root = "https://127.0.0.1:8443/ui/"
css = urljoin(root, re.findall(r'href="([^"]+\.css)"', page)[0])
fonts = re.findall(r'url\(["\']?([^"\')]+\.ttf)', host.succeed(f"curl -sfk {css}"))
assert len(fonts) == 3, fonts
for f in fonts:
    magic = host.succeed(f"curl -sfk {urljoin(css, f)} -o /tmp/font && head -c 4 /tmp/font | od -An -tx1").split()
    assert magic == ["00", "01", "00", "00"], (f, magic)
# What the host wants a person to know reaches the panel through the daemon's
# own configuration, so it takes the same client certificate the rest of the
# panel's data does. A real notice, made by breaking a unit:
host.succeed(
    "systemd-run --unit=nixie-broken-test --service-type=oneshot "
    "/run/current-system/sw/bin/false || true"
)
host.wait_until_succeeds("systemctl is-failed nixie-broken-test.service")
host.succeed("nixie notices --write")
published = host.succeed("incus config get user.nixie.notices")
assert "nixie-broken-test" in published, published
host.succeed("systemctl reset-failed nixie-broken-test.service")
# And nothing of it reaches a browser with no certificate: the bundle beside
# it is public (incusd answers any path under it with the page itself), and
# the daemon hands an untrusted caller no configuration at all.
host.succeed("curl -sfk https://127.0.0.1:8443/ui/notices.json -o /tmp/served")
assert "nixie-broken-test" not in host.succeed("cat /tmp/served")

# Who the daemon trusts, and for how long, is part of `nixie doctor`: a
# browser certificate that quietly expired looks just like a panel that will
# not load. One that expires in three days, which is inside the fortnight it
# warns about:
host.succeed(
    "openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -sha256 -days 3 "
    "-nodes -subj /CN=soon -keyout /tmp/soon.key -out /tmp/soon.crt 2>/dev/null"
)
host.succeed("incus config trust add-certificate --name soon /tmp/soon.crt")
doc = host.succeed("nixie doctor || true")
print(doc)
assert "EXPIRING: soon" in doc, doc

# The daemon itself answers on the same origin, untrusted without a client certificate.
host.succeed("curl -sfk https://127.0.0.1:8443/1.0 | jq -e '.metadata.auth == \"untrusted\"'")
host.succeed("curl -sfk https://127.0.0.1:8443/1.0 | jq -e '.metadata.config // {} | has(\"user.nixie.notices\") | not'")
