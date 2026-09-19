# Drive the wizard through the browser on the machine's own screen.
#
# `nixie-test-iso` otherwise talks to the setup backend over HTTP, which
# proves the phases but not the page a person at the machine actually uses:
# cage, chromium, the local token that pairs the kiosk without a code, and
# the wizard rendering inside all of that. This connects to that browser over
# the debugger the kiosk image opens on the loopback
# (nixie.kiosk.remoteDebugPort, which only that image sets) and walks the same
# steps, ending where the HTTP path ends: phase 3 done, ready to restart.
import asyncio, base64, hashlib, hmac, struct, sys, time
from playwright.async_api import async_playwright

cdp = sys.argv[1]
shots = sys.argv[2]
# What the person at the machine chooses on the Security step. A hardened
# setup turns on every feature the installer can, and asks for more than a
# plain one does, so the steps after it are walked rather than counted.
security = sys.argv[3] if len(sys.argv) > 3 else "plain"

# Everything this wizard can ask for, by the label above the box. The same
# secrets the HTTP path posts, so the two runs install the same machine.
ANSWERS = {
    "Administrator name": "admin",
    "Administrator password": "nixie",
    "Disk passphrase": "hunter2",
    "TPM PIN": "1234",
    "Duress passphrase": "wipe-me",
}


async def shot(page, name):
    await page.wait_for_timeout(800)
    await page.screenshot(path=f"{shots}/kiosk-{name}.png")


def code_for(secret):
    # RFC 6238, which is all an authenticator app does: the wizard shows the
    # secret beside the QR code for someone typing it in by hand.
    key = base64.b32decode(secret.replace(" ", "").upper() + "=" * (-len(secret) % 8))
    digest = hmac.new(key, struct.pack(">Q", int(time.time()) // 30), hashlib.sha1).digest()
    at = digest[-1] & 0x0F
    return f"{(struct.unpack('>I', digest[at:at + 4])[0] & 0x7FFFFFFF) % 1000000:06d}"


async def enrol_second_factor(page):
    # A hardened setup puts a second factor on the host page, and the step
    # will not advance until it is enrolled -- the one thing on it that is
    # not a box to fill in.
    show = page.locator('button:has-text("Show QR code")').first
    if not await show.count():
        return
    await show.click()
    shown = page.locator(".caption.mono").first
    await shown.wait_for(timeout=30000)
    secret = (await shown.inner_text()).strip()
    for _ in range(3):
        await page.fill('input[placeholder="code from the app"]', code_for(secret))
        await page.click('.btn.primary:has-text("Verify")')
        try:
            await page.wait_for_selector(".chip.ok", timeout=15000)
            print("  enrolled the second factor", flush=True)
            return
        except Exception:
            # A code that crossed its thirty-second window: the next one.
            await page.wait_for_timeout(5000)
    raise SystemExit("the second factor would not enrol")


async def answer(page):
    # Whatever this step is asking for that we know an answer to. Empty
    # boxes only: a step revisited must not have its answer typed twice.
    for label, value in ANSWERS.items():
        box = page.locator(f'.field:has-text("{label}") input').first
        if await box.count() and await box.is_visible() and not await box.input_value():
            await box.fill(value)
            print(f"  answered {label}", flush=True)


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
        # How much security is asked on this first step, beside which
        # profile: the two cards are here, not on the Security step that
        # carries out the answer, and a run that clicked past them installed
        # the other machine.
        card = "Hardened" if security == "hardened" else "Standard"
        picked = page.locator(f'button.card:has-text("{card}")').first
        await picked.wait_for(timeout=60000)
        await picked.click()
        await page.wait_for_timeout(500)
        print(f"chose {card}", flush=True)
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

        # How much security, which is a choice of two cards. A hardened setup
        # then walks through every feature it turns on and asks for what each
        # one needs, so from here the steps are walked to Review rather than
        # counted: the count is not the same for the two answers.
        for _ in range(25):
            head = (await page.inner_text("h1")).strip()
            print("now on:", head, flush=True)
            if head.lower().startswith("review"):
                break
            await answer(page)
            if head.lower().startswith("security"):
                await enrol_second_factor(page)
                await shot(page, "security")
            if head.lower().startswith("network"):
                await shot(page, "network")
            await page.click(nxt)
            await page.wait_for_timeout(1500)
        else:
            raise SystemExit("the wizard never reached Review")

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
