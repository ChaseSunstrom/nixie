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
