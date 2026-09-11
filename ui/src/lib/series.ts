// Series helpers shared by charts, lanes and heat strips. Hand-rolled SVG
// paths, as in the design file; uPlot is used only for the dashboards.
export type Series = number[];

export function slice(arr: Series, points = 160): Series {
  if (arr.length <= points) return arr;
  const out: number[] = [];
  const step = arr.length / points;
  for (let i = 0; i < points; i++) {
    const a = Math.floor(i * step);
    const b = Math.max(a + 1, Math.floor((i + 1) * step));
    let s = 0;
    for (let j = a; j < b; j++) s += arr[j];
    out.push(s / (b - a));
  }
  return out;
}

export function at(arr: Series, frac: number): number {
  if (!arr.length) return 0;
  return arr[Math.min(arr.length - 1, Math.max(0, Math.round(frac * (arr.length - 1))))];
}

export function linePath(vals: Series, w: number, h: number, min: number, max: number, pad = 1): string {
  if (!vals.length) return "";
  const span = max - min || 1;
  return vals
    .map((v, i) => {
      const x = (i / Math.max(1, vals.length - 1)) * w;
      const y = h - pad - ((Math.min(max, Math.max(min, v)) - min) / span) * (h - 2 * pad);
      return `${i ? "L" : "M"}${x.toFixed(1)} ${y.toFixed(1)}`;
    })
    .join(" ");
}

export function areaPath(vals: Series, w: number, h: number, min: number, max: number): string {
  const l = linePath(vals, w, h, min, max);
  return l ? `${l} L${w} ${h} L0 ${h} Z` : "";
}

export function timeTicks(minutes: number, n = 2): string[] {
  const now = Date.now();
  const out: string[] = [];
  for (let i = 0; i <= n; i++) {
    const t = new Date(now - minutes * 60_000 * (1 - i / n));
    out.push(t.toTimeString().slice(0, 5));
  }
  return out;
}

export function fmtBytes(b: number): string {
  const u = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  while (b >= 1024 && i < u.length - 1) {
    b /= 1024;
    i++;
  }
  return `${b < 10 ? b.toFixed(1) : Math.round(b)} ${u[i]}`;
}

export function fmtAge(iso: string): string {
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 90) return `${Math.round(s)}s`;
  if (s < 5400) return `${Math.round(s / 60)}m`;
  if (s < 172800) return `${Math.round(s / 3600)}h`;
  return `${Math.round(s / 86400)}d`;
}

export const RANGES: Record<string, number> = { "15m": 15, "1h": 60, "6h": 360, "24h": 1440 };
