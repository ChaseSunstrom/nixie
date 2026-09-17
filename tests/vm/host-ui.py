host.wait_for_unit("cockpit.socket")
host.wait_for_unit("nixie-oath-users.service")
host.wait_for_open_port(9090)
page = host.wait_until_succeeds("curl -sfk https://127.0.0.1:9090/")
assert "nixie" in page.lower(), page[:500]
host.succeed("curl -sfk https://127.0.0.1:9090/cockpit/static/branding.css | grep -q 'nixie'")

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
    host.succeed("nix-env --profile /nix/var/nix/profiles/system --set \"$(readlink -f /run/current-system)\"")
    h = _json.loads(host.succeed("nixie rollback --json"))
    assert set(h) == {"generations", "guests", "data", "backups"}, h
    assert len(h["generations"]) >= 1 and h["generations"][-1]["current"] is True, h
    print(h["generations"][-1])
