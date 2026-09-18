# Drive the wizard through the browser on the machine's own screen.
#
# `nixie-test-iso` otherwise talks to the setup backend over HTTP, which
# proves the phases but not the page a person at the machine actually uses:
# cage, chromium, the local token that pairs the kiosk without a code, and
# the wizard rendering inside all of that. This connects to that browser over
# the debugger the kiosk image opens on the loopback
# (nixie.kiosk.remoteDebugPort, which only that image sets) and walks the same
# steps, ending where the HTTP path ends: phase 3 done, ready to restart.
import asyncio, sys
from playwright.async_api import async_playwright

cdp = sys.argv[1]
shots = sys.argv[2]


async def shot(page, name):
    await page.wait_for_timeout(800)
    await page.screenshot(path=f"{shots}/kiosk-{name}.png")


async def main():
    async with async_playwright() as p:
        # The kiosk's own browser, not one started here: what is driven is
        # what is on the screen.
        browser = await p.chromium.connect_over_cdp(cdp)
        context = browser.contexts[0]
        page = context.pages[0] if context.pages else await context.new_page()
        # It pairs itself with the token the setup service leaves for it, so
        # there is no code to type and the first step is already showing.
        await page.wait_for_selector(".wizard-foot .btn.primary", timeout=300000)
        await shot(page, "machine")

        # The foot's primary button is the step's advance, whatever it is
        # labelled: on the last step before Review it is not "Next".
        nxt = ".wizard-foot .btn.primary"
        await page.click(nxt)
        await page.wait_for_selector("input[name=disk]", timeout=60000)
        await shot(page, "disks")
        # The first radio is whatever the kernel lists first; name the disk
        # this machine is meant to be installed on.
        await page.click('label:has-text("nixie-system") input[name=disk]')
        await page.click("input[type=checkbox]")
        await page.click(nxt)

        await page.fill("input[placeholder*=lowercase]", "server")
        await page.click(nxt)

        # Security carries the administrator too: Next stays disabled until
        # the name and both secrets are there.
        await page.fill('.field:has-text("Administrator name") input', "admin")
        await page.fill('.field:has-text("Administrator password") input', "nixie")
        await page.fill('.field:has-text("Disk passphrase") input', "hunter2")
        await page.click(nxt)
        await shot(page, "network")

        # Network, then Services, then Review: two advances, and the step
        # heading is printed after each so a wrong count says so here
        # instead of timing out fifteen minutes later on a selector.
        for step in ("services", "review"):
            await page.click(nxt)
            await page.wait_for_timeout(1500)
            print("now on:", (await page.inner_text("h1")).strip(), flush=True)

        # Review writes the site and evaluates the host before Install unlocks.
        try:
            await page.wait_for_selector(".status.ok", timeout=900000)
        except Exception:
            await shot(page, "review-stuck")
            print("REVIEW DID NOT PASS:",
                  repr(await page.evaluate("document.body.innerText"))[:2000], flush=True)
            raise
        await shot(page, "review")
        await page.click('button:has-text("Continue to install")')
        await page.click('button.btn.primary:has-text("Install")')
        await page.wait_for_timeout(4000)
        await shot(page, "installing")

        for _ in range(240):
            if await page.query_selector('button:has-text("Restart now")'):
                await shot(page, "installed")
                print("the kiosk drove the wizard to a finished install", flush=True)
                return
            await page.wait_for_timeout(5000)
        print(
            "THE KIOSK NEVER REACHED A FINISHED INSTALL:",
            repr(await page.evaluate("document.body.innerText"))[-2000:],
            flush=True,
        )
        raise SystemExit(1)


asyncio.run(main())
