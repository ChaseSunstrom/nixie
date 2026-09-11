// xterm.js over the Incus exec websocket. In demo mode a few canned
// commands answer so the screen is not empty.
import { useEffect, useRef } from "react";
import { Terminal as XTerm } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import "@xterm/xterm/css/xterm.css";
import { useStore } from "../lib/store";

const canned: Record<string, string> = {
  uptime: " 21:40:03 up 12 days,  3:14,  0 users,  load average: 0.42, 0.38, 0.35",
  "free -h": "               total        used        free      shared  buff/cache   available\nMem:            62Gi        23Gi        11Gi       1.2Gi        27Gi        37Gi",
  ls: "bin  etc  nix  root  run  srv  sys  tmp  usr  var",
  "ip a": "2: uplink: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500\n    inet 192.0.2.10/24 scope global uplink",
  help: "demo terminal: uptime, free -h, ls, ip a, clear",
};

export function Terminal({ name }: { name: string }) {
  const ref = useRef<HTMLDivElement>(null);
  const { api, toast, finish } = useStore();
  useEffect(() => {
    if (!ref.current) return;
    const term = new XTerm({ fontFamily: "'JetBrains Mono', monospace", fontSize: 13, lineHeight: 1.2, cursorBlink: true, theme: finish === "paper" ? { background: "#d9d5cc", foreground: "#1c1b19", cursor: "#3f6bb8" } : { background: finish === "umber" ? "#1a130f" : "#181b1e", foreground: "#eceae5", cursor: "#7ebae4" } });
    const fit = new FitAddon();
    term.loadAddon(fit);
    term.open(ref.current);
    fit.fit();
    let ws: WebSocket | null = null;
    let control: WebSocket | null = null;
    let closed = false;
    const resize = () => {
      fit.fit();
      control?.readyState === 1 && control.send(JSON.stringify({ command: "window-resize", args: { width: String(term.cols), height: String(term.rows) } }));
    };
    window.addEventListener("resize", resize);
    if (api.demo) {
      let line = "";
      const prompt = () => term.write(`\r\n\x1b[38;2;126;186;228mroot@${name}\x1b[0m:~# `);
      term.writeln(`demo terminal for ${name}; the real one runs over the exec websocket`);
      prompt();
      term.onData((d) => {
        if (d === "\r") {
          const cmd = line.trim();
          line = "";
          if (cmd === "clear") term.clear();
          else if (cmd) term.write(`\r\n${(canned[cmd] ?? `${cmd}: command not found`).replace(/\n/g, "\r\n")}`);
          prompt();
        } else if (d === "\x7f") {
          if (line) {
            line = line.slice(0, -1);
            term.write("\b \b");
          }
        } else {
          line += d;
          term.write(d);
        }
      });
    } else {
      api
        .execUrls(name, ["/bin/sh", "-c", "exec $(command -v bash || command -v sh) -l"])
        .then(({ control: c, data }) => {
          if (closed) return;
          control = new WebSocket(c);
          ws = new WebSocket(data);
          ws.binaryType = "arraybuffer";
          ws.onmessage = (m) => term.write(new Uint8Array(m.data as ArrayBuffer));
          ws.onclose = () => term.writeln("\r\n[session closed]");
          control.onopen = resize;
          term.onData((d) => ws?.readyState === 1 && ws.send(new TextEncoder().encode(d)));
        })
        .catch((e) => toast(`terminal: ${(e as Error).message}`, true));
    }
    return () => {
      closed = true;
      window.removeEventListener("resize", resize);
      ws?.close();
      control?.close();
      term.dispose();
    };
  }, [name, api, toast, finish]);
  return <div ref={ref} className="well term" style={{ padding: 8 }} />;
}
