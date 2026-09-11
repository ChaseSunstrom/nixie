// Small, dumb building blocks straight from the design recipes.
import { useEffect, useRef, useState, type ReactNode } from "react";
import { areaPath, linePath, slice, at, timeTicks, type Series } from "../lib/series";
import { heatColor } from "../tokens";
import { useStore } from "../lib/store";

export const Mark = ({ size = 26 }: { size?: number }) => (
  <svg width={size} height={size} viewBox="0 0 72 72" fill="none" aria-hidden="true">
    <rect x="10" y="10" width="11" height="52" rx="3" fill="#5277c3" />
    <rect x="51" y="10" width="11" height="52" rx="3" fill="#5277c3" />
    <circle cx="27" cy="20" r="5" fill="#7ebae4" />
    <circle cx="33" cy="31" r="5" fill="#7ebae4" />
    <circle cx="39" cy="42" r="5" fill="#7ebae4" />
    <circle cx="45" cy="53" r="5" fill="#7ebae4" />
  </svg>
);

export function Panel({ title, sub, value, children, dense, style, span }: { title?: string; sub?: string; value?: ReactNode; children?: ReactNode; dense?: boolean; style?: React.CSSProperties; span?: number }) {
  return (
    <section className={`panel${dense ? " dense" : ""}`} style={{ gridColumn: span ? `span ${span}` : undefined, ...style }}>
      {title && (
        <header>
          <span className="t">
            {title} {sub && <span className="sub">· {sub}</span>}
          </span>
          {value !== undefined && <span className="v">{value}</span>}
        </header>
      )}
      {children}
    </section>
  );
}

export function Dot({ status }: { status: string }) {
  const s = status.toLowerCase();
  return <span className={`dot ${s === "running" ? "running" : s === "frozen" ? "frozen" : ""}`} aria-label={status} />;
}

export function Bar({ pct, color }: { pct: number; color?: string }) {
  return (
    <span className="bar" style={{ width: "100%" }}>
      <i style={{ width: `${Math.max(0, Math.min(100, pct))}%`, background: color }} />
    </span>
  );
}

// Every chart shares the cursor from the store, so hovering one moves all.
export function useCursor() {
  const { cursor, setCursor } = useStore();
  const onMove = (e: React.MouseEvent<HTMLElement>) => {
    const r = e.currentTarget.getBoundingClientRect();
    setCursor(Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)));
  };
  return { cursor, onMove, onLeave: () => setCursor(null) };
}

export function Chart({ series, colors, max = 100, min = 0, cap, unit = "%", height = 140, minutes }: { series: Series[]; colors: string[]; max?: number; min?: number; cap?: number; unit?: string; height?: number; minutes: number }) {
  const { cursor, onMove, onLeave } = useCursor();
  const W = 600;
  const H = height;
  const shown = series.map((s) => slice(s));
  const capY = cap !== undefined ? H - 1 - ((cap - min) / (max - min || 1)) * (H - 2) : undefined;
  return (
    <div className="well chart" onMouseMove={onMove} onMouseLeave={onLeave}>
      <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" style={{ width: "100%", height: "100%", display: "block" }}>
        {[0.25, 0.5, 0.75].map((f) => (
          <line key={f} x1="0" x2={W} y1={H * f} y2={H * f} stroke="var(--line)" strokeDasharray="2 4" />
        ))}
        {shown.map((s, i) => (
          <g key={i}>
            {i === 0 && <path d={areaPath(s, W, H, min, max)} fill={`color-mix(in oklch, ${colors[i]} 20%, transparent)`} />}
            <path d={linePath(s, W, H, min, max)} fill="none" stroke={colors[i]} strokeWidth="1.5" vectorEffect="non-scaling-stroke" />
          </g>
        ))}
        {capY !== undefined && <line x1="0" x2={W} y1={capY} y2={capY} stroke="var(--err)" strokeDasharray="4 4" />}
      </svg>
      {cursor !== null && <div className="crosshair" style={{ left: `${cursor * 100}%` }} />}
      {cursor !== null && (
        <div className="mono" style={{ position: "absolute", top: 6, right: 8, fontSize: 11, color: colors[0] }}>
          {shown.map((s, i) => `${at(s, cursor).toFixed(unit === "%" ? 0 : 1)}${unit}`).join(" · ")}
        </div>
      )}
      <div className="ticks" style={{ position: "absolute", left: 8, right: 8, bottom: 2 }}>
        {timeTicks(minutes).map((t, i) => (
          <span key={i}>{t}</span>
        ))}
      </div>
    </div>
  );
}

export function Sparkline({ series, color = "var(--cpu)", max = 100 }: { series: Series; color?: string; max?: number }) {
  const s = slice(series, 120);
  return (
    <svg viewBox="0 0 600 60" preserveAspectRatio="none" style={{ width: "100%", height: 56, display: "block" }}>
      <path d={areaPath(s, 600, 60, 0, max)} fill={`color-mix(in oklch, ${color} 20%, transparent)`} />
      <path d={linePath(s, 600, 60, 0, max)} fill="none" stroke={color} strokeWidth="1.5" vectorEffect="non-scaling-stroke" />
    </svg>
  );
}

export function Ring({ value, max, caption, color }: { value: number; max: number; caption: string; color: string }) {
  const dash = 217 * Math.min(1, value / max);
  return (
    <div className="ring">
      <svg viewBox="0 0 120 120" style={{ width: 118, height: 118 }}>
        <circle cx="60" cy="60" r="46" fill="none" strokeWidth="10" stroke="var(--s2)" strokeDasharray="217 289" transform="rotate(135 60 60)" strokeLinecap="round" />
        <circle cx="60" cy="60" r="46" fill="none" strokeWidth="10" stroke={color} strokeDasharray={`${dash.toFixed(1)} 400`} transform="rotate(135 60 60)" strokeLinecap="round" />
      </svg>
      <div className="val">{Math.round(value)}</div>
      <div className="cap">{caption}</div>
    </div>
  );
}

export function PoolRing({ pct, name, detail }: { pct: number; name: string; detail: string }) {
  const color = pct > 85 ? "var(--err)" : "var(--disk)";
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 4 }}>
      <div className="ring pool">
        <svg viewBox="0 0 120 120" style={{ width: 104, height: 104 }}>
          <circle cx="60" cy="60" r="48" fill="none" strokeWidth="9" stroke="var(--s2)" />
          <circle cx="60" cy="60" r="48" fill="none" strokeWidth="9" stroke={color} strokeDasharray={`${((301.6 * pct) / 100).toFixed(1)} 400`} transform="rotate(-90 60 60)" />
        </svg>
        <div className="val">{Math.round(pct)}%</div>
      </div>
      <div style={{ fontWeight: 500 }}>{name}</div>
      <div className="mono muted" style={{ fontSize: 11 }}>
        {detail}
      </div>
    </div>
  );
}

export function HeatStrip({ series, scale = 1, row }: { series: Series; scale?: number; row?: boolean }) {
  const { finish } = useStore();
  const dark = finish !== "paper";
  const cells = slice(series, 96);
  return (
    <div className={`strip${row ? " row" : ""}`} aria-hidden="true">
      {cells.map((v, i) => (
        <i key={i} style={{ background: heatColor(v * scale, dark) }} />
      ))}
    </div>
  );
}

export function Toggle({ on, onChange, label }: { on: boolean; onChange: (v: boolean) => void; label: ReactNode }) {
  return (
    <button type="button" role="switch" aria-checked={on} className="toggle" onClick={() => onChange(!on)} style={{ background: "none", border: 0, padding: 0 }}>
      <span className="sw" />
      <span>{label}</span>
    </button>
  );
}

export function Dialog({ title, onClose, children, footer, wide }: { title: string; onClose: () => void; children: ReactNode; footer?: ReactNode; wide?: boolean }) {
  useEffect(() => {
    const k = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  }, [onClose]);
  return (
    <div className="scrim" onClick={onClose}>
      <div className="dialog" role="dialog" aria-label={title} style={wide ? { width: 820 } : undefined} onClick={(e) => e.stopPropagation()}>
        <div className="input-row">
          <span className="arrow">›</span>
          <span style={{ flex: 1, fontSize: 15 }}>{title}</span>
          <span className="kbd">esc</span>
        </div>
        <div className="body">{children}</div>
        {footer && <footer style={{ display: "flex", justifyContent: "flex-end", gap: 8 }}>{footer}</footer>}
      </div>
    </div>
  );
}

export function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="field">
      <span>{label}</span>
      {children}
    </label>
  );
}

// A key/value editor for config maps, used by instances, profiles and settings.
export function KvEditor({ value, onChange, readOnlyKeys = /^volatile\./ }: { value: Record<string, string>; onChange: (v: Record<string, string>) => void; readOnlyKeys?: RegExp }) {
  const [k, setK] = useState("");
  const [v, setV] = useState("");
  const entries = Object.entries(value).sort(([a], [b]) => a.localeCompare(b));
  return (
    <div className="table" style={{ gridTemplateColumns: "1fr 1fr auto" }}>
      <span className="h">key</span>
      <span className="h">value</span>
      <span className="h" />
      {entries.map(([key, val]) => (
        <KvRow key={key} k={key} v={val} locked={readOnlyKeys.test(key)} onChange={(nv) => onChange({ ...value, [key]: nv })} onDelete={() => onChange(Object.fromEntries(entries.filter(([x]) => x !== key)))} />
      ))}
      <input className="input mono" placeholder="new key" value={k} onChange={(e) => setK(e.target.value)} />
      <input className="input mono" placeholder="value" value={v} onChange={(e) => setV(e.target.value)} />
      <button
        className="btn"
        disabled={!k}
        onClick={() => {
          onChange({ ...value, [k]: v });
          setK("");
          setV("");
        }}
      >
        Add
      </button>
    </div>
  );
}
function KvRow({ k, v, locked, onChange, onDelete }: { k: string; v: string; locked: boolean; onChange: (v: string) => void; onDelete: () => void }) {
  return (
    <>
      <span className="mono" style={{ color: "var(--brand2)" }}>
        {k}
      </span>
      <input className="input mono" value={v} disabled={locked} onChange={(e) => onChange(e.target.value)} />
      <button className="btn" disabled={locked} onClick={onDelete} aria-label={`remove ${k}`}>
        ×
      </button>
    </>
  );
}

export function useHashRoute(): string[] {
  const [h, setH] = useState(location.hash);
  useEffect(() => {
    const f = () => setH(location.hash);
    window.addEventListener("hashchange", f);
    return () => window.removeEventListener("hashchange", f);
  }, []);
  return h.replace(/^#\/?/, "").split("/").filter(Boolean);
}
export const go = (path: string) => {
  location.hash = `#/${path}`;
};

export function Toasts() {
  const { toasts } = useStore();
  return (
    <>
      {toasts.map((t, i) => (
        <div key={t.id} className={`toast${t.err ? " err" : ""}`} style={{ bottom: 16 + i * 52 }} role="status">
          {t.msg}
        </div>
      ))}
    </>
  );
}

export function Empty({ children }: { children: ReactNode }) {
  return <div className="empty">{children}</div>;
}

export function usePoll<T>(fn: () => Promise<T>, deps: unknown[], ms = 15000): [T | undefined, () => void] {
  const [v, setV] = useState<T>();
  const alive = useRef(true);
  const load = () => {
    fn()
      .then((r) => alive.current && setV(r))
      .catch(() => undefined);
  };
  useEffect(() => {
    alive.current = true;
    load();
    const t = setInterval(load, ms);
    return () => {
      alive.current = false;
      clearInterval(t);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  return [v, load];
}
