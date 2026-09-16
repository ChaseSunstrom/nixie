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
  inherit (pkgs) lib;
  py = pkgs.python3.withPackages (p: [ p.playwright ]);
  script = pkgs.writeText "shoot.py" ''
    import asyncio, os, sys, json
    from playwright.async_api import async_playwright
    OUT = "/tmp/media"; os.makedirs(OUT, exist_ok=True)
    BASE = "https://127.0.0.1:8443/ui/"
    SCREENS = ["overview", "machines", "instances", "instances/web", "instances/web/terminal", "instances/web/devices", "instances/web/snapshots", "instances/web/logs", "instances/web/files", "instances/web/metrics", "images", "profiles", "networks", "storage", "operations", "dashboards", "dashboards/nixie-guest", "settings"]
    async def main():
        async with async_playwright() as p:
            browser = await p.chromium.launch(args=["--ignore-certificate-errors"])
            for finish in ["graphite", "umber", "paper"]:
                ctx = await browser.new_context(viewport={"width": 1440, "height": 900}, ignore_https_errors=True,
                    client_certificates=[{"origin": "https://127.0.0.1:8443", "certPath": "/root/client.crt", "keyPath": "/root/client.key"}])
                page = await ctx.new_page()
                await page.goto(BASE)
                await page.evaluate(f"localStorage.setItem('nixie.finish', '{finish}')")
                for s in SCREENS:
                    await page.goto(BASE + "#/" + s)
                    await page.wait_for_timeout(2500)
                    await page.screenshot(path=f"{OUT}/panel-{s.replace('/', '-')}-{finish}.png")
                await page.goto(BASE + "#/instances")
                await page.wait_for_timeout(1500)
                await page.keyboard.press("Control+K"); await page.wait_for_timeout(600)
                await page.keyboard.type("term"); await page.wait_for_timeout(600)
                await page.screenshot(path=f"{OUT}/panel-palette-{finish}.png")
                await page.keyboard.press("Escape")
                await page.click("text=Export"); await page.wait_for_timeout(800)
                await page.screenshot(path=f"{OUT}/panel-export-{finish}.png")
                await ctx.close()
            # the walk-through video in one finish
            ctx = await browser.new_context(viewport={"width": 1440, "height": 900}, ignore_https_errors=True, record_video_dir="/tmp/rec", record_video_size={"width": 1440, "height": 900},
                client_certificates=[{"origin": "https://127.0.0.1:8443", "certPath": "/root/client.crt", "keyPath": "/root/client.key"}])
            page = await ctx.new_page()
            await page.goto(BASE + "#/overview"); await page.wait_for_timeout(6000)
            await page.mouse.move(400, 250); await page.mouse.move(700, 250, steps=40); await page.wait_for_timeout(1500)
            await page.click("text=web"); await page.wait_for_timeout(4000)
            await page.click("text=Terminal"); await page.wait_for_timeout(2500)
            await page.keyboard.type("uptime"); await page.keyboard.press("Enter"); await page.wait_for_timeout(3000)
            await page.goto(BASE + "#/dashboards/nixie-guest/web"); await page.wait_for_timeout(5000)
            await page.click("text=6h"); await page.wait_for_timeout(3000)
            video = page.video
            await ctx.close()
            # Playwright names its recordings with a GUID; the gallery and the
            # README refer to this file by name, so give it one.
            await video.save_as(f"{OUT}/walkthrough.webm")
            await browser.close()
    asyncio.run(main())
  '';
  cockpit = pkgs.writeText "cockpit.py" ''
    import asyncio, os, subprocess
    from playwright.async_api import async_playwright
    OUT = "/tmp/media"; os.makedirs(OUT, exist_ok=True)
    code = subprocess.check_output(["oathtool", "--totp", "-b", "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"]).decode().strip()
    async def main():
        async with async_playwright() as p:
            b = await p.chromium.launch(args=["--ignore-certificate-errors"])
            page = await (await b.new_context(viewport={"width": 1440, "height": 900}, ignore_https_errors=True)).new_page()
            await page.goto("https://127.0.0.1:9090/"); await page.wait_for_timeout(3000)
            await page.screenshot(path=f"{OUT}/hostui-login.png")
            await page.fill("#login-user-input", "admin"); await page.fill("#login-password-input", "nixie"); await page.click("#login-button")
            await page.wait_for_timeout(2500); await page.screenshot(path=f"{OUT}/hostui-second-factor.png")
            # Say what the page is showing if the second factor never appears.
            try:
                await page.wait_for_selector("#conversation-input:visible", timeout=20000)
            except Exception:
                print("LOGIN STUCK:", repr(await page.inner_text("body"))[:1500], flush=True)
                raise
            await page.fill("#conversation-input", code); await page.click("#login-button"); await page.wait_for_timeout(5000)
            await page.screenshot(path=f"{OUT}/hostui-overview.png")
            for path, name in [("/files", "files"), ("/system/terminal", "terminal"), ("/system/logs", "journal")]:
                await page.goto("https://127.0.0.1:9090" + path); await page.wait_for_timeout(4000)
                await page.screenshot(path=f"{OUT}/hostui-{name}.png")
            await b.close()
    asyncio.run(main())
  '';
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
  testScript = ''
    host.wait_for_unit("incus.service")
    host.wait_for_unit("incus-preseed.service")
    host.wait_for_unit("prometheus.service")
    host.succeed("mkdir -p /data/state/web && echo hello > /data/state/web/index.html")
    host.succeed("nixie apply --yes --skip-host >&2")
    host.wait_until_succeeds("incus list web -c s -f csv | grep -q RUNNING")
    host.succeed("incus launch $(jq -r '.declared.web.image' /etc/nixie/guests.json) scratch")
    host.succeed("openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 30 -subj /CN=media -keyout /root/client.key -out /root/client.crt 2>/dev/null && incus config trust add-certificate /root/client.crt")
    host.succeed("sleep 20")  # a little history for the charts
    host.succeed("python3 ${script} >&2")
    # The second factor is a PAM module reading a file another unit writes:
    # logging in before it exists is refused as a wrong password.
    host.wait_for_unit("cockpit.socket")
    host.wait_for_unit("nixie-oath-users.service")
    host.succeed("python3 ${cockpit} >&2")
    host.succeed("ls /tmp/media >&2")
    host.copy_from_vm("/tmp/media", "media")
  '';
}
