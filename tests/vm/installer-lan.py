import json, re
from urllib.parse import urljoin

def api(method, path, data=None, raw=False):
    body = f"-d '{json.dumps(data)}'" if data is not None else ""
    out = client.succeed(f"curl -sk -b /tmp/c -c /tmp/c -X {method} -H 'Content-Type: application/json' {body} https://192.168.1.2:9443{path}")
    return out if raw else json.loads(out)

def phase(n, data=None):
    out = api("POST", f"/api/phase/{n}", data or {}, raw=True)
    print(out[-2000:])
    m = re.search(r'event: done\ndata: (.*)', out)
    return json.loads(m.group(1))["rc"] if m else 1

def pair():
    banner = installer.succeed("cat /var/lib/nixie/setup/banner.txt")
    code = re.findall(r"Pairing code: (\d{6})", banner)[0]
    assert "Certificate fingerprint" in banner and "https://192.168.1.2:9443" in banner, banner
    assert api("POST", "/api/pair", {"code": code})["ok"]
    client.fail(f"curl -sk -X POST -H 'Content-Type: application/json' -d '{{\"code\": \"{code}\"}}' https://192.168.1.2:9443/api/pair | grep -q ok")  # single use

client.start()
installer.start()
installer.wait_for_unit("nixie-setup.service")
installer.wait_for_open_port(9443)
client.wait_until_succeeds("curl -sk https://192.168.1.2:9443/api/pair | grep -q needsCode", timeout=120)

with subtest("the kiosk shows the wizard on the installer's own screen"):
    installer.wait_for_unit("cage-tty1.service")
    # Paired by the local token: the pairing form would ask for a code that
    # is printed on the console behind the kiosk.
    # The first step and its choices, drawn large enough to read back.
    installer.wait_for_text("(Machine|Server|Desktop)", timeout=300)
    installer.screenshot("kiosk-wizard")
    # The wizard alone, not a browser window: its address bar shows the URL.
    screen = installer.get_screen_text()
    assert "Pair this browser" not in screen, screen
    assert "127.0.0.1" not in screen and "9443" not in screen, screen

with subtest("the wizard's fonts load from the address its stylesheet names"):
    base = "https://192.168.1.2:9443/"
    index = client.succeed(f"curl -sk {base}")
    css = urljoin(base, re.findall(r'href="([^"]+\.css)"', index)[0])
    fonts = re.findall(r'url\(["\']?([^"\')]+\.ttf)', client.succeed(f"curl -sk {css}"))
    assert len(fonts) == 3, fonts
    for f in fonts:
        ctype = client.succeed(f"curl -sk -o /dev/null -w '%{{content_type}}' {urljoin(css, f)}")
        assert ctype == "font/ttf", (f, ctype)

with subtest("pair from the LAN with the single-use code"):
    pair()
    hw = api("GET", "/api/hardware")
    assert any(d["path"] == "/dev/vda" for d in hw["disks"]), hw
    # Every disk the kernel has must be offered. A disk with no
    # /dev/disk/by-id link used to be dropped from this list entirely,
    # which leaves the wizard with nothing to install on.
    disks = installer.succeed("lsblk -d -n -o TYPE,PATH").splitlines()
    # zram is the installer's compressed swap, not somewhere to install.
    paths = sorted(ln.split()[1] for ln in disks if ln.split()[0] == "disk" and "/zram" not in ln)
    assert not any("zram" in d["path"] for d in hw["disks"]), hw["disks"]
    assert sorted(d["path"] for d in hw["disks"]) == paths, (hw["disks"], paths)
    opts = api("GET", "/api/options")
    assert any(o["path"] == "nixie.security.encryption.enable" and o["section"] == "security" for o in opts)

with subtest("configure, plan, install"):
    api("POST", "/api/secrets", {"passphrase": "hunter2", "admin-password": "nixie"})
    api("POST", "/api/config", {"host": "server", "profile": "server", "systemDisk": "/dev/vda", "uplinks": ["52:54:00:12:01:03"], "settings": {"nixie.auth.admin.name": "admin", "nixie.security.encryption.enable": True}})
    # A module of the site's own, in the file the wizard leaves to the site:
    # hosts/<name>/configuration.nix, which it writes once and then never
    # touches (the directory itself is remade when the host entry is
    # written, so this belongs after that). Its option asks for a wizard
    # section, which is the extension point docs/extending.md describes.
    installer.succeed(
        "cat >/etc/nixie/site/hosts/server/configuration.nix <<'EOF'\n"
        "{ inputs, lib, ... }:\n"
        "{\n"
        "  options.nixie.site.motto = inputs.nixie.lib.mkOption {\n"
        "    type = lib.types.str;\n"
        '    default = "";\n'
        '    description = "A line this site puts on its own machines.";\n'
        '    nixieUi.section = "services";\n'
        "  };\n"
        "}\n"
        "EOF"
    )
    assert phase(1) == 0
    plan = api("GET", "/api/plan")
    assert 'nixie.disks.system = "/dev/vda"' in plan["hardware"] and "nixie.security.encryption.enable = true" in plan["site"], plan
    assert phase(2) == 0
    assert phase(3) == 0
    installer.succeed("test -e /var/lib/nixie/setup/3.done")
    # And now that the site evaluates, the wizard offers the site's own
    # option beside the platform's, with the section it asked for.
    opts = api("GET", "/api/options")
    mine = [o for o in opts if o["path"] == "nixie.site.motto"]
    assert mine and mine[0]["section"] == "services", mine
    # No label is written for it anywhere in the platform, so the wizard
    # falls back to the option's own path.
    assert mine[0]["label"] is None, mine
    assert any(o["path"] == "nixie.security.encryption.enable" for o in opts), "the platform's own are still there"
    installer.shutdown()

with subtest("first boot lands in the setup generation and continues over the same URL"):
    target.start()
    # The splash's label, which Plymouth's text view puts on the serial
    # console this VM has.
    target.wait_for_console_text("Disk passphrase")
    target.send_console("hunter2\n")
    target.wait_for_unit("nixie-setup.service")
    target.succeed("test -e /var/lib/nixie/setup/3.done && test -e /var/lib/nixie/age.key")
    # nixie-setup.service exists only in the setup generation, so being active proves the boot entry.
    target.wait_for_open_port(9443)
    banner = target.succeed("cat /var/lib/nixie/setup/banner.txt")
    code = re.findall(r"Pairing code: (\d{6})", banner)[0]
    client.succeed(f"curl -sk -c /tmp/c2 -X POST -H 'Content-Type: application/json' -d '{{\"code\": \"{code}\"}}' https://192.168.1.3:9443/api/pair | grep -q ok")
    for n in (4, 5, 6, 7):
        if n == 6:  # the wizard asks for the passphrase again before TPM enrolment
            client.succeed("curl -sk -b /tmp/c2 -X POST -H 'Content-Type: application/json' -d '{\"passphrase\": \"hunter2\"}' https://192.168.1.3:9443/api/secrets")
        out = client.succeed(f"curl -sk -b /tmp/c2 -X POST -H 'Content-Type: application/json' -d '{{}}' https://192.168.1.3:9443/api/phase/{n}")
        assert '"rc": 0' in out, out
    target.succeed("test -e /var/lib/nixie/setup/7.done")
    st = json.loads(client.succeed("curl -sk -b /tmp/c2 https://192.168.1.3:9443/api/state"))
    assert st["mode"] == "continuation" and 7 in st["done"], st
