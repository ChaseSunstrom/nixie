# shellcheck shell=bash
exec python3 - "$@" <<'PY'
import http.server, subprocess, urllib.parse, os, time, sys
admin = sys.argv[1]; idle = int(sys.argv[2]); target = sys.argv[3]
state = {"unlocked": 0.0}
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if time.time() - state["unlocked"] < idle:
            state["unlocked"] = time.time()
            self.send_response(302); self.send_header("Location", target); self.end_headers(); return
        self.send_response(200); self.send_header("Content-Type", "text/html"); self.end_headers()
        self.wfile.write(open("@lockPage@", "rb").read())
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        f = urllib.parse.parse_qs(self.rfile.read(n).decode())
        pw = f.get("password", [""])[0]; code = f.get("code", [""])[0]
        ok = subprocess.run(["/run/wrappers/bin/unix_chkpwd", admin, "nullok"], input=pw + "\0", capture_output=True, text=True).returncode == 0
        if ok and os.path.exists("/run/nixie/oath/users"):
            ok = subprocess.run(["oathtool", "--totp", "-b", "-w", "1", open("/run/nixie/oath/secret").read().strip(), code], capture_output=True).returncode == 0
        if ok:
            state["unlocked"] = time.time()
            self.send_response(302); self.send_header("Location", target); self.end_headers()
        else:
            time.sleep(2); self.send_response(303); self.send_header("Location", "/"); self.end_headers()
http.server.HTTPServer(("127.0.0.1", 9444), H).serve_forever()
PY
