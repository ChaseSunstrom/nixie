import asyncio, os, re, sys
from playwright.async_api import async_playwright
OUT = "/tmp/media"; os.makedirs(OUT, exist_ok=True)
base = sys.argv[1]; code = sys.argv[2]; mode = sys.argv[3]
async def shot(page, name): await page.wait_for_timeout(1200); await page.screenshot(path=f"{OUT}/installer-{name}.png")
async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(args=["--ignore-certificate-errors"])
        page = await (await b.new_context(viewport={"width": 1280, "height": 900}, ignore_https_errors=True)).new_page()
        page.on("response", lambda r: print("RESP", r.status, r.url, flush=True) if "/api/" in r.url else None)
        await page.goto(base); await shot(page, "pair" if mode != "continuation" else "continuation-pair")
        await page.fill("input", code)
        # "text=Pair" matches the panel's own heading, "Pair this browser",
        # and clicking a heading does nothing: name the button.
        await page.click("button:has-text(\"Pair\")")
        # Pairing is done when its own input is gone: the continuation view
        # returns before the step heading, so waiting for an h1 hangs there.
        await page.wait_for_selector("input[placeholder=\"123456\"]", state="detached", timeout=30000)
        await page.wait_for_timeout(1500)
        if mode == "continuation":
            await shot(page, "continuation"); await b.close(); return
        await shot(page, "profile")
        await page.click("button:has-text(\"Next\")"); await shot(page, "hardware")
        # Say which step the wizard is actually on if the disks are not there.
        try:
            await page.wait_for_selector("input[name=disk]", timeout=20000)
        except Exception:
            body = await page.evaluate("document.body.innerText")
            print("WIZARD STUCK, page says:", repr(body)[:1500], flush=True)
            raise
        # The first radio is whatever the kernel lists first, which here is
        # a 4 KB floppy; name the disk this VM is meant to be installed on.
        await page.click("label:has-text(\"virtio-root\") input[name=disk]")
        await page.click("input[type=checkbox]"); await page.click("button:has-text(\"Next\")"); await shot(page, "name")
        await page.fill("input[placeholder*=lowercase]", "server"); await page.click("button:has-text(\"Next\")"); await shot(page, "security")
        # Security holds the administrator as well: without the name and
        # both secrets its Next button stays disabled.
        await page.fill(".field:has-text(\"Administrator name\") input", "admin")
        await page.fill(".field:has-text(\"Administrator password\") input", "nixie")
        await page.fill(".field:has-text(\"Disk passphrase\") input", "hunter2")
        await page.click("button:has-text(\"Next\")"); await shot(page, "network")
        # The time zone is a dropdown of this machine's own zones. The open
        # list is drawn by the browser, not the page, so what is checked is
        # that it holds them.
        zone = page.locator(".field:has-text('Time zone') select")
        await page.wait_for_function("document.querySelectorAll('select option').length > 100", timeout=30000)
        zones = await zone.locator("option").count()
        assert zones > 100, f"time zone list has {zones} entries"
        await page.click("button:has-text(\"Next\")"); await shot(page, "services")
        # A backup goes to a folder, and the folder can be picked from the
        # drives this machine can see. Opened and closed again: choosing one
        # would write a repository into the site being installed.
        await page.click("button:has-text(\"Choose a drive\")")
        await page.wait_for_selector(".pick, .picker .caption", timeout=30000)
        await shot(page, "services-backup-drive")
        await page.click("button:has-text(\"Choose a drive\")")
        # Review writes the site and evaluates the host before Install unlocks.
        await page.click(".wizard-foot .btn.primary")
        await page.wait_for_selector(".status.ok", timeout=900000); await shot(page, "review")
        await page.click("button:has-text(\"Continue to install\")"); await shot(page, "install-ready")
        # The stepper names its last step Install too; the action is the primary button.
        await page.click("button.btn.primary:has-text(\"Install\")"); await page.wait_for_timeout(4000); await shot(page, "install-streaming")
        done = False
        for _ in range(120):
            if await page.query_selector("button:has-text(\"Restart now\")"):
                done = True
                break
            await page.wait_for_timeout(5000)
        await shot(page, "install-done")
        # Carrying on regardless left the target with nothing to boot and
        # the run hanging at its passphrase prompt half an hour later.
        if not done:
            print("INSTALL DID NOT FINISH:",
                  repr(await page.evaluate("document.body.innerText"))[-2500:], flush=True)
            raise SystemExit("the wizard never reported phase 3 done")
        await b.close()
asyncio.run(main())
