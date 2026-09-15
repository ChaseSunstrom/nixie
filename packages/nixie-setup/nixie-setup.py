#!/usr/bin/env python3
"""The installer backend: one process, standard library only.

Serves the wizard bundle and a small JSON API over TLS on the setup port,
pairs browsers with a single-use code, holds secrets in memory until a phase
needs them, and runs the phase scripts with their output streamed back. The
same program runs on the ISO (phases 1-3) and in the setup generation after
the first reboot (phases 4-8); the wizard never does anything the CLI cannot.
"""
import argparse, base64, hashlib, hmac, http.cookies, http.server, json, os, secrets, shutil, socket, ssl, struct, subprocess, sys, tarfile, tempfile, threading, time, urllib.parse

ARGS = None
SESSIONS = set()
PAIR_CODE = None
FINISH_STARTED = None
SECRETS = {}           # name -> bytes, in memory only
LOCK = threading.Lock()
RUNNING = None         # currently running phase subprocess
TOTP = {}              # pending TOTP enrolment


def log(msg):
    print(f"[nixie-setup] {msg}", file=sys.stderr, flush=True)


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


# ---------------------------------------------------------------- nix text
def to_nix(v, indent=0):
    pad = "  " * indent
    if isinstance(v, bool):
        return "true" if v else "false"
    if v is None:
        return "null"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        # JSON's escapes are Nix's, except that Nix would interpolate ${ and
        # does not know \u.
        return json.dumps(v, ensure_ascii=False).replace("${", "\\${")
    if isinstance(v, list):
        if not v:
            return "[ ]"
        return "[\n" + "".join(f"{pad}  {to_nix(x, indent + 1)}\n" for x in v) + f"{pad}]"
    if isinstance(v, dict):
        if not v:
            return "{ }"
        out = "{\n"
        for k, x in v.items():
            key = k if k.replace("_", "a").replace("-", "a").isalnum() and not k[0].isdigit() else json.dumps(k)
            out += f"{pad}  {key} = {to_nix(x, indent + 1)};\n"
        return out + f"{pad}}}"
    raise TypeError(type(v))


# ------------------------------------------------------------------ state
def state_path():
    return os.path.join(ARGS.state_dir, "state.json")


def read_state():
    try:
        with open(state_path()) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def write_state(s):
    os.makedirs(ARGS.state_dir, exist_ok=True)
    with open(state_path() + ".new", "w") as f:
        json.dump(s, f, indent=2)
    os.replace(state_path() + ".new", state_path())


def markers():
    return sorted(int(f[:-5]) for f in os.listdir(ARGS.state_dir) if f.endswith(".done")) if os.path.isdir(ARGS.state_dir) else []


def keys_dir():
    d = "/run/nixie/keys"
    os.makedirs(d, mode=0o700, exist_ok=True)
    os.chmod(d, 0o700)
    return d


def materialise_secrets():
    """Phases read secrets as files on a root-only tmpfs; written only when a
    phase is about to run and removed when setup finishes."""
    d = keys_dir()
    for name, value in SECRETS.items():
        fd = os.open(os.path.join(d, name), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "wb") as f:
            f.write(value)
    if ARGS.age_key and not os.path.exists(os.path.join(d, "age.key")):
        shutil.copy(ARGS.age_key, os.path.join(d, "age.key"))
        os.chmod(os.path.join(d, "age.key"), 0o600)


# ------------------------------------------------------------------- TOTP
def totp_code(secret_b32, t=None):
    key = base64.b32decode(secret_b32 + "=" * (-len(secret_b32) % 8))
    counter = int((t or time.time()) // 30)
    mac = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    off = mac[-1] & 0xF
    return str((struct.unpack(">I", mac[off : off + 4])[0] & 0x7FFFFFFF) % 1000000).zfill(6)


def qr_text(data):
    r = sh(["qrencode", "-t", "UTF8", "-m", "1", data])
    return r.stdout if r.returncode == 0 else ""


# ------------------------------------------------------------------- site
def site_new(host, profile, settings, platform):
    site = ARGS.site
    if not os.path.exists(os.path.join(site, "site.nix")):
        shutil.copytree(ARGS.template, site, dirs_exist_ok=True)
        # The template comes from the read-only store and copytree keeps its
        # modes; the site is for editing.
        sh(["chmod", "-R", "u+w", site])
        for p in ("site.nix", "flake.nix", ".sops.yaml"):
            try:
                os.remove(os.path.join(site, p))
            except FileNotFoundError:
                pass
        shutil.rmtree(os.path.join(site, "hosts"), ignore_errors=True)
        shutil.rmtree(os.path.join(site, "secrets"), ignore_errors=True)
        with open(os.path.join(site, "flake.nix"), "w") as f:
            f.write(
                "{\n  description = \"Nixie site\";\n"
                f"  inputs.nixie.url = {json.dumps(platform)};\n"
                "  outputs = { nixie, ... }: nixie.lib.mkSite ./site.nix;\n}\n"
            )
    hosts = {}
    sp = os.path.join(site, "site.nix")
    if os.path.exists(sp):
        # Keep other hosts: the file is data, re-emitted with this host replaced.
        r = sh(["nix", "eval", "--json", "--file", sp, "hosts"], cwd=site)
        if r.returncode == 0:
            hosts = {k: None for k in json.loads(r.stdout)}
    hdir = os.path.join(site, "hosts", host)
    os.makedirs(hdir, exist_ok=True)
    os.makedirs(os.path.join(site, "secrets"), exist_ok=True)
    with open(os.path.join(hdir, "setup-pending.nix"), "w") as f:
        f.write("# Managed by setup: true until Finish, then empty.\n{ nixie.setup.pending = true; }\n")
    entry = (
        "  hosts." + host + " = {\n"
        f"    hardware = ./hosts/{host}/hardware.nix;\n"
        f"    secrets = ./secrets/{host}.yaml;\n"
        "    guests = import ./guests.nix;\n    data = import ./data.nix;\n"
        f"    settings = {{\n      imports = [ ./hosts/{host}/setup-pending.nix ];\n"
        + "".join(f"      {k} = {to_nix(v, 3)};\n" for k, v in sorted(settings.items()))
        + "    };\n  };\n"
    )
    others = ""
    if hosts and os.path.exists(sp):
        # Preserve the other hosts' text verbatim by keeping the old file as a module.
        old = os.path.join(site, f"site-{int(time.time())}.nix.bak")
        shutil.move(sp, old)
        others = f"  # previous hosts kept in {os.path.basename(old)}; merge by hand\n"
    with open(sp, "w") as f:
        f.write("# Plain data. One entry per machine.\n{\n" + others + entry + "}\n")
    if not os.path.exists(os.path.join(site, ".git")):
        sh(["git", "init", "-q"], cwd=site)
        sh(["git", "config", "user.email", "nixie@localhost"], cwd=site)
        sh(["git", "config", "user.name", "nixie setup"], cwd=site)
    sh(["git", "add", "-A"], cwd=site)
    sh(["git", "commit", "-qm", f"setup: host {host}"], cwd=site)


def apply_config(b):
    """The wizard's choices become state.json and the site's host entry. The
    web wizard posts them to /api/config; the terminal wizard pipes the same
    JSON to --configure, so both write the site the same way."""
    host = b["host"]
    write_state({
        "host": host,
        "profile": b["profile"],
        "systemDisk": b["systemDisk"],
        "dataDisk": b.get("dataDisk"),
        "uplinks": b.get("uplinks", []),
        "gpu": b.get("gpu", "none"),
        "tpm": b.get("tpm", False),
        "hostId": b.get("hostId"),
        "options": {"secureBoot": bool(b.get("settings", {}).get("nixie.security.secureBoot.enable"))},
    })
    settings = dict(b.get("settings", {}))
    settings["nixie.profile"] = b["profile"]
    settings["nixie.host.name"] = host
    # An existing site already declares the host; phase 1 only (re)writes hardware.nix.
    if not b.get("existingSite"):
        site_new(host, b["profile"], settings, ARGS.platform)


# ------------------------------------------------------------- HTTP server
class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "nixie-setup"

    def log_message(self, fmt, *args):  # quiet
        pass

    # helpers
    def send_json(self, obj, status=200, session=False):
        body = json.dumps(obj).encode()
        self.send_response(status)
        if session:
            self.set_session()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}") if n else {}

    def session(self):
        c = http.cookies.SimpleCookie(self.headers.get("Cookie"))
        tok = c["nixie-session"].value if "nixie-session" in c else None
        return tok if tok in SESSIONS else None

    def set_session(self):
        tok = secrets.token_urlsafe(32)
        SESSIONS.add(tok)
        self.send_header("Set-Cookie", f"nixie-session={tok}; Path=/; Secure; HttpOnly; SameSite=Strict")

    def static(self, path):
        p = os.path.normpath(os.path.join(ARGS.static, path.lstrip("/"))) if path != "/" else os.path.join(ARGS.static, "index.html")
        if not p.startswith(ARGS.static) or not os.path.isfile(p):
            p = os.path.join(ARGS.static, "index.html")
        ctype = {".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".ttf": "font/ttf", ".svg": "image/svg+xml"}.get(os.path.splitext(p)[1], "application/octet-stream")
        with open(p, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    # routes
    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if u.path.startswith("/api/"):
            if u.path == "/api/pair":
                return self.send_json({"needsCode": True, "mode": ARGS.mode, "host": socket.gethostname()})
            if not self.session():
                # The kiosk on the machine itself pairs with the local token.
                if "token" in q and os.path.exists(ARGS.local_token) and hmac.compare_digest(open(ARGS.local_token).read().strip(), q["token"][0]):
                    self.send_response(204)
                    self.set_session()
                    self.end_headers()
                    return
                return self.send_json({"error": "not paired"}, 401)
            return self.api_get(u.path, q)
        if "token" in q and os.path.exists(ARGS.local_token) and hmac.compare_digest(open(ARGS.local_token).read().strip(), q["token"][0]):
            self.send_response(302)
            self.set_session()
            self.send_header("Location", "/")
            self.end_headers()
            return
        return self.static(u.path)

    def api_get(self, path, q):
        if path == "/api/state":
            st = read_state()
            return self.send_json({"mode": ARGS.mode, "state": st, "done": markers(), "host": socket.gethostname(), "secrets": sorted(SECRETS), "layout": self.layout()})
        if path == "/api/hardware":
            r = sh(["nixie-discover"])
            return self.send_json(json.loads(r.stdout) if r.returncode == 0 else {"error": r.stderr})
        if path == "/api/finish":
            # Finish runs as a unit of its own; what it printed since the
            # button was pressed is how a failure reaches the page.
            if FINISH_STARTED is None:
                return self.send_json({"failed": False, "lines": []})
            out = sh(["journalctl", "-u", "nixie-finish", "--since", f"@{FINISH_STARTED}", "-o", "cat", "--no-pager"]).stdout.splitlines()
            return self.send_json({"failed": any("nixie-finish.service: Failed" in l for l in out), "lines": out[-20:]})
        if path == "/api/options":
            with open(ARGS.options) as f:
                return self.send_json(json.load(f))
        if path == "/api/plan":
            st = read_state()
            hw = ""
            hp = os.path.join(ARGS.site, "hosts", st.get("host", ""), "hardware.nix")
            if os.path.exists(hp):
                hw = open(hp).read()
            sp = os.path.join(ARGS.site, "site.nix")
            return self.send_json({"hardware": hw, "site": open(sp).read() if os.path.exists(sp) else ""})
        if path == "/api/totp/new":
            secret = base64.b32encode(secrets.token_bytes(20)).decode().rstrip("=")
            TOTP["secret"] = secret
            label = f"nixie:{read_state().get('host', socket.gethostname())}"
            uri = f"otpauth://totp/{urllib.parse.quote(label)}?secret={secret}&issuer=nixie"
            return self.send_json({"secret": secret, "uri": uri, "qr": qr_text(uri)})
        if path == "/api/attestation":
            p = os.path.join(keys_dir(), "attestation-qr")
            r = os.path.join(keys_dir(), "recovery-key")
            key = open(r).read().strip() if os.path.exists(r) else ""
            return self.send_json({"text": open(p).read() if os.path.exists(p) else "", "recovery": key, "recoveryQr": qr_text(key) if key else ""})
        if path == "/api/download/header-backup":
            p = os.path.join(ARGS.state_dir, "header-backup.tar.age")
            if not os.path.exists(p):
                return self.send_json({"error": "no bundle yet"}, 404)
            data = open(p, "rb").read()
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Disposition", f"attachment; filename=nixie-{read_state().get('host','host')}-headers.tar.age")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            return self.wfile.write(data)
        if path == "/api/banner":
            p = os.path.join(ARGS.state_dir, "banner.txt")
            return self.send_json({"text": open(p).read() if os.path.exists(p) else "", "code": PAIR_CODE})
        if path == "/api/log":
            p = os.path.join(ARGS.state_dir, "setup.log")
            return self.send_json({"log": open(p).read()[-20000:] if os.path.exists(p) else ""})
        return self.send_json({"error": "not found"}, 404)

    def layout(self):
        p = "/run/current-system/etc/nixie/layout.json"
        try:
            with open(p) as f:
                return json.load(f)
        except OSError:
            return None

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        if u.path == "/api/pair":
            global PAIR_CODE
            b = self.body()
            if PAIR_CODE and hmac.compare_digest(str(b.get("code", "")), PAIR_CODE):
                PAIR_CODE = None  # single use
                # Framed with Content-Length: curl over TLS treats an EOF-delimited
                # body as an unexpected close and fails the request.
                return self.send_json({"ok": True}, session=True)
            return self.send_json({"error": "wrong or used code"}, 403)
        if not self.session():
            return self.send_json({"error": "not paired"}, 401)
        b = self.body()
        if u.path == "/api/config":
            return self.configure(b)
        if u.path == "/api/secrets":
            with LOCK:
                for k, v in b.items():
                    if v:
                        SECRETS[k] = v.encode()
            return self.send_json({"ok": True, "have": sorted(SECRETS)})
        if u.path == "/api/totp/verify":
            if "secret" in TOTP and hmac.compare_digest(totp_code(TOTP["secret"]), str(b.get("code", ""))):
                SECRETS["totp-secret"] = TOTP["secret"].encode()
                return self.send_json({"ok": True})
            return self.send_json({"ok": False}, 400)
        if u.path.startswith("/api/phase/"):
            return self.run_phase(int(u.path.rsplit("/", 1)[1]), b)
        if u.path == "/api/site":
            return self.site(b)
        if u.path == "/api/reboot":
            self.send_json({"ok": True})
            threading.Timer(1.0, reboot).start()
            return
        if u.path == "/api/finish":
            return self.api_finish()
        return self.send_json({"error": "not found"}, 404)

    def site(self, b):
        mode = b.get("mode", "new")
        os.makedirs(os.path.dirname(ARGS.site.rstrip("/")), exist_ok=True)
        if mode == "clone":
            if os.path.exists(ARGS.site):
                shutil.rmtree(ARGS.site)
            r = sh(["git", "clone", "-q", b["url"], ARGS.site])
            if r.returncode:
                return self.send_json({"error": r.stderr}, 400)
        elif mode == "upload":
            data = base64.b64decode(b["tarball"])
            if os.path.exists(ARGS.site):
                shutil.rmtree(ARGS.site)
            os.makedirs(ARGS.site)
            with tarfile.open(fileobj=__import__("io").BytesIO(data)) as t:
                t.extractall(ARGS.site, filter="data")
        hosts = []
        sp = os.path.join(ARGS.site, "site.nix")
        if os.path.exists(sp):
            r = sh(["nix", "eval", "--json", "--file", sp, "hosts"], cwd=ARGS.site)
            hosts = list(json.loads(r.stdout)) if r.returncode == 0 else []
        return self.send_json({"ok": True, "hosts": hosts})

    def configure(self, b):
        apply_config(b)
        return self.send_json({"ok": True})

    def run_phase(self, n, b):
        global RUNNING
        with LOCK:
            if RUNNING and RUNNING.poll() is None:
                return self.send_json({"error": "a phase is running"}, 409)
            materialise_secrets()
            env = dict(os.environ, NIXIE_SITE=ARGS.site, NIXIE_SETUP_DIR=ARGS.state_dir, NIXIE_KEYS=keys_dir())
            if ARGS.toplevel:
                env["NIXIE_TOPLEVEL"] = ARGS.toplevel
            if ARGS.disko:
                env["NIXIE_DISKO"] = ARGS.disko
            extra = []
            if n == 6 and b.get("backupDest"):
                extra = ["--backup-dest", b["backupDest"]]
            RUNNING = subprocess.Popen(["nixie-phase", str(n), *extra], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        os.makedirs(ARGS.state_dir, exist_ok=True)
        with open(os.path.join(ARGS.state_dir, "setup.log"), "a") as logf:
            for line in RUNNING.stdout:
                logf.write(line)
                try:
                    self.wfile.write(f"data: {json.dumps(line.rstrip())}\n\n".encode())
                    self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    pass
        rc = RUNNING.wait()
        try:
            self.wfile.write(f"event: done\ndata: {json.dumps({'rc': rc, 'done': markers()})}\n\n".encode())
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass

    # Not "finish": socketserver calls a method of that name after every request.
    def api_finish(self):
        # Finishing switches to the normal generation, which stops this
        # service and kills everything in its cgroup, so the script runs as a
        # unit of its own and this answers before the switch gets here. A
        # transient unit starts with systemd's bare PATH; it gets this one.
        # Its output also goes to the console, the screen once the kiosk is gone.
        global FINISH_STARTED
        FINISH_STARTED = int(time.time())
        r = subprocess.run(["systemd-run", "--unit=nixie-finish", "--collect", f"--setenv=PATH={os.environ['PATH']}",
                            "-p", "StandardOutput=journal+console", "-p", "StandardError=journal+console",
                            shutil.which("nixie-finish")], capture_output=True, text=True)
        for f in os.listdir(keys_dir()):
            os.remove(os.path.join(keys_dir(), f))
        SECRETS.clear()
        msg = "Finishing: this page closes when the normal system takes over; `journalctl -u nixie-finish` shows the steps."
        return self.send_json({"ok": r.returncode == 0, "output": msg if r.returncode == 0 else r.stderr[-4000:]})


def reboot():
    # In the setup generation the machine must come back to itself: firmware
    # that puts an attached installer first (VirtualBox does on every start)
    # would boot that instead, so the next boot goes to the current entry.
    # Phase 3 does the same for the first boot after installing.
    if ARGS.mode == "continuation":
        cur = sh(["efibootmgr"]).stdout
        for line in cur.splitlines():
            if line.startswith("BootCurrent:"):
                sh(["efibootmgr", "-q", "--bootnext", line.split(":", 1)[1].strip()])
    subprocess.Popen(["systemctl", "reboot"])


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True

    # Send TLS close_notify: an event stream has no length, and without the
    # close alert curl treats the end of the response as a truncated read.
    def shutdown_request(self, request):
        try:
            request.settimeout(2)
            request.unwrap()
        except OSError:
            pass
        super().shutdown_request(request)


def ensure_cert(d, host):
    os.makedirs(d, mode=0o700, exist_ok=True)
    crt, key = os.path.join(d, "cert.pem"), os.path.join(d, "key.pem")
    if not os.path.exists(crt):
        ips = [l.split()[3].split("/")[0] for l in sh(["ip", "-4", "-o", "addr"]).stdout.splitlines() if not l.split()[3].startswith("127.")]
        san = ",".join(["DNS:" + host, "IP:127.0.0.1"] + ["IP:" + i for i in ips])
        sh(["openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes", "-days", "3650", "-subj", f"/CN={host}", "-addext", f"subjectAltName={san}", "-keyout", key, "-out", crt])
        os.chmod(key, 0o600)
    fp = sh(["openssl", "x509", "-in", crt, "-noout", "-fingerprint", "-sha256"]).stdout.strip().split("=", 1)[-1]
    return crt, key, fp


def banner(fp, ips):
    global PAIR_CODE
    PAIR_CODE = str(secrets.randbelow(900000) + 100000)
    urls = [f"https://{ip}:{ARGS.port}/" for ip in ips] or [f"https://<this machine>:{ARGS.port}/"]
    text = "\n".join([
        "", "  Nixie setup", "",
        *[f"  Open {u} in a browser on this network" for u in urls],
        f"  Pairing code: {PAIR_CODE}",
        f"  Certificate fingerprint: {fp}",
        "", qr_text(urls[0]) if urls[0].startswith("https://") and "<" not in urls[0] else "", "",
    ])
    try:
        consoles = open("/sys/class/tty/console/active").read().split()
    except OSError:
        consoles = ["console"]
    for name in consoles:
        try:
            with open(f"/dev/{name}", "w") as f:
                f.write(text)
        except OSError:
            pass
    log(text)
    with open(os.path.join(ARGS.state_dir, "banner.txt"), "w") as f:
        f.write(text)


def main():
    global ARGS
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["iso", "continuation"], default="iso")
    ap.add_argument("--port", type=int, default=9443)
    ap.add_argument("--static", required=True)
    ap.add_argument("--options", required=True)
    ap.add_argument("--template", required=True)
    ap.add_argument("--platform", required=True, help="flake URL a new site's nixie input points at")
    ap.add_argument("--site", default="/etc/nixie/site")
    ap.add_argument("--state-dir", default="/var/lib/nixie/setup")
    ap.add_argument("--cert-dir", default="/var/lib/nixie/setup-cert")
    ap.add_argument("--local-token", default="/run/nixie-setup/local-token")
    ap.add_argument("--age-key", default=None)
    ap.add_argument("--toplevel", default=None)
    ap.add_argument("--disko", default=None)
    ap.add_argument("--configure", action="store_true", help="read the wizard's choices as JSON on stdin, write state and site, exit")
    ARGS = ap.parse_args()
    ARGS.static = os.path.realpath(ARGS.static)
    os.makedirs(ARGS.state_dir, exist_ok=True)
    if ARGS.configure:
        return apply_config(json.load(sys.stdin))
    os.makedirs(os.path.dirname(ARGS.local_token), mode=0o700, exist_ok=True)
    with open(ARGS.local_token, "w") as f:
        f.write(secrets.token_urlsafe(24))
    os.chmod(ARGS.local_token, 0o600)
    host = socket.gethostname()
    crt, key, fp = ensure_cert(ARGS.cert_dir, host)
    ips = [l.split()[3].split("/")[0] for l in sh(["ip", "-4", "-o", "addr"]).stdout.splitlines() if not l.split()[3].startswith("127.")]
    banner(fp, ips)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(crt, key)
    srv = Server(("0.0.0.0", ARGS.port), Handler)
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    log(f"listening on :{ARGS.port} ({ARGS.mode})")
    srv.serve_forever()


if __name__ == "__main__":
    main()
