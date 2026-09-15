// Dashboards: JSON files in the shipped Grafana shape, rendered with uPlot.
// Data comes from the rolling in-browser history or, when configured, a
// Prometheus query_range adapter. Panels share one cursor and one range.
import { useEffect, useMemo, useRef, useState } from "react";
import uPlot from "uplot";
import "uplot/dist/uPlot.min.css";
import { useStore } from "../lib/store";
import { Panel, Field, Dialog, usePoll } from "../components/ui";
import { RANGES } from "../lib/series";
import hostDash from "../../../dashboards/host.json";
import guestDash from "../../../dashboards/guest.json";
import gpuDash from "../../../dashboards/gpu.json";

type PanelDef = { id: number; type: string; title: string; gridPos: { x: number; y: number; w: number; h: number }; targets: { expr: string; legendFormat?: string }[]; fieldConfig?: { defaults?: { unit?: string; thresholds?: { steps: { value: number | null }[] } } } };
type Dash = { uid: string; title: string; panels: PanelDef[]; templating?: { list: { name: string }[] } };
type Frame = { name: string; t: number[]; v: number[] };

const shipped: Dash[] = [hostDash as unknown as Dash, guestDash as unknown as Dash, gpuDash as unknown as Dash];

function loadCustom(): Dash[] {
  try {
    return JSON.parse(localStorage.getItem("nixie.dashboards") ?? "[]");
  } catch {
    return [];
  }
}

// Map a PromQL expression onto the rolling history when no Prometheus is
// set: the metric names we sample locally are the ones the shipped
// dashboards use.
function localFrames(expr: string, history: Record<string, number[]>, guest: string | null, points: number): Frame[] {
  const now = Date.now() / 1000;
  const mk = (name: string, vals: number[], scale = 1): Frame => {
    const v = vals.slice(-points);
    return { name, t: v.map((_, i) => now - (v.length - 1 - i) * 5), v: v.map((x) => x * scale) };
  };
  if (expr.includes("node_cpu_seconds_total")) return [mk("used", history["host.cpu"] ?? [], 0.01)];
  if (expr.includes("node_memory")) return [mk("used", history["host.mem"] ?? [], 0.01)];
  if (expr.includes("incus_cpu_seconds_total")) {
    const names = Object.keys(history).filter((k) => k.startsWith("cpu.")).map((k) => k.slice(4)).filter((n) => !guest || guest === "all" || guest === n);
    return names.map((n) => mk(n, history[`cpu.${n}`] ?? [], 0.01));
  }
  if (expr.includes("nvidia_smi_utilization")) return Object.keys(history).filter((k) => k.startsWith("gpu.util.")).map((k) => mk(`GPU ${k.slice(9)}`, history[k], 0.01));
  if (expr.includes("nvidia_smi_temperature")) return Object.keys(history).filter((k) => k.startsWith("gpu.temp.")).map((k) => mk(`GPU ${k.slice(9)}`, history[k]));
  if (expr.includes("nvidia_smi_power")) return Object.keys(history).filter((k) => k.startsWith("gpu.power.")).map((k) => mk(`GPU ${k.slice(10)}`, history[k]));
  return [];
}

async function promFrames(base: string, expr: string, minutes: number, guest: string | null): Promise<Frame[]> {
  const end = Math.floor(Date.now() / 1000);
  const start = end - minutes * 60;
  const step = Math.max(5, Math.floor((minutes * 60) / 300));
  const q = expr.replace(/\$guest/g, guest && guest !== "all" ? guest : ".*");
  const r = await fetch(`${base.replace(/\/$/, "")}/api/v1/query_range?query=${encodeURIComponent(q)}&start=${start}&end=${end}&step=${step}`);
  const j = (await r.json()) as { data: { result: { metric: Record<string, string>; values: [number, string][] }[] } };
  return j.data.result.map((s) => ({ name: Object.entries(s.metric).filter(([k]) => k !== "__name__").map(([, v]) => v).join(" ") || "value", t: s.values.map((v) => v[0]), v: s.values.map((v) => Number(v[1])) }));
}

const colors = ["var(--cpu)", "var(--mem)", "var(--net)", "var(--disk)", "var(--hot)", "var(--ok)", "var(--ice)", "var(--err)"];
const css = (v: string) => getComputedStyle(document.documentElement).getPropertyValue(v.slice(4, -1)).trim() || "#7ebae4";

function TimeSeries({ frames, unit, threshold, sync }: { frames: Frame[]; unit: string; threshold?: number; sync: string }) {
  const ref = useRef<HTMLDivElement>(null);
  const plot = useRef<uPlot | null>(null);
  useEffect(() => {
    if (!ref.current) return;
    const el = ref.current;
    const fmt = (v: number) => (unit === "percentunit" ? `${(v * 100).toFixed(0)}%` : unit === "bytes" ? `${(v / 2 ** 30).toFixed(1)} G` : unit === "Bps" ? `${(v / 2 ** 20).toFixed(1)} M/s` : unit === "celsius" ? `${v.toFixed(0)}°` : unit === "watt" ? `${v.toFixed(0)} W` : v.toFixed(2));
    const build = () => {
      plot.current?.destroy();
      const ts = frames[0]?.t ?? [];
      const data: uPlot.AlignedData = [ts, ...frames.map((f) => f.v)] as uPlot.AlignedData;
      const ink = css("var(--ink)");
      const opts: uPlot.Options = {
        width: el.clientWidth,
        height: Math.max(120, el.clientHeight - 4),
        cursor: { sync: { key: sync }, points: { size: 6 } },
        legend: { show: true },
        axes: [
          { stroke: css("var(--muted)"), grid: { stroke: css("var(--line)"), dash: [2, 4] }, ticks: { show: false }, font: "11px 'JetBrains Mono'" },
          { stroke: css("var(--muted)"), grid: { stroke: css("var(--line)"), dash: [2, 4] }, ticks: { show: false }, font: "11px 'JetBrains Mono'", values: (_, v) => v.map(fmt), size: 56 },
        ],
        series: [{ label: "time" }, ...frames.map((f, i) => ({ label: f.name, stroke: css(colors[i % colors.length]), width: 1.5, fill: i === 0 ? `color-mix(in oklch, ${css(colors[0])} 20%, transparent)` : undefined, value: (_: uPlot, v: number | null) => (v == null ? "–" : fmt(v)) }))],
        hooks: threshold !== undefined ? { draw: [(u) => { const y = u.valToPos(threshold, "y", true); const ctx = u.ctx; ctx.save(); ctx.strokeStyle = css("var(--err)"); ctx.setLineDash([4, 4]); ctx.beginPath(); ctx.moveTo(u.bbox.left, y); ctx.lineTo(u.bbox.left + u.bbox.width, y); ctx.stroke(); ctx.restore(); }] } : undefined,
      };
      el.style.color = ink;
      plot.current = new uPlot(opts, data, el);
    };
    build();
    const ro = new ResizeObserver(() => plot.current?.setSize({ width: el.clientWidth, height: Math.max(120, el.clientHeight - 4) }));
    ro.observe(el);
    return () => {
      ro.disconnect();
      plot.current?.destroy();
    };
  }, [frames, unit, threshold, sync]);
  return <div ref={ref} className="well" style={{ flex: 1, minHeight: 140, padding: 4 }} />;
}

function Stat({ frames, unit, kind }: { frames: Frame[]; unit: string; kind: string }) {
  const v = frames[0]?.v.at(-1) ?? 0;
  const pct = unit === "percentunit" ? v * 100 : v;
  const text = unit === "percentunit" ? `${pct.toFixed(0)} %` : unit === "bytes" ? `${(v / 2 ** 30).toFixed(1)} GB` : v.toFixed(2);
  if (kind === "gauge") {
    const dash = 217 * Math.min(1, pct / 100);
    return (
      <div style={{ display: "flex", justifyContent: "center", flex: 1, alignItems: "center" }}>
        <div className="ring">
          <svg viewBox="0 0 120 120" style={{ width: 118, height: 118 }}>
            <circle cx="60" cy="60" r="46" fill="none" strokeWidth="10" stroke="var(--s2)" strokeDasharray="217 289" transform="rotate(135 60 60)" strokeLinecap="round" />
            <circle cx="60" cy="60" r="46" fill="none" strokeWidth="10" stroke={pct > 85 ? "var(--err)" : "var(--disk)"} strokeDasharray={`${dash.toFixed(1)} 400`} transform="rotate(135 60 60)" strokeLinecap="round" />
          </svg>
          <div className="val">{text}</div>
        </div>
      </div>
    );
  }
  if (kind === "bargauge") return <div style={{ display: "flex", flexDirection: "column", gap: 6, flex: 1, justifyContent: "center" }}>{frames.map((f, i) => <div key={f.name}><div className="muted" style={{ fontSize: 11 }}>{f.name}</div><span className="bar"><i style={{ width: `${Math.min(100, (f.v.at(-1) ?? 0) * (unit === "percentunit" ? 100 : 1))}%`, background: colors[i % colors.length] }} /></span></div>)}</div>;
  if (kind === "table") return <div className="table" style={{ gridTemplateColumns: "1fr auto" }}>{frames.map((f) => <span key={f.name} style={{ display: "contents" }}><span>{f.name}</span><span className="mono">{(f.v.at(-1) ?? 0).toFixed(2)}</span></span>)}</div>;
  if (kind === "heatmap") return <div className="strip row" style={{ height: 40 }}>{(frames[0]?.v ?? []).slice(-96).map((x, i) => <i key={i} style={{ background: `color-mix(in oklch, var(--hot) ${Math.min(100, x * (unit === "percentunit" ? 100 : 1))}%, var(--s2))` }} />)}</div>;
  if (kind === "logs") return <pre className="well term" style={{ fontSize: 11, minHeight: 80 }}>{frames.map((f) => `${f.name}\n`).join("")}</pre>;
  return <div className="readout" style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center" }}>{text}</div>;
}

export function Dashboards({ uid, guest }: { uid?: string; guest?: string }) {
  const { history, range, setRange, site, demo } = useStore();
  const [custom, setCustom] = useState<Dash[]>(loadCustom);
  const all = [...shipped, ...custom];
  // Short names (#/dashboards/gpu, the instance page's guest link) stand for the shipped nixie-* ones.
  const dash = all.find((d) => d.uid === uid || d.uid === `nixie-${uid}`) ?? all[0];
  const minutes = RANGES[range] ?? 60;
  const points = Math.max(2, Math.round(minutes / 5)) * 12;
  const prom = localStorage.getItem("nixie.prometheus") || site.prometheusUrl;
  const [selGuest, setSelGuest] = useState(guest ?? "all");
  const [editing, setEditing] = useState(false);
  const [json, setJson] = useState("");
  const [tick, setTick] = useState(0);
  useEffect(() => {
    const t = setInterval(() => setTick((x) => x + 1), 15000);
    return () => clearInterval(t);
  }, []);
  const [frames] = usePoll(async () => {
    const out: Record<number, Frame[]> = {};
    for (const p of dash.panels) {
      const fr: Frame[] = [];
      for (const t of p.targets) {
        if (prom && !demo) fr.push(...(await promFrames(prom, t.expr, minutes, selGuest).catch(() => localFrames(t.expr, history, selGuest, points))));
        else fr.push(...localFrames(t.expr, history, selGuest, points));
      }
      out[p.id] = fr;
    }
    return out;
  }, [dash.uid, minutes, selGuest, prom, tick], 15000);
  const guests = useMemo(() => Object.keys(history).filter((k) => k.startsWith("cpu.")).map((k) => k.slice(4)), [history]);

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12 }}>
        <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
          <h1 className="page-title">Dashboards</h1>
          <select className="input" value={dash.uid} onChange={(e) => (location.hash = `#/dashboards/${e.target.value}`)} aria-label="dashboard">
            {all.map((d) => <option key={d.uid} value={d.uid}>{d.title}</option>)}
          </select>
          {dash.templating?.list.some((v) => v.name === "guest") && (
            <select className="input" value={selGuest} onChange={(e) => setSelGuest(e.target.value)} aria-label="guest">
              <option value="all">all guests</option>
              {guests.map((g) => <option key={g}>{g}</option>)}
            </select>
          )}
          <span className="muted">{prom && !demo ? `history: ${prom}` : "history: this browser session"}</span>
        </div>
        <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
          <div className="tray">{Object.keys(RANGES).map((r) => <button key={r} className="seg" aria-pressed={range === r} onClick={() => setRange(r)}>{r}</button>)}</div>
          <button className="btn" onClick={() => { setJson(JSON.stringify(dash, null, 2)); setEditing(true); }}>Edit JSON</button>
          <button className="btn" onClick={() => { setJson(""); setEditing(true); }}>Import</button>
        </div>
      </div>
      <div className="grid12" style={{ gridAutoRows: "28px" }}>
        {dash.panels.map((p) => {
          const th = p.fieldConfig?.defaults?.thresholds?.steps.find((s) => s.value != null)?.value ?? undefined;
          const unit = p.fieldConfig?.defaults?.unit ?? "short";
          return (
            <Panel key={p.id} title={p.title} dense style={{ gridColumn: `${p.gridPos.x / 2 + 1} / span ${p.gridPos.w / 2}`, gridRow: `${p.gridPos.y + 1} / span ${p.gridPos.h}` }}>
              {p.type === "timeseries" ? <TimeSeries frames={frames?.[p.id] ?? []} unit={unit} threshold={th ?? undefined} sync={dash.uid} /> : <Stat frames={frames?.[p.id] ?? []} unit={unit} kind={p.type} />}
            </Panel>
          );
        })}
      </div>
      {editing && (
        <Dialog title="Dashboard JSON" onClose={() => setEditing(false)} wide footer={<button className="btn primary" onClick={() => { try { const d = JSON.parse(json) as Dash; const next = [...custom.filter((c) => c.uid !== d.uid), d]; setCustom(next); localStorage.setItem("nixie.dashboards", JSON.stringify(next)); setEditing(false); location.hash = `#/dashboards/${d.uid}`; } catch (e) { alert(String(e)); } }}>Save</button>}>
          <Field label="Grafana-shaped JSON: uid, title, panels[] with gridPos, targets[].expr, fieldConfig.defaults.unit"><textarea className="input" rows={18} value={json} onChange={(e) => setJson(e.target.value)} /></Field>
        </Dialog>
      )}
    </div>
  );
}
