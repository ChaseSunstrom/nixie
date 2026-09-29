# The lock in front of the local control panel (modules/console.nix).
#
# The kiosk browser only ever talks to this process, on the loopback. Locked,
# it gets the lock page; unlocked with the administrator's password (and the
# authenticator code when the second factor is on), it gets the panel in a
# frame, and every request the panel makes is passed to incusd over its unix
# socket, which trusts root. So the kiosk needs no client certificate, and
# once the session ends -- idle, or the Lock button -- the panel's requests
# stop working at once, not only when the page notices.
#
# Nothing here may end in an empty response or a browser error page: the
# kiosk has no address bar and no back button, so a person would be stuck.
import base64
import hashlib
import hmac
import http.cookies
import http.server
import json
import os
import secrets
import selectors
import socket
import struct
import subprocess
import sys
import threading
import time
import urllib.parse

# The secret file is "none" when the site has no second factor.
ADMIN, IDLE, TOTP_FILE, LOCK_PAGE, PANEL_PAGE, INCUS = sys.argv[1:7]
IDLE = int(IDLE)
TOTP_FILE = "" if TOTP_FILE == "none" else TOTP_FILE
PORT = 9444
COOKIE = "nixie-kiosk"
SESSIONS = {}  # token -> time of the last sign of a person
GUARD = threading.Lock()
SLOW = threading.Lock()  # a refusal is slow, and one at a time
LAST_STEP = [0]  # an authenticator code is good once
WRONG = "That password or code is not right."


def page(path):
    with open(path, "rb") as f:
        return f.read()


def totp_ok(code):
    """The authenticator code, checked against the enrolled secret: this
    step, or the one either side of it for a clock a little off."""
    with open(TOTP_FILE) as f:
        secret = f.read().strip().replace(" ", "").upper()
    key = base64.b32decode(secret + "=" * (-len(secret) % 8))
    now = int(time.time()) // 30
    for step in (now - 1, now, now + 1):
        h = hmac.new(key, struct.pack(">Q", step), hashlib.sha1).digest()
        o = h[-1] & 15
        value = (struct.unpack(">I", h[o:o + 4])[0] & 0x7FFFFFFF) % 1000000
        if hmac.compare_digest(f"{value:06d}", code):
            with GUARD:
                if step <= LAST_STEP[0]:
                    return False
                LAST_STEP[0] = step
            return True
    return False


def password_ok(password):
    # pam_unix's helper reads the password from stdin, so no terminal is
    # needed; as root it may check another account's.
    r = subprocess.run(["/run/wrappers/bin/unix_chkpwd", ADMIN, "nonull"],
                       input=password.encode() + b"\0", capture_output=True)
    return r.returncode == 0


def unlock(password, code):
    """None when the panel may open, otherwise what to tell the person."""
    if TOTP_FILE:
        if not os.path.exists(TOTP_FILE):
            # Never open without the second factor the site asked for.
            return ("The second factor's secret did not install on this machine, so the panel stays locked. "
                    "Log in at Ctrl+Alt+F2 and look at the site's secrets (totp-secret).")
        if not code.strip():
            return "The code from the authenticator app is needed too."
    # The code only after the password: a code is good once, and a typo in
    # the password must not spend it.
    ok = password_ok(password) and (not TOTP_FILE or totp_ok(code.strip()))
    return None if ok else WRONG


def splice(a, b, alive):
    """Copy both ways until either side closes, or the session ends."""
    sel = selectors.DefaultSelector()
    sel.register(a, selectors.EVENT_READ, b)
    sel.register(b, selectors.EVENT_READ, a)
    try:
        while alive():
            for key, _ in sel.select(timeout=5):
                data = key.fileobj.recv(65536)
                if not data:
                    return
                key.data.sendall(data)
    except OSError:
        pass
    finally:
        sel.close()


class Gate(http.server.BaseHTTPRequestHandler):
    server_version = "nixie-kiosk-gate"
    # Unbuffered, so nothing past the request's head is read into Python's
    # buffer: the body, or a websocket's frames, are passed on as they come.
    rbufsize = 0

    def log_message(self, fmt, *args):
        pass

    def token(self):
        c = http.cookies.SimpleCookie(self.headers.get("Cookie") or "")
        return c[COOKIE].value if COOKIE in c else None

    def alive(self, tok):
        with GUARD:
            last = SESSIONS.get(tok)
            if last is None:
                return False
            if time.time() - last > IDLE:
                SESSIONS.pop(tok, None)
                return False
            return True

    def reply(self, status, body=b"", ctype="text/html; charset=utf-8", headers=()):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in headers:
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def json(self, obj, status=200, headers=()):
        self.reply(status, json.dumps(obj).encode(), "application/json", headers)

    def handle_one_request(self):
        try:
            super().handle_one_request()
        except Exception as e:  # noqa: BLE001 -- anything, rather than a dropped connection
            print(f"nixie-kiosk-gate: {type(e).__name__}: {e}", file=sys.stderr, flush=True)
            try:
                self.reply(500, page(LOCK_PAGE))
            except OSError:
                pass
            self.close_connection = True

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        tok = self.token()
        if path == "/":
            return self.reply(200, page(PANEL_PAGE if self.alive(tok) else LOCK_PAGE))
        if path == "/__nixie/state":
            with GUARD:
                left = IDLE - (time.time() - SESSIONS[tok]) if tok in SESSIONS else 0
            return self.json({"unlocked": self.alive(tok), "left": max(0, int(left))})
        return self.proxy(tok)

    do_HEAD = do_GET

    def do_POST(self):
        path = urllib.parse.urlsplit(self.path).path
        tok = self.token()
        if path == "/__nixie/unlock":
            n = int(self.headers.get("Content-Length") or 0)
            form = urllib.parse.parse_qs(self.rfile.read(n).decode(errors="replace"))
            why = unlock(form.get("password", [""])[0], form.get("code", [""])[0])
            wants_json = "application/json" in (self.headers.get("Accept") or "")
            if why:
                with SLOW:
                    time.sleep(2)
                if wants_json:
                    return self.json({"ok": False, "error": why}, 403)
                return self.reply(303, headers=[("Location", "/")])
            new = secrets.token_urlsafe(32)
            with GUARD:
                SESSIONS.clear()
                SESSIONS[new] = time.time()
            cookie = [("Set-Cookie", f"{COOKIE}={new}; Path=/; HttpOnly; SameSite=Strict")]
            if wants_json:
                return self.json({"ok": True}, headers=cookie)
            return self.reply(303, headers=[("Location", "/"), *cookie])
        if path == "/__nixie/active":
            if not self.alive(tok):
                return self.json({"unlocked": False}, 401)
            with GUARD:
                SESSIONS[tok] = time.time()
            return self.json({"unlocked": True})
        if path == "/__nixie/lock":
            with GUARD:
                SESSIONS.pop(tok, None)
            return self.json({"unlocked": False})
        return self.proxy(tok)

    def do_PUT(self):
        return self.proxy(self.token())

    do_PATCH = do_DELETE = do_PUT

    def proxy(self, tok):
        if not self.alive(tok):
            if self.command == "GET" and self.path.startswith("/ui"):
                # The frame after the lock: the whole page goes back to it.
                return self.reply(200, b'<script>top.location.replace("/")</script>')
            return self.json({"type": "error", "error": "locked", "error_code": 403}, 403)
        up = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            up.connect(INCUS)
        except OSError:
            up.close()
            return self.reply(502, b"<meta http-equiv=refresh content=5>The control panel's daemon is not answering yet; trying again.")
        upgrade = (self.headers.get("Upgrade") or "").lower() == "websocket"
        head = [f"{self.command} {self.path} HTTP/1.1"]
        for k, v in self.headers.items():
            # The session cookie stays here; the daemon has no use for it.
            if k.lower() not in ("cookie", "connection", "keep-alive", "proxy-connection"):
                head.append(f"{k}: {v}")
        # One request per connection, so the daemon's close ends the reply.
        head.append("Connection: Upgrade" if upgrade else "Connection: close")
        up.sendall(("\r\n".join(head) + "\r\n\r\n").encode("latin-1"))
        try:
            splice(self.connection, up, lambda: self.alive(tok))
        finally:
            up.close()
        self.close_connection = True


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    Server(("127.0.0.1", PORT), Gate).serve_forever()
