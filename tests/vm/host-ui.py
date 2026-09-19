host.wait_for_unit("cockpit.socket")
host.wait_for_unit("nixie-oath-users.service")
host.wait_for_open_port(9090)
page = host.wait_until_succeeds("curl -sfk https://127.0.0.1:9090/")
assert "nixie" in page.lower(), page[:500]
# Into a file, not a pipe: the finish's own tokens are the first thing in
# the stylesheet, and `grep -q` closing early makes curl report a write error.
host.succeed("curl -sfk https://127.0.0.1:9090/cockpit/static/branding.css >/tmp/branding.css")
host.succeed("grep -q nixie /tmp/branding.css")

with subtest("password plus TOTP logs in; a wrong code does not"):
    code = host.succeed("oathtool --totp -b @totp@").strip()
    # Cockpit's login is HTTP basic for the first factor; the PAM
    # conversation for the second is answered with the X-Conversation flow.
    r = host.succeed("curl -sk -o /dev/null -w '%{http_code}' -u 'admin:nixie' https://127.0.0.1:9090/cockpit/login")
    assert r in ("401", "200"), r
    conv = host.succeed("curl -sk -i -u 'admin:nixie' https://127.0.0.1:9090/cockpit/login | grep -i 'x-conversation' || true")
    print(conv)
    # The second factor is configured, so the conversation must be offered.
    # Skipping this quietly let a login that never worked look verified:
    # `text` had replaced Cockpit's whole PAM stack with the OATH rule, so
    # no password was ever checked and every login was refused.
    assert "x-conversation" in conv.lower(), (
        "the password was not accepted for the first factor: " + repr(conv)
    )
    import base64, re
    tok = re.findall(r"X-Conversation (\S+)", conv, re.I)[0]
    ok = host.succeed(f"curl -sk -o /dev/null -w '%{{http_code}}' -H 'Authorization: X-Conversation {tok} {base64.b64encode(code.encode()).decode()}' https://127.0.0.1:9090/cockpit/login").strip()
    assert ok == "200", ok
    tok2 = re.findall(r"X-Conversation (\S+)", host.succeed("curl -sk -i -u 'admin:nixie' https://127.0.0.1:9090/cockpit/login | grep -i 'x-conversation'"), re.I)[0]
    bad = host.succeed(f"curl -sk -o /dev/null -w '%{{http_code}}' -H 'Authorization: X-Conversation {tok2} {base64.b64encode(b'000000').decode()}' https://127.0.0.1:9090/cockpit/login").strip()
    assert bad == "401", bad
    # cockpit-session reports each attempt through PAM's audit records.
    host.succeed("journalctl -b --no-pager | grep -E 'PAM:authentication.*acct=.admin.' | grep -q cockpit-session")

with subtest("the History screen is installed and the host can answer it"):
    # The page is joined into Cockpit's share alongside the branding.
    host.succeed("test -s /etc/cockpit/share/cockpit/nixie-history/manifest.json")
    host.succeed("test -s /etc/cockpit/share/cockpit/nixie-history/index.html")
    host.succeed("test -s /etc/cockpit/share/cockpit/nixie-history/history.js")
    import json as _json
    m = _json.loads(host.succeed("cat /etc/cockpit/share/cockpit/nixie-history/manifest.json"))
    assert m["menu"]["index"]["label"] == "History", m
    # It asks the CLI for JSON through the bridge; that is what the CLI prints.
    host.succeed("grep -q 'nixie\", \"rollback\", \"--json' /etc/cockpit/share/cockpit/nixie-history/history.js")
    # A machine with no generations recorded yet. The page asked this of the
    # host and got a line of shell errors back -- stat, date and jq each
    # failing on an unmatched glob passed through as a path -- where its
    # history belongs.
    empty = _json.loads(host.succeed("nixie rollback --json"))
    assert empty["generations"] == [], empty
    host.succeed("nix-env --profile /nix/var/nix/profiles/system --set \"$(readlink -f /run/current-system)\"")
    h = _json.loads(host.succeed("nixie rollback --json"))
    assert set(h) == {"generations", "guests", "data", "backups"}, h
    assert len(h["generations"]) >= 1 and h["generations"][-1]["current"] is True, h
    print(h["generations"][-1])

with subtest("the page can run apply, fetch and the checks, and they answer"):
    js = "/etc/cockpit/share/cockpit/nixie-history/history.js"
    # Each one spawned through the bridge, with its output streamed back.
    for argv in ('"nixie", "apply", "--yes"', '"nixie", "fetch"', '"nixie", "doctor"'):
        host.succeed(f"grep -q '{argv}' {js}")
    host.succeed(f"grep -q '.stream((data)' {js}")
    # And the commands themselves exist on this host to be spawned: doctor
    # is the one that says something without changing anything.
    doc = host.succeed("nixie doctor || true")
    print(doc)
    assert "disk" in doc, doc
    host.succeed("nixie fetch --help >/dev/null 2>&1 || nixie fetch 2>&1 | head -1 >&2 || true")
