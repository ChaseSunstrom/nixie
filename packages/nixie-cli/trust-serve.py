# `nixie panel trust`'s way off the machine: the browser certificate it just
# made, handed once to whoever types the code it printed, then gone.
#
# It answers on the setup port with incusd's own certificate, so the address
# a browser accepts here is the one it accepts for the control panel. Exit
# status: 0 the file was fetched, 1 nobody fetched it in time, 3 too many
# wrong codes.
import argparse
import hmac
import html
import http.server
import os
import secrets
import ssl
import sys
import threading
import time
import urllib.parse

ap = argparse.ArgumentParser()
for a in ("p12", "cert", "key", "host", "panel", "name"):
    ap.add_argument(f"--{a}", required=True)
ap.add_argument("--port", type=int, default=9443)
ap.add_argument("--timeout", type=int, default=600)
ARGS = ap.parse_args()
# In the environment, which only root can read, rather than on the command
# line, which anyone on the machine can: the code is the whole way in.
ARGS.code = os.environ.pop("NIXIE_TRUST_CODE")
ARGS.password = os.environ.pop("NIXIE_TRUST_PASSWORD")

FETCH = secrets.token_urlsafe(24)  # the download link, given out with the password
STATE = {"wrong": 0, "fetched": None}
GUARD = threading.Lock()
MAX_WRONG = 10
FILE = f"nixie-{ARGS.host}.p12"

STYLE = """<style>
*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#1c1f24;color:#e8e6e1;font:15px/1.55 system-ui,sans-serif}
main{width:min(560px,100% - 32px);background:#252930;border:1px solid #3a3f48;border-radius:14px;padding:28px}
h1{margin:0 0 8px;font-size:22px;font-weight:500}p,li{color:#b9b6ae}code,.pw{font-family:ui-monospace,monospace;color:#e8e6e1}
.pw{font-size:22px;letter-spacing:.06em;background:#1c1f24;border:1px solid #3a3f48;border-radius:6px;padding:8px 12px;display:inline-block}
input{background:#1c1f24;border:1px solid #3a3f48;border-radius:6px;color:#e8e6e1;height:40px;padding:0 12px;font:20px ui-monospace,monospace;width:10ch;letter-spacing:.2em}
a.btn,button{display:inline-block;height:40px;line-height:40px;padding:0 16px;background:#5b7fd0;border:0;border-radius:6px;color:#fff;font:inherit;text-decoration:none;cursor:pointer}
.err{color:#f08a86}ol{padding-left:20px}
</style>"""


def page(body):
    return f"<!doctype html><meta charset=utf-8><meta name=viewport content='width=device-width'><title>nixie: this browser's certificate</title>{STYLE}<main>{body}</main>".encode()


def ask(err=""):
    return page(f"""<h1>A certificate for this browser</h1>
<p>It lets this browser open the control panel of <b>{html.escape(ARGS.host)}</b>. Type the code <code>nixie panel trust</code> printed on the machine.</p>
<form method=post action=/><input name=code inputmode=numeric autocomplete=off maxlength=6 autofocus> <button>Continue</button></form>
<p class=err>{html.escape(err)}</p>""")


def given():
    return page(f"""<h1>Your certificate</h1>
<p><a class=btn href="/{FETCH}/{FILE}" download>Download {html.escape(FILE)}</a></p>
<p>Its password, asked for when you import it:</p><p class=pw>{html.escape(ARGS.password)}</p>
<ol>
<li>Import the file into this browser.<br>
Chrome and Edge: Settings › Privacy and security › Security › Manage certificates › Your certificates › Import.<br>
Firefox: Settings › Privacy &amp; Security › Certificates › View Certificates › Your Certificates › Import.<br>
Safari: open the file; it goes into the keychain.</li>
<li>Open <a href="{html.escape(ARGS.panel)}">{html.escape(ARGS.panel)}</a>, and choose the nixie certificate when the browser asks which one to use.</li>
</ol>
<p>This page stops answering a minute after the download. <code>sudo nixie panel forget {html.escape(ARGS.name)}</code> on the machine takes the certificate's access away again.</p>""")


class H(http.server.BaseHTTPRequestHandler):
    server_version = "nixie-trust"

    def log_message(self, fmt, *args):
        pass

    def send(self, status, body, ctype="text/html; charset=utf-8", extra=()):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in extra:
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        if path == f"/{FETCH}/{FILE}":
            with open(ARGS.p12, "rb") as f:
                data = f.read()
            with GUARD:
                STATE["fetched"] = STATE["fetched"] or time.time()
            print(f"fetched by {self.client_address[0]}", flush=True)
            return self.send(200, data, "application/x-pkcs12", [("Content-Disposition", f'attachment; filename="{FILE}"')])
        return self.send(200, ask())

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        code = urllib.parse.parse_qs(self.rfile.read(min(n, 1024)).decode(errors="replace")).get("code", [""])[0].strip()
        if hmac.compare_digest(code, ARGS.code):
            return self.send(200, given())
        with GUARD:
            STATE["wrong"] += 1
            wrong = STATE["wrong"]
        print(f"a wrong code from {self.client_address[0]} ({wrong} of {MAX_WRONG})", flush=True)
        time.sleep(1)
        return self.send(403, ask("That is not the code on the machine."))


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main():
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(ARGS.cert, ARGS.key)
    srv = Server(("0.0.0.0", ARGS.port), H)
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    end = time.time() + ARGS.timeout
    while True:
        time.sleep(0.5)
        with GUARD:
            fetched, wrong = STATE["fetched"], STATE["wrong"]
        # A minute for a second try, if the first download went astray.
        if fetched and time.time() - fetched > 60:
            rc = 0
            break
        if wrong >= MAX_WRONG:
            rc = 3
            break
        if not fetched and time.time() > end:
            rc = 1
            break
    srv.shutdown()
    return rc


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(1)
