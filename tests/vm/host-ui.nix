# The host page answers on its port with Nixie branding, and a login with
# the admin password and a valid TOTP code succeeds while a wrong code fails.
{
  pkgs,
  nixieLib,
  exampleSite,
}:
let
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
    ];
  };

  testScript = ''
    host.wait_for_unit("cockpit.socket")
    host.wait_for_unit("nixie-oath-users.service")
    host.wait_for_open_port(9090)
    page = host.wait_until_succeeds("curl -sfk https://127.0.0.1:9090/")
    assert "nixie" in page.lower(), page[:500]
    host.succeed("curl -sfk https://127.0.0.1:9090/cockpit/static/branding.css | grep -q 'nixie'")

    with subtest("password plus TOTP logs in; a wrong code does not"):
        code = host.succeed("oathtool --totp -b ${totp}").strip()
        # Cockpit's login is HTTP basic for the first factor; the PAM
        # conversation for the second is answered with the X-Conversation flow.
        r = host.succeed("curl -sk -o /dev/null -w '%{http_code}' -u 'admin:nixie' https://127.0.0.1:9090/cockpit/login")
        assert r in ("401", "200"), r
        conv = host.succeed("curl -sk -i -u 'admin:nixie' https://127.0.0.1:9090/cockpit/login | grep -i 'x-conversation' || true")
        print(conv)
        if "x-conversation" in conv.lower():
            import base64, re
            tok = re.findall(r"X-Conversation: (\S+)", conv, re.I)[0]
            ok = host.succeed(f"curl -sk -o /dev/null -w '%{{http_code}}' -H 'Authorization: X-Conversation {tok} {base64.b64encode(code.encode()).decode()}' https://127.0.0.1:9090/cockpit/login").strip()
            assert ok == "200", ok
            tok2 = re.findall(r"X-Conversation: (\S+)", host.succeed("curl -sk -i -u 'admin:nixie' https://127.0.0.1:9090/cockpit/login | grep -i 'x-conversation'"), re.I)[0]
            bad = host.succeed(f"curl -sk -o /dev/null -w '%{{http_code}}' -H 'Authorization: X-Conversation {tok2} {base64.b64encode(b'000000').decode()}' https://127.0.0.1:9090/cockpit/login").strip()
            assert bad == "401", bad
        # cockpit-session reports each attempt through PAM's audit records.
        host.succeed("journalctl -b --no-pager | grep -E 'PAM:authentication.*acct=.admin.' | grep -q cockpit-session")
  '';
}
