# Declare, from the panel: whether it is offered, and where it goes.
#
# incusd serves this panel and runs no host command, so Declare hands the
# instance's name to the host page, which does (D16). The half that runs the
# command is vm-guests; the half checked here is the one a person clicks --
# offered for a scratch instance and not for a declared one, and opening the
# host page's own address with that name on it. Demo mode makes it a page on
# a port rather than a machine: no daemon, no VM, no certificate.
import asyncio
import functools
import http.server
import json
import socketserver
import sys
import threading

from playwright.async_api import async_playwright

root = sys.argv[1]
HOST_UI = ":9090"


def site(**over):
    base = {
        "theme": "graphite",
        "host": "server",
        "machines": [],
        "tokens": {},
        "links": [],
        # One guest the site declares; everything else demo mode seeds is a
        # scratch instance, which is what Declare is for.
        "declared": {"web": {"kind": "nixos", "ip": None, "image": "nixie/web/x"}},
        "allowSiteEdits": True,
        "hostUiUrl": HOST_UI,
    }
    base.update(over)
    json.dump(base, open(f"{root}/nixie.json", "w"))


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def end_headers(self):
        # The site file is rewritten between loads, and a browser that keeps
        # the first one reads the same answer every time.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


async def main():
    handler = functools.partial(Quiet, directory=root)
    httpd = socketserver.TCPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{httpd.server_address[1]}/?demo#/instances"

    async with async_playwright() as p:
        # --no-sandbox: this runs inside a build, which has no user
        # namespaces of its own to give the browser.
        browser = await p.chromium.launch(args=["--no-sandbox"])
        page = await (await browser.new_context(viewport={"width": 1440, "height": 900})).new_page()
        problems = []
        page.on("pageerror", lambda e: problems.append(str(e)))
        # The panel opens the host page in a window of its own; this records
        # the address instead of opening it.
        await page.add_init_script("window.__opened = []; window.open = (u) => { window.__opened.push(u); return null; };")

        site()
        await page.goto(base)
        await page.wait_for_selector(".chip")
        await page.wait_for_timeout(500)
        scratch = await page.locator('.chip:text-is("scratch")').count()
        declared = await page.locator('.chip:text-is("declared")').count()
        buttons = page.locator('button:text-is("Declare")')
        assert scratch and declared, f"demo mode showed {scratch} scratch and {declared} declared"
        # Offered for every scratch instance and for none of the declared
        # ones: `apply` is what owns a declared guest, and declaring it twice
        # is a site that does not evaluate.
        assert await buttons.count() == scratch, f"{await buttons.count()} buttons for {scratch} scratch instances"

        await buttons.first.click()
        opened = await page.evaluate("window.__opened")
        assert len(opened) == 1, opened
        want = f"https://127.0.0.1{HOST_UI}/nixie-history#declare="
        assert opened[0].startswith(want), f"{opened[0]} does not start with {want}"
        name = opened[0][len(want):]
        assert name and "/" not in name, opened[0]
        print(f"Declare opened the host page for {name}")

        # And with no host page, or a site that is not to be edited from
        # here, there is nothing to click: the panel cannot run the command
        # itself either way.
        for off in ({"hostUiUrl": None}, {"allowSiteEdits": False}):
            site(**off)
            await page.reload()
            await page.wait_for_selector(".chip")
            await page.wait_for_timeout(500)
            assert await buttons.count() == 0, f"Declare was offered with {off}"
            print(f"with {off}: no Declare, as there is nothing behind it")

        assert not problems, f"the page raised {problems[:3]}"
        await browser.close()


asyncio.run(main())
