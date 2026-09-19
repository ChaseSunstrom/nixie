# Every screen of the control panel, in all three finishes, from demo mode.
#
# The brief asks for these to be generated in CI, and demo mode is what makes
# that possible: the panel is a static bundle, and with ?demo it answers
# itself from seeded data instead of a daemon, so there is no VM, no
# certificate and nothing to install. The shots that need a real daemon are
# the media runs, which want KVM and stay out of CI.
import asyncio, functools, http.server, os, socketserver, sys, threading
from playwright.async_api import async_playwright

bundle = sys.argv[1]
out = sys.argv[2]
# The design file, photographed beside the screens built from it: the brief
# calls it the visual source of truth, and comparing the two is a person's
# judgement -- which is easier when both are in one folder. Its colours are
# held to the bundle's by the tokens-from-design check; what the pictures
# add is everything a colour is not, the layout and the type and the depth.
design = sys.argv[3] if len(sys.argv) > 3 else None
FINISHES = ["graphite", "umber", "paper"]
SCREENS = [
    "overview",
    "machines",
    "instances",
    "instances/web",
    "instances/web/snapshots",
    "instances/web/metrics",
    "images",
    "profiles",
    "networks",
    "storage",
    "operations",
    "dashboards",
    "history",
    "settings",
]


class Quiet(http.server.SimpleHTTPRequestHandler):
    # One line per request would bury whatever actually goes wrong.
    def log_message(self, *a):
        pass


def serve(directory):
    """A directory on a port of its own, so the page is loaded the way a
    browser loads it rather than from a file:// URL, where the panel's own
    fetches would be refused."""
    handler = functools.partial(Quiet, directory=directory)
    httpd = socketserver.TCPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd.server_address[1]


async def shoot_design(browser):
    """The design file itself, once per finish, whole."""
    port = serve(design)
    page = await (await browser.new_context(viewport={"width": 1440, "height": 900})).new_page()
    problems = []
    page.on("pageerror", lambda e: problems.append(str(e)))
    await page.goto(f"http://127.0.0.1:{port}/Nixie%20Front%20Panel.html", wait_until="networkidle")
    await page.wait_for_timeout(2500)
    for finish in FINISHES:
        button = page.locator(f'button:has-text("{finish.capitalize()}")').first
        await button.click()
        # Its own switch, so wait for the page to say it took rather than
        # for a length of time.
        await page.wait_for_function(
            "name => [...document.querySelectorAll('button')].some(b => b.textContent.trim().startsWith(name) && b.getAttribute('aria-pressed') === 'true')",
            arg=finish.capitalize(),
            timeout=15000,
        )
        await page.wait_for_timeout(800)
        await page.screenshot(path=f"{out}/design-{finish}.png", full_page=True)
    assert not problems, f"the design file raised {problems[:3]}"
    return len(FINISHES)


async def main():
    port = serve(bundle)
    base = f"http://127.0.0.1:{port}/"
    os.makedirs(out, exist_ok=True)
    taken = 0
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        for finish in FINISHES:
            context = await browser.new_context(viewport={"width": 1440, "height": 900})
            page = await context.new_page()
            problems = []
            page.on("pageerror", lambda e: problems.append(str(e)))
            # ?demo is what the panel reads to answer itself; the finish is
            # a browser choice, so it is set before anything is drawn.
            await page.goto(base + "?demo")
            await page.evaluate(f"localStorage.setItem('nixie.finish', '{finish}')")
            # The panel reads that choice once, as it starts: without this
            # every finish came out looking like the one before it.
            await page.reload()
            await page.wait_for_timeout(500)
            for screen in SCREENS:
                await page.goto(f"{base}?demo#/{screen}")
                await page.wait_for_timeout(1200)
                name = screen.replace("/", "-")
                await page.screenshot(path=f"{out}/panel-{name}-{finish}.png")
                taken += 1
            await context.close()
            # A screen that threw is a screen whose picture is a lie.
            assert not problems, f"{finish}: the page raised {problems[:3]}"
        if design:
            taken += await shoot_design(browser)
        await browser.close()
    print(f"{taken} screenshots in {out}")


asyncio.run(main())
