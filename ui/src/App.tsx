import { useEffect, useState } from "react";
import { useStore } from "./lib/store";
import { Mark, useHashRoute, Toasts, Panel, go } from "./components/ui";
import { Palette, PAGES } from "./components/Palette";
import { Overview } from "./pages/Overview";
import { Instances, CreateInstance } from "./pages/Instances";
import { InstancePage } from "./pages/Instance";
import { Images, Profiles, Networks, Storage, Operations, Settings } from "./pages/Others";
import { Dashboards } from "./pages/Dashboards";
import { RANGES, fmtBytes } from "./lib/series";
import { finishes } from "./tokens";

function Trust() {
  const { auth } = useStore();
  const [server, setServer] = useState<{ auth_methods?: string[] } | null>(null);
  useEffect(() => {
    fetch("/1.0").then((r) => r.json()).then((j) => setServer(j.metadata)).catch(() => undefined);
  }, []);
  const oidc = server?.auth_methods?.includes("oidc");
  return (
    <div className="page" style={{ maxWidth: 720, margin: "40px auto" }}>
      <Panel title="This browser is not trusted yet" sub={auth}>
        <p>The daemon answers, but this browser has no certificate it trusts. Two ways in:</p>
        {oidc && <p><a className="btn primary" href="/oidc/login" style={{ display: "inline-flex", alignItems: "center" }}>Log in with the identity provider</a></p>}
        <ol style={{ lineHeight: 1.7 }}>
          <li>On the host, as the administrator, make a client certificate and a token:
            <pre className="well term" style={{ margin: "6px 0", minHeight: 0 }}>{`openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:secp384r1 -sha384 -days 3650 -nodes -subj "/CN=nixie-browser" -keyout client.key -out client.crt
openssl pkcs12 -export -inkey client.key -in client.crt -out client.p12   # choose a password
incus config trust add-certificate client.crt`}</pre>
          </li>
          <li>Import <code>client.p12</code> into this browser's certificates, then reload. Firefox: Settings › Privacy › Certificates › Your Certificates. Chromium: chrome://settings/certificates.</li>
        </ol>
        <p className="muted">The control panel talks only to the daemon that served it; nothing is sent anywhere else.</p>
      </Panel>
    </div>
  );
}

export function App() {
  const route = useHashRoute();
  const { instances, history, range, setRange, finish, setFinish, site, demo, auth, operations } = useStore();
  const [palette, setPalette] = useState(false);
  useEffect(() => {
    const k = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setPalette((p) => !p);
      } else if (e.key === "Escape") setPalette(false);
      else if (e.key === "g" && !(e.target as HTMLElement).matches("input,textarea,select")) {
        const next = (ev: KeyboardEvent) => {
          const p = PAGES.find((x) => x[0].toLowerCase() === ev.key);
          if (p) go(p.toLowerCase());
          window.removeEventListener("keydown", next);
        };
        window.addEventListener("keydown", next, { once: true });
      }
    };
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  }, []);
  if (auth !== "trusted" && auth !== "unknown") return <Trust />;
  const page = route[0] || "overview";
  const cpu = history["host.cpu"]?.at(-1) ?? 0;
  const mem = history["host.mem"]?.at(-1) ?? 0;
  const running = instances.filter((i) => i.status === "Running").length;
  const gpu = history["gpu.util.0"]?.at(-1);
  const memUsed = instances.reduce((a, i) => a + (i.state?.memory?.usage ?? 0), 0);
  const ops = operations.filter((o) => o.status === "Running").length;
  const stat = (label: string, value: string, unit?: string) => (
    <div className="stat" key={label}>
      <span className="label">{label}</span>
      <span className="value">
        {value} {unit && <span className="unit">{unit}</span>}
      </span>
    </div>
  );
  return (
    <div className="app">
      <header className="header">
        <a className="brand" href="#/overview">
          <Mark />
          <span className="wordmark">nixie</span>
          {demo && <span className="chip hot" style={{ fontSize: 10 }}>demo</span>}
        </a>
        <div className="stats">
          {stat("CPU", cpu.toFixed(0), "%")}
          {stat("Memory", mem.toFixed(0), "%")}
          {stat("Guests", `${running}`, `/ ${instances.length}`)}
          {stat("Guest memory", fmtBytes(memUsed).split(" ")[0], fmtBytes(memUsed).split(" ")[1])}
          {stat("GPU", gpu === undefined ? "–" : gpu.toFixed(0), gpu === undefined ? "" : "%")}
          {stat("Operations", `${ops}`, "running")}
        </div>
        <div className="header-right">
          <div className="tray">
            {Object.keys(RANGES).map((r) => (
              <button key={r} className="seg" aria-pressed={range === r} onClick={() => setRange(r)}>{r}</button>
            ))}
          </div>
          <div className="tray" role="group" aria-label="Finish">
            {finishes.map((f) => (
              <button key={f} className="swatch" aria-pressed={finish === f} aria-label={f} title={f} onClick={() => setFinish(f)} style={{ background: f === "graphite" ? "#1f2226" : f === "umber" ? "#231b16" : "#e4e1da" }} />
            ))}
          </div>
          <button className="palette-btn" onClick={() => setPalette(true)}>
            <span>Search or run</span>
            <span className="kbd">⌘K</span>
          </button>
          <span style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 12 }} className="muted">
            <span className="dot live" /> live · {new Date().toTimeString().slice(0, 5)}
          </span>
        </div>
      </header>
      <nav className="nav" aria-label="Primary">
        {PAGES.map((p) => (
          <a key={p} href={`#/${p.toLowerCase()}`} aria-current={page === p.toLowerCase() ? "page" : undefined}>
            {p}
            {p === "Operations" && ops > 0 && <span className="badge">{ops}</span>}
          </a>
        ))}
        {site.hostUiUrl && <a href={site.hostUiUrl}>Host</a>}
        {site.links.map((l) => (
          <a key={l.url} href={l.url}>{l.label}</a>
        ))}
      </nav>
      <main className="page">
        {page === "overview" && <Overview />}
        {page === "instances" && !route[1] && <Instances />}
        {page === "instances" && route[1] === "new" && <CreateInstance />}
        {page === "instances" && route[1] && route[1] !== "new" && <InstancePage name={route[1]} tab={route[2] ?? "overview"} />}
        {page === "images" && <Images />}
        {page === "profiles" && <Profiles />}
        {page === "networks" && <Networks />}
        {page === "storage" && <Storage />}
        {page === "operations" && <Operations />}
        {page === "settings" && <Settings />}
        {page === "dashboards" && <Dashboards uid={route[1]} guest={route[2]} />}
      </main>
      <Palette open={palette} onClose={() => setPalette(false)} />
      <Toasts />
    </div>
  );
}
