import { useEffect, useState } from "react";
import { useStore } from "./lib/store";
import { Mark, useHashRoute, Toasts, go } from "./components/ui";
import { Palette, PAGES } from "./components/Palette";
import { Overview } from "./pages/Overview";
import { Instances, CreateInstance } from "./pages/Instances";
import { Machines } from "./pages/Machines";
import { InstancePage } from "./pages/Instance";
import { Images, Profiles, Networks, Storage, Operations, Settings } from "./pages/Others";
import { Dashboards } from "./pages/Dashboards";
import { History } from "./pages/History";
import { RANGES, fmtBytes } from "./lib/series";
import { STATS } from "./lib/ui-config";

function Trust() {
  const { auth } = useStore();
  const [server, setServer] = useState<{ auth_methods?: string[] } | null>(null);
  useEffect(() => {
    fetch("/1.0").then((r) => r.json()).then((j) => setServer(j.metadata)).catch(() => undefined);
  }, []);
  const oidc = server?.auth_methods?.includes("oidc");
  return (
    <div className="pair">
      <div className="panel pair-card wide">
        <div className="brand-row"><Mark size={30} /><span className="wordmark">nixie</span>{auth && <span className="chip">{auth}</span>}</div>
        <h1 className="title">This browser is not trusted yet</h1>
        <p className="caption">The daemon answers, but this browser has no certificate it trusts. Two ways in:</p>
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
      </div>
    </div>
  );
}

// What the host wants a person to know, on every page. The panel says it
// and names the command; acting on it is the machine's own business, which
// is why nothing here reaches past the daemon (D39).
function Notices() {
  const { notices } = useStore();
  const [hidden, setHidden] = useState<string[]>([]);
  const shown = notices.filter((n) => !hidden.includes(n.id));
  if (!shown.length) return null;
  return (
    <div className="notices">
      {shown.map((n) => (
        <div key={n.id} className={"notice" + (n.level === "warn" ? " warn" : "")}>
          <span className="notice-title">{n.title}</span>
          <span className="muted">{n.detail}</span>
          <code className="notice-action">{n.action}</code>
          <button className="btn icon" aria-label={`Hide: ${n.title}`} onClick={() => setHidden((h) => [...h, n.id])}>×</button>
        </div>
      ))}
    </div>
  );
}

export function App() {
  const route = useHashRoute();
  const { instances, history, range, setRange, site, ui, demo, auth, operations } = useStore();
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
  // Until the backend is chosen, pages would ask the daemon for data the
  // demo is about to answer instead (a preview served HTML as a network list).
  if (auth === "unknown") return <div className="boot"><Mark size={44} /></div>;
  if (auth !== "trusted") return <Trust />;
  const page = route[0] || "overview";
  const cpu = history["host.cpu"]?.at(-1) ?? 0;
  const mem = history["host.mem"]?.at(-1) ?? 0;
  const running = instances.filter((i) => i.status === "Running").length;
  const gpu = history["gpu.util.0"]?.at(-1);
  const memUsed = instances.reduce((a, i) => a + (i.state?.memory?.usage ?? 0), 0);
  const ops = operations.filter((o) => o.status === "Running").length;
  const figures: Record<string, [string, string]> = {
    cpu: [cpu.toFixed(0), "%"],
    memory: [mem.toFixed(0), "%"],
    guests: [`${running}`, `/ ${instances.length}`],
    "guest-memory": fmtBytes(memUsed).split(" ") as [string, string],
    gpu: gpu === undefined ? ["–", ""] : [gpu.toFixed(0), "%"],
    operations: [`${ops}`, "running"],
  };
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
          {ui.title && <span className="muted" style={{ fontSize: 13, whiteSpace: "nowrap" }}>{ui.title}</span>}
          {demo && <span className="chip hot" style={{ fontSize: 10 }}>demo</span>}
        </a>
        <div className="stats">
          {(ui.stats ?? STATS.map(([id]) => id)).filter((id) => figures[id]).map((id) => stat(STATS.find((s) => s[0] === id)![1], ...figures[id]))}
        </div>
        <div className="header-right">
          <div className="tray">
            {Object.keys(RANGES).map((r) => (
              <button key={r} className="seg" aria-pressed={range === r} onClick={() => setRange(r)}>{r}</button>
            ))}
          </div>
          <button className="palette-btn" onClick={() => setPalette(true)}>
            <span>Search or run</span>
            <span className="kbd">⌘K</span>
          </button>
          <span style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 12 }} className="muted">
            <span className="dot live" /> live · {new Date().toTimeString().slice(0, 5)}
          </span>
          <button className="btn icon" aria-label="Settings" title="Settings: theme, header, Overview layout, navigation" aria-pressed={page === "settings"} onClick={() => go("settings")}>
            <svg viewBox="0 0 24 24" width="17" height="17" aria-hidden="true">
              <path fill="currentColor" d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 0 0 .12-.61l-1.92-3.32a.49.49 0 0 0-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54a.48.48 0 0 0-.48-.41h-3.84a.47.47 0 0 0-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96a.48.48 0 0 0-.59.22L2.74 8.87a.47.47 0 0 0 .12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58a.49.49 0 0 0-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32a.49.49 0 0 0-.12-.61l-2.01-1.58zM12 15.6A3.6 3.6 0 1 1 12 8.4a3.6 3.6 0 0 1 0 7.2z" />
            </svg>
          </button>
        </div>
      </header>
      <nav className="nav" aria-label="Primary">
        {PAGES.filter((p) => p !== "Settings" && !(ui.hiddenPages ?? []).includes(p)).map((p) => (
          <a key={p} href={`#/${p.toLowerCase()}`} aria-current={page === p.toLowerCase() ? "page" : undefined}>
            {p}
            {p === "Operations" && ops > 0 && <span className="badge">{ops}</span>}
          </a>
        ))}
        {site.hostUiUrl && <a href={site.hostUiUrl}>Host</a>}
        {[...site.links, ...(ui.links ?? [])].map((l) => (
          <a key={l.url} href={l.url}>{l.label}</a>
        ))}
      </nav>
      <Notices />
      <main className="page">
        <div className="route" key={page}>
        {page === "overview" && <Overview />}
        {page === "machines" && <Machines />}
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
        {page === "history" && <History />}
        </div>
      </main>
      <Palette open={palette} onClose={() => setPalette(false)} />
      <Toasts />
    </div>
  );
}
