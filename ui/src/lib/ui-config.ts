// The control panel's own settings, changed from its Settings page and shared
// by every browser that opens it. They are one JSON value in the daemon's
// free-form user.* server configuration, so nothing new runs on the host; the
// site's nixie.ui.* is what they start from.
import type { Finish } from "../tokens";

export const UI_KEY = "user.nixie.ui";

export type UiConfig = {
  theme?: Finish;
  range?: string;
  title?: string;
  stats?: string[];
  overview?: { id: string; span: number; hidden?: boolean }[];
  hiddenPages?: string[];
  links?: { label: string; url: string }[];
};

// The figures in the header, in their default order.
export const STATS: [string, string][] = [
  ["cpu", "CPU"],
  ["memory", "Memory"],
  ["guests", "Guests"],
  ["guest-memory", "Guest memory"],
  ["gpu", "GPU"],
  ["operations", "Operations"],
];

// The Overview's panels, in their default order and width (of 12 columns).
// The chart rows keep a fixed height so a moved chart does not collapse.
export const OVERVIEW_PANELS: { id: string; title: string; span: number; height?: number }[] = [
  { id: "cpu", title: "CPU", span: 3, height: 198 },
  { id: "memory", title: "Memory", span: 3, height: 198 },
  { id: "gpu-power", title: "GPU power", span: 3, height: 198 },
  { id: "gpu-temperature", title: "GPU temperature", span: 3, height: 198 },
  { id: "instances", title: "Instances", span: 7, height: 252 },
  { id: "topology", title: "Bridge topology", span: 5, height: 252 },
  { id: "storage", title: "Storage", span: 4 },
  { id: "gpu-utilization", title: "GPU utilization", span: 5 },
  { id: "operations", title: "Operations", span: 3 },
];

// A saved layout in its own order, then any panel added since, so an older
// saved value never hides a new panel.
export function overviewLayout(saved?: UiConfig["overview"]) {
  const known = new Map(OVERVIEW_PANELS.map((p) => [p.id, p]));
  const kept = (saved ?? []).filter((p) => known.has(p.id)).map((p) => ({ ...known.get(p.id)!, span: Math.min(12, Math.max(2, p.span)), hidden: !!p.hidden }));
  return [...kept, ...OVERVIEW_PANELS.filter((p) => !kept.some((k) => k.id === p.id)).map((p) => ({ ...p, hidden: false }))];
}
