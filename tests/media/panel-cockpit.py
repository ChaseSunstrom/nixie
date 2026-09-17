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
