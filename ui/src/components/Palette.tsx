// Cmd/Ctrl+K: every page, every instance action, and a few global ones.
import { useEffect, useMemo, useState } from "react";
import { useStore } from "../lib/store";
import { go } from "./ui";
import { finishes } from "../tokens";

export const PAGES = ["Overview", "Instances", "Images", "Profiles", "Networks", "Storage", "Operations", "Dashboards", "Settings"];

type Cmd = { label: string; hint: string; run: () => void };

export function Palette({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { instances, api, run, setFinish, finish, setRange } = useStore();
  const [q, setQ] = useState("");
  const [sel, setSel] = useState(0);
  useEffect(() => {
    setQ("");
    setSel(0);
  }, [open]);

  const commands = useMemo<Cmd[]>(() => {
    const c: Cmd[] = PAGES.map((p) => ({ label: `Go to ${p}`, hint: `g ${p[0].toLowerCase()}`, run: () => go(p.toLowerCase()) }));
    for (const i of instances) {
      const running = i.status === "Running";
      c.push({ label: `Open ${i.name}`, hint: "", run: () => go(`instances/${i.name}`) });
      c.push({ label: `Open terminal on ${i.name}`, hint: "", run: () => go(`instances/${i.name}/terminal`) });
      c.push({ label: `${running ? "Stop" : "Start"} ${i.name}`, hint: "", run: () => void run(`${running ? "Stop" : "Start"} ${i.name}`, api.instanceAction(i.name, running ? "stop" : "start")) });
      c.push({ label: `Restart ${i.name}`, hint: "", run: () => void run(`Restart ${i.name}`, api.instanceAction(i.name, "restart")) });
      c.push({ label: `Snapshot ${i.name}`, hint: "", run: () => void run(`Snapshot ${i.name}`, api.createSnapshot(i.name, `snap-${Date.now().toString(36)}`)) });
      c.push({ label: `Dashboard for ${i.name}`, hint: "", run: () => go(`dashboards/guest/${i.name}`) });
    }
    c.push({ label: "Create instance", hint: "n", run: () => go("instances/new") });
    c.push({ label: "Pull image debian/12", hint: "", run: () => void run("Pull debian/12", api.pullImage("https://images.linuxcontainers.org", "debian/12")) });
    c.push({ label: "Pull image ubuntu/24.04", hint: "", run: () => void run("Pull ubuntu/24.04", api.pullImage("https://images.linuxcontainers.org", "ubuntu/24.04")) });
    c.push({ label: "Toggle light theme", hint: "t", run: () => setFinish(finish === "paper" ? "graphite" : "paper") });
    for (const f of finishes) c.push({ label: `Finish: ${f}`, hint: "", run: () => setFinish(f) });
    for (const r of ["15m", "1h", "6h", "24h"]) c.push({ label: `Set range: last ${r}`, hint: `r ${r}`, run: () => setRange(r) });
    return c;
  }, [instances, api, run, setFinish, finish, setRange]);

  const results = useMemo(() => {
    const words = q.toLowerCase().split(/\s+/).filter(Boolean);
    return commands.filter((c) => words.every((w) => c.label.toLowerCase().includes(w))).slice(0, 9);
  }, [q, commands]);

  if (!open) return null;
  const pick = (c: Cmd) => {
    onClose();
    c.run();
  };
  return (
    <div className="scrim" onClick={onClose}>
      <div className="dialog" role="dialog" aria-label="Command palette" onClick={(e) => e.stopPropagation()}>
        <div className="input-row">
          <span className="arrow">›</span>
          <input
            className="plain"
            autoFocus
            placeholder="stop web · open terminal on db · pull debian/12"
            value={q}
            onChange={(e) => {
              setQ(e.target.value);
              setSel(0);
            }}
            onKeyDown={(e) => {
              if (e.key === "ArrowDown") setSel((s) => Math.min(results.length - 1, s + 1));
              else if (e.key === "ArrowUp") setSel((s) => Math.max(0, s - 1));
              else if (e.key === "Enter" && results[sel]) pick(results[sel]);
            }}
          />
          <span className="kbd">esc</span>
        </div>
        <div>
          {results.map((c, i) => (
            <button key={c.label} className="result" aria-selected={i === sel} onMouseEnter={() => setSel(i)} onClick={() => pick(c)}>
              <span className="mono muted" style={{ fontSize: 11 }}>
                {c.hint}
              </span>
              <span>{c.label}</span>
              <span className="muted">↵</span>
            </button>
          ))}
          {!results.length && <div className="empty">no matches</div>}
        </div>
        <footer>↑↓ move · ↵ run · {results.length} matches</footer>
      </div>
    </div>
  );
}
