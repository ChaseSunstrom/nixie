# The local console: the front panel on the first text console, and an
# optional permanent kiosk showing the control panel behind a lock page.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../lib/option.nix lib) mkOption;
  cfg = config.nixie.console;
  panel = import ../packages/nixie-panel.nix { inherit pkgs; };
  server = config.nixie.profile == "server";
  # The setup generation owns tty1 while setup is pending; the kiosk keeps
  # tty1 when it is on, so the panel moves to tty2.
  panelTty = if cfg.kiosk.enable then "tty2" else "tty1";
  # The lock page is the setup pairing card in the host's finish.
  t = (import ../lib/tokens.nix { inherit lib; }).forFinish config.nixie.ui.theme;
  lockPage = pkgs.writeText "lock.html" ''
    <!doctype html><meta charset="utf-8"><title>nixie</title>
    <style>
    *{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:radial-gradient(900px 480px at 50% -200px,color-mix(in srgb,${t.brand} 22%,transparent),transparent 70%),${t.bg};color:${t.ink};font:14px Archivo,sans-serif}
    form{width:360px;background:${t.s1};border:1px solid ${t.line};border-radius:14px;padding:28px;display:grid;gap:12px;box-shadow:0 24px 60px -24px ${t.shadow};animation:pop .32s cubic-bezier(.2,.8,.2,1) both}
    @keyframes pop{from{opacity:0;transform:scale(.96) translateY(6px)}to{opacity:1;transform:none}}
    @media (prefers-reduced-motion:reduce){form{animation:none}}
    .brand{display:flex;align-items:center;gap:10px;font-size:20px;font-weight:600;letter-spacing:-.03em}h1{margin:6px 0 0;font-size:22px;font-weight:500}p{margin:0;color:${t.muted}}
    label{display:grid;gap:4px;font-weight:500}input{background:${t.s2};border:1px solid ${t.line};border-radius:6px;color:${t.ink};height:36px;padding:0 10px;font:inherit}input:focus{outline:2px solid ${t.brand2};outline-offset:1px}
    button{margin-top:4px;height:38px;background:${t.brand};border:0;border-radius:6px;color:#fff;font:inherit;cursor:pointer}button:hover{filter:brightness(1.12)}
    </style>
    <form method="post" action="/unlock">
      <div class="brand"><svg width="28" height="28" viewBox="0 0 72 72" aria-hidden="true"><rect x="10" y="18" width="10" height="44" rx="3" fill="${t.brand}"/><rect x="10" y="18" width="52" height="10" rx="3" fill="${t.brand}"/><rect x="52" y="18" width="10" height="44" rx="3" fill="${t.brand2}"/></svg>nixie</div>
      <h1>Unlock the control panel</h1><p>The administrator's password, and the code from the authenticator app if one is enrolled.</p>
      <label>Password<input name="password" type="password" autofocus></label>
      <label>Second factor<input name="code" inputmode="numeric" placeholder="if enrolled"></label>
      <button>Unlock</button>
    </form>
  '';
  # A small local gate: the kiosk checks the password with `unix_chkpwd`, the
  # pam_unix helper (it reads the password from stdin, so no terminal is
  # needed), and, when TOTP is enrolled, the code against the same file the
  # host page uses.
  gate = pkgs.writeShellApplication {
    name = "nixie-kiosk-gate";
    runtimeInputs = with pkgs; [
      python3
      coreutils
      oath-toolkit
    ];
    text = ''
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
              self.wfile.write(open("${lockPage}", "rb").read())
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
    '';
  };
in
{
  imports = [ ../installer/kiosk.nix ];

  options.nixie.console = {
    frontPanel.enable = mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        A status screen on the first text console instead of a bare login:
        host name, addresses, the control panel address as a QR code, each
        guest as a lane with its state, GPU temperature, pool usage, and
        anything `nixie doctor` would flag, drawn in the chosen finish. Any
        key opens the normal login. The other consoles stay ordinary logins.
      '';
      nixieUi = {
        section = "services";
        order = 7;
      };
    };
    kiosk.enable = mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Keep the setup kiosk permanently and point it at the control panel,
        so the local display shows the full web page behind a lock page that
        checks the administrator password and second factor. Costs a
        compositor and a browser in the server closure.
      '';
      nixieUi = {
        section = "services";
        order = 8;
      };
    };
    kiosk.idleLock = mkOption {
      type = lib.types.str;
      default = "10m";
      description = "Re-lock the kiosk after this much inactivity.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (server && cfg.frontPanel.enable && !config.nixie.setup.pending) {
      environment.etc."nixie/ui.json".text = builtins.toJSON {
        theme = config.nixie.ui.theme;
        uiPort = config.nixie.incus.ui.port;
      };
      systemd.services."getty@${panelTty}".enable = false;
      systemd.services.nixie-panel = {
        description = "Nixie front panel on ${panelTty}";
        # `r`/`b` on the panel run the nixie CLI from the system profile.
        path = [ "/run/current-system/sw" ];
        wantedBy = [ "multi-user.target" ];
        after = [
          "incus.service"
          "systemd-user-sessions.service"
          # The splash holds the console until it quits.
          "plymouth-quit-wait.service"
        ];
        conflicts = [ "getty@${panelTty}.service" ];
        serviceConfig = {
          # exposure: owns a console and execs login(1); it must run as root.
          ExecStart = "${lib.getExe panel} /dev/${panelTty}";
          StandardInput = "tty";
          StandardOutput = "tty";
          TTYPath = "/dev/${panelTty}";
          TTYReset = true;
          TTYVHangup = true;
          Restart = "always";
          RestartSec = 1;
        };
      };
    })
    (lib.mkIf (server && cfg.kiosk.enable && !config.nixie.setup.pending) {
      nixie.kiosk = {
        enable = true;
        url = "http://127.0.0.1:9444/";
        tokenFile = "";
      };
      systemd.services.nixie-kiosk-gate = {
        description = "Lock page in front of the local control panel";
        wantedBy = [ "multi-user.target" ];
        before = [ "cage-tty1.service" ];
        serviceConfig = {
          # exposure: checks the admin password through unix_chkpwd; loopback only.
          ExecStart = "${lib.getExe gate} ${config.nixie.auth.admin.name} ${
            toString (lib.toInt (lib.removeSuffix "m" cfg.kiosk.idleLock) * 60)
          } https://127.0.0.1:${toString config.nixie.incus.ui.port}/ui/";
          Restart = "on-failure";
        };
      };
    })
    (lib.mkIf server {
      # Prompts, the attestation code and the front panel must render on the
      # primary GPU. With the NVIDIA driver that needs modesetting and the
      # driver's own framebuffer.
      hardware.nvidia.modesetting.enable = lib.mkIf (config.nixie.hardware.gpu == "nvidia") true;
      # The open kernel modules are the supported choice on current cards; a
      # site with an older card sets this to false in its hardware.nix.
      hardware.nvidia.open = lib.mkIf (config.nixie.hardware.gpu == "nvidia") (lib.mkDefault true);
      boot.kernelParams = lib.optional (config.nixie.hardware.gpu == "nvidia") "nvidia-drm.fbdev=1";
      services.xserver.videoDrivers = lib.mkIf (config.nixie.hardware.gpu == "nvidia") [ "nvidia" ];
    })
  ];
}
