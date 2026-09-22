// One store: which backend answers, the finish, the time range, the shared
// chart cursor, the rolling metrics history and the site's declared guests.
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { incus, parseMetrics, type Backend, type Instance, type Op } from "./api";
import { demo, demoDeclared, demoSeries } from "./demo";
import { applyFinish, type Finish, type Tokens } from "../tokens";
import { NOTICES_KEY, UI_KEY, type Notice, type UiConfig } from "./ui-config";

export type Machine = { name: string; profile: string; url: string | null };
export type SiteConfig = {
  theme: Finish;
  host: string;
  machines: Machine[];
  tokens: Partial<Tokens>;
  links: { label: string; url: string }[];
  declared: Record<string, { kind: string; ip: string; image: string }>;
  allowSiteEdits: boolean;
  hostUiUrl: string | null;
  prometheusPath: string | null;
  grafanaPath: string | null;
  prometheusUrl: string | null;
  grafanaUrl: string | null;
  gpuPowerCap: number | null;
};
const defaultSite: SiteConfig = { theme: "graphite", host: "", machines: [], tokens: {}, links: [], declared: {}, allowSiteEdits: false, hostUiUrl: null, prometheusPath: null, grafanaPath: null, prometheusUrl: null, grafanaUrl: null, gpuPowerCap: null };

// Services published by tailscale serve live under paths on the tailnet
// name the panel was opened on; the host page is a port on the same host.
function resolveUrls(s: SiteConfig): SiteConfig {
  const onTailnet = /\.ts\.net$/.test(location.hostname);
  const base = `https://${location.hostname}`;
  return {
    ...s,
    prometheusUrl: s.prometheusPath && onTailnet ? base + s.prometheusPath : s.prometheusUrl,
    grafanaUrl: s.grafanaPath && onTailnet ? base + s.grafanaPath : s.grafanaUrl,
    hostUiUrl: s.hostUiUrl?.startsWith(":") ? `https://${location.hostname}${s.hostUiUrl}` : s.hostUiUrl,
  };
}

export type History = Record<string, number[]>; // metric key -> last N samples (one per poll)
export const HISTORY = 1440;

type Store = {
  api: Backend;
  demo: boolean;
  site: SiteConfig;
  finish: Finish;
  // null: follow the default every browser gets
  setFinish: (f: Finish | null) => void;
  ui: UiConfig;
  saveUi: (next: UiConfig) => Promise<void>;
  range: string;
  setRange: (r: string) => void;
  cursor: number | null;
  setCursor: (c: number | null) => void;
  instances: Instance[];
  operations: Op[];
  events: { t: string; kind: string; text: string }[];
  history: History;
  refresh: () => Promise<void>;
  toast: (msg: string, err?: boolean) => void;
  toasts: { id: number; msg: string; err: boolean }[];
  auth: string;
  notices: Notice[];
  run: <T>(label: string, p: Promise<T>) => Promise<T | undefined>;
};

const Ctx = createContext<Store | null>(null);
export const useStore = () => useContext(Ctx)!;

export function StoreProvider({ children }: { children: ReactNode }) {
  const [api, setApi] = useState<Backend>(incus);
  const [auth, setAuth] = useState("unknown");
  const [site, setSite] = useState<SiteConfig>(defaultSite);
  const [ui, setUi] = useState<UiConfig>({});
  // This browser's own choices win over the panel's settings, which win
  // over the site's.
  const [browserFinish, setBrowserFinish] = useState(localStorage.getItem("nixie.finish") as Finish | null);
  const finish = browserFinish ?? ui.theme ?? site.theme;
  const [browserRange, setBrowserRange] = useState(localStorage.getItem("nixie.range"));
  const range = browserRange ?? ui.range ?? "1h";
  const setRange = (r: string) => {
    localStorage.setItem("nixie.range", r);
    setBrowserRange(r);
  };
  const [cursor, setCursor] = useState<number | null>(null);
  const [instances, setInstances] = useState<Instance[]>([]);
  const [operations, setOperations] = useState<Op[]>([]);
  const [events, setEvents] = useState<Store["events"]>([]);
  const [toasts, setToasts] = useState<Store["toasts"]>([]);
  const [notices, setNotices] = useState<Notice[]>([]);
  const history = useRef<History>({});
  const [, tick] = useState(0);

  // Stable, so an effect that lists it runs once: the terminal listed a
  // fresh one each render and opened a new exec session per refresh.
  const toast = useCallback((msg: string, err = false) => {
    const id = Date.now() + Math.random();
    setToasts((t) => [...t, { id, msg, err }]);
    setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 5000);
  }, []);

  // Site configuration is a file next to the bundle, written by the host.
  useEffect(() => {
    fetch("./nixie.json")
      .then((r) => (r.ok ? r.json() : defaultSite))
      .then((s: Partial<SiteConfig>) => {
        setSite(resolveUrls({ ...defaultSite, ...s }));
      })
      .catch(() => undefined);
  }, []);
  useEffect(() => {
    applyFinish(finish, site.tokens);
  }, [finish, site]);
  const setFinish = (f: Finish | null) => {
    if (f) localStorage.setItem("nixie.finish", f);
    else localStorage.removeItem("nixie.finish");
    setBrowserFinish(f);
  };

  useEffect(() => {
    if (auth !== "trusted") return;
    (api.demo ? Promise.resolve(localStorage.getItem("nixie.ui") ?? "{}") : api.server().then((s) => (s.config ?? {})[UI_KEY] ?? "{}"))
      .then((raw) => {
        try {
          setUi(JSON.parse(raw) as UiConfig);
        } catch {
          // A value edited by hand into something other than JSON: start from the site.
          setUi({});
        }
      })
      .catch(() => undefined);
  }, [api, auth]);
  const saveUi = async (next: UiConfig) => {
    if (api.demo) localStorage.setItem("nixie.ui", JSON.stringify(next));
    else await api.updateServer({ [UI_KEY]: JSON.stringify(next) });
    setUi(next);
  };

  // Pick the backend once: the daemon, or the seeded demo when it is silent.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (new URLSearchParams(location.search).has("demo")) {
        setApi(demo);
        setAuth("trusted");
        return;
      }
      try {
        const s = await incus.server();
        if (cancelled) return;
        setAuth(s.auth);
      } catch {
        if (!cancelled) {
          setApi(demo);
          setAuth("trusted");
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // One refresh at a time: every operation and lifecycle event asks for one,
  // and a burst of them gets a single follow-up instead of a request each.
  const refreshing = useRef<"idle" | "busy" | "again">("idle");
  const refresh = async () => {
    if (auth !== "trusted") return;
    if (refreshing.current !== "idle") {
      refreshing.current = "again";
      return;
    }
    refreshing.current = "busy";
    try {
      // The host's own notices ride along with the poll: they are a value in
      // the daemon's configuration, so no second connection and nothing on
      // the host to ask.
      const [ins, ops, srv] = await Promise.all([api.instances(), api.operations(), api.server().catch(() => null)]);
      setInstances(ins);
      setOperations(ops);
      try {
        setNotices(JSON.parse((srv?.config ?? {})[NOTICES_KEY] ?? "[]"));
      } catch {
        // Edited by hand into something other than JSON: say nothing.
        setNotices([]);
      }
    } catch (e) {
      toast(String((e as Error).message), true);
    } finally {
      // Read afresh: an event may have asked again while this one ran.
      const again = (refreshing.current as string) === "again";
      refreshing.current = "idle";
      if (again) setTimeout(() => void refresh(), 500);
    }
  };

  // Rolling history from /1.0/metrics, sampled while the page is open.
  const sample = async () => {
    if (auth !== "trusted") return;
    const h = history.current;
    const push = (k: string, v: number) => {
      const a = (h[k] ??= []);
      a.push(v);
      if (a.length > HISTORY) a.shift();
    };
    if (api.demo) {
      // A fresh demo page starts with a full history, so its charts look like
      // a machine that has been running rather than one sample per chart.
      const first = !h["_n"];
      for (let k = first ? HISTORY : 1; k > 0; k--) {
        const n = (h["_n"]?.[0] ?? 0) + 1;
        h["_n"] = [n];
        const idx = (i: number) => (n * 3 + i * 17) % 1440;
        push("host.cpu", demoSeries.hostCpu[idx(0)]);
        push("host.mem", demoSeries.mem[idx(1)]);
        for (const [name, s] of Object.entries(demoSeries.cpu)) push(`cpu.${name}`, s[idx(2)]);
        demoSeries.gpuUtil.forEach((s, i) => push(`gpu.util.${i}`, s[idx(3 + i)]));
        demoSeries.gpuPower.forEach((s, i) => push(`gpu.power.${i}`, s[idx(5 + i)]));
        demoSeries.gpuTemp.forEach((s, i) => push(`gpu.temp.${i}`, s[idx(7 + i)]));
      }
      tick((x) => x + 1);
      return;
    }
    try {
      const m = parseMetrics(await api.metrics());
      const prev = h["_prev"] as unknown as Record<string, number> | undefined;
      const cpuNow: Record<string, number> = {};
      for (const s of m["incus_cpu_seconds_total"] ?? []) cpuNow[s.labels.name] = (cpuNow[s.labels.name] ?? 0) + s.value;
      const dt = 5;
      let total = 0;
      for (const [name, v] of Object.entries(cpuNow)) {
        const pct = prev && prev[name] !== undefined ? Math.max(0, ((v - prev[name]) / dt) * 100) : 0;
        push(`cpu.${name}`, pct);
        total += pct;
      }
      h["_prev"] = cpuNow as unknown as number[];
      push("host.cpu", Math.min(100, total));
      // incusd exports MemTotal and MemAvailable per instance; an instance
      // without a memory limit reports the host's total.
      const avail = Object.fromEntries((m["incus_memory_MemAvailable_bytes"] ?? []).map((s) => [s.labels.name, s.value]));
      const totals = m["incus_memory_MemTotal_bytes"] ?? [];
      const memUsed = totals.reduce((a, s) => a + Math.max(0, s.value - (avail[s.labels.name] ?? s.value)), 0);
      const memTotal = Math.max(0, ...totals.map((s) => s.value));
      push("host.mem", memTotal ? (memUsed / memTotal) * 100 : 0);
      tick((x) => x + 1);
    } catch {
      /* metrics are optional */
    }
  };

  useEffect(() => {
    if (auth !== "trusted") return;
    void refresh();
    void sample();
    const t1 = setInterval(refresh, 15000);
    const t2 = setInterval(sample, 5000);
    const off = api.events((e) => {
      const md = e.metadata as { action?: string; source?: string; description?: string; status?: string; message?: string };
      const kind = e.type === "lifecycle" ? md.action ?? "" : e.type === "operation" ? md.status ?? "" : "log";
      const text = e.type === "lifecycle" ? md.source?.replace("/1.0/instances/", "") ?? "" : md.description ?? md.message ?? "";
      setEvents((ev) => [{ t: e.timestamp.slice(11, 19), kind, text }, ...ev].slice(0, 60));
      if (e.type !== "logging") void refresh();
    });
    return () => {
      clearInterval(t1);
      clearInterval(t2);
      off();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [api, auth]);

  const run: Store["run"] = async (label, p) => {
    try {
      const r = await p;
      const op = r as unknown as Op | undefined;
      if (op && typeof op === "object" && "id" in op && op.status !== "Success") await api.waitOperation(op.id).catch(() => undefined);
      toast(`${label}: done`);
      void refresh();
      return r;
    } catch (e) {
      toast(`${label}: ${(e as Error).message}`, true);
      return undefined;
    }
  };

  const value = useMemo<Store>(
    () => ({ api, demo: api.demo, site: api.demo && !Object.keys(site.declared).length ? { ...site, declared: demoDeclared } : site, finish, setFinish, ui, saveUi, range, setRange, cursor, setCursor, instances, operations, events, history: history.current, refresh, toast, toasts, auth, notices, run }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [api, site, finish, ui, range, cursor, instances, operations, events, toasts, auth, notices],
  );
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

// Which instances the site declares; anything else is scratch.
export function tier(site: SiteConfig, name: string): "declared" | "scratch" {
  return name in site.declared ? "declared" : "scratch";
}

// A guests.nix entry for an instance's current state, the same shape the CLI emits.
export function exportEntry(i: Instance): string {
  const cfg = i.config ?? {};
  const devs = i.expanded_devices ?? i.devices ?? {};
  const lines = [`  ${i.name} = {`];
  if (cfg["image.os"] === "nixos") lines.push('    kind = "nixos";');
  else {
    lines.push(`    kind = "${i.type === "virtual-machine" ? "vm" : "image"}";`);
    lines.push(`    image.fingerprint = "${cfg["volatile.base_image"] ?? ""}";`);
  }
  if (cfg["security.nesting"] === "true") lines.push("    nesting = true;");
  if (Object.values(devs).some((d) => d.type === "gpu")) lines.push("    gpu = true;");
  if (cfg["limits.memory"]) lines.push(`    limits.memory = "${cfg["limits.memory"]}";`);
  if (cfg["limits.cpu"]) lines.push(`    limits.cpu = "${cfg["limits.cpu"]}";`);
  const mounts = Object.values(devs).filter((d) => d.type === "disk" && d.source);
  if (mounts.length) {
    lines.push("    mounts = {");
    for (const m of mounts) lines.push(`      "${m.source}" = "${m.path}";`);
    lines.push("    };");
  }
  const extra = (i.profiles ?? []).filter((p) => p !== "default");
  if (extra.length) lines.push(`    profiles = [ ${extra.map((p) => `"${p}"`).join(" ")} ];`);
  lines.push("  };");
  return lines.join("\n");
}
