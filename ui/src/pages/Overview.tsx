import { Fragment, type ReactNode } from "react";
import { useStore, tier } from "../lib/store";
import { overviewLayout } from "../lib/ui-config";
import { Panel, Chart, Ring, PoolRing, HeatStrip, Dot, Bar, useCursor, usePoll, go } from "../components/ui";
import { at, slice, RANGES, fmtBytes, fmtAge } from "../lib/series";
import { Topology } from "../components/Topology";
import { demoSeries } from "../lib/demo";
import { address } from "../lib/api";

export function Overview() {
  const { history, range, instances, operations, events, site, api, cursor, demo, ui } = useStore();
  const minutes = RANGES[range] ?? 60;
  const points = Math.max(2, Math.round(minutes / 5)) * 12; // one sample per 5 s
  const last = (k: string, n = points) => (history[k] ?? []).slice(-n);
  const hostCpu = last("host.cpu");
  const hostMem = last("host.mem");
  const gpus = demo ? 2 : Object.keys(history).filter((k) => k.startsWith("gpu.util.")).length;
  const [pools] = usePoll(async () => Promise.all((await api.pools()).map(async (p) => ({ ...p, res: await api.poolResources(p.name).catch(() => null) }))), [api], 30000);
  const [nets] = usePoll(() => api.networks(), [api], 30000);
  const frac = cursor ?? 1;
  const { onMove, onLeave } = useCursor();
  const running = operations.filter((o) => o.status === "Running");

  // Each panel by id, drawn in the order and width Settings keeps (ui-config.ts).
  const panels: Record<string, (span: number, height?: number) => ReactNode> = {
    "cpu": (span, height) => (
      <Panel title="CPU" sub="host" value={<span style={{ color: "var(--cpu)" }}>{at(slice(hostCpu), frac).toFixed(0)} %</span>} span={span} dense style={{ height }}>
        <Chart series={[hostCpu]} colors={["var(--cpu)"]} minutes={minutes} />
      </Panel>
    ),
    "memory": (span, height) => (
      <Panel title="Memory" sub="host" value={<span style={{ color: "var(--mem)" }}>{at(slice(hostMem), frac).toFixed(0)} %</span>} span={span} dense style={{ height }}>
        <Chart series={[hostMem]} colors={["var(--mem)"]} minutes={minutes} />
      </Panel>
    ),
    "gpu-power": (span, height) => (
      <Panel title="GPU power" sub={gpus ? `${gpus} cards` : "no GPU"} value={site.gpuPowerCap ? <span style={{ color: "var(--err)" }}>cap {site.gpuPowerCap} W</span> : undefined} span={span} dense style={{ height }}>
        {gpus ? <Chart series={Array.from({ length: gpus }, (_, i) => last(`gpu.power.${i}`))} colors={["var(--hot)", "var(--disk)"]} max={Math.max(300, site.gpuPowerCap ?? 0) * 1.2} cap={site.gpuPowerCap ?? undefined} unit=" W" minutes={minutes} /> : <div className="empty">No GPU on this host</div>}
      </Panel>
    ),
    "gpu-temperature": (span, height) => (
      <Panel title="GPU temperature" span={span} dense style={{ height }}>
        <div style={{ display: "flex", justifyContent: "space-around", alignItems: "center", flex: 1 }}>
          {gpus ? (
            Array.from({ length: gpus }, (_, i) => {
              const t = at(last(`gpu.temp.${i}`), frac);
              const u = at(last(`gpu.util.${i}`), frac);
              return <Ring key={i} value={t} max={100} caption={`GPU ${i} · ${u.toFixed(0)} %`} color={t > 80 ? "var(--err)" : t > 68 ? "var(--hot)" : "var(--cpu)"} />;
            })
          ) : (
            <div className="empty">No GPU on this host</div>
          )}
        </div>
      </Panel>
    ),
    "instances": (span, height) => (
      <Panel title="Instances" sub={`${instances.length} · ${instances.filter((i) => i.status === "Running").length} running`} span={span} dense style={{ padding: 0, overflow: "hidden", height }}>
        <div className="lane-head">
          <span>name</span>
          <span>cpu · {range}</span>
          <span style={{ textAlign: "right" }}>at cursor</span>
          <span>memory</span>
        </div>
        <div className="lanes" style={{ position: "relative" }} onMouseMove={onMove} onMouseLeave={onLeave}>
          {instances.map((i) => {
            const s = last(`cpu.${i.name}`);
            const v = at(slice(s, 96), frac);
            const mem = i.state?.memory?.usage ?? 0;
            const memTotal = i.state?.memory?.total || 0;
            return (
              <a key={i.name} className="lane" href={`#/instances/${i.name}`} onClick={(e) => (e.preventDefault(), go(`instances/${i.name}`))}>
                <span className="name">
                  <Dot status={i.status} />
                  <span>{i.name}</span>
                  <span className="ip">{address(i.state)}</span>
                  {tier(site, i.name) === "scratch" && <span className="chip hot" style={{ fontSize: 10, padding: "0 5px" }}>scratch</span>}
                </span>
                <HeatStrip series={i.status === "Running" ? s : []} scale={1.6} />
                <span className="mono" style={{ fontSize: 12, textAlign: "right", color: v > 40 ? "var(--hot)" : "var(--ink)" }}>
                  {v.toFixed(0)} %
                </span>
                <span style={{ display: "flex", alignItems: "center", gap: 6 }}>
                  <Bar pct={memTotal ? (mem / memTotal) * 100 : 0} />
                  <span className="mono" style={{ fontSize: 11, minWidth: 44, textAlign: "right", whiteSpace: "nowrap" }}>
                    {fmtBytes(mem)}
                  </span>
                </span>
              </a>
            );
          })}
          {!instances.length && <div className="empty">No instances yet</div>}
          {cursor !== null && <div className="crosshair" style={{ left: `calc(246px + (100% - 246px - 190px) * ${cursor})` }} />}
        </div>
      </Panel>
    ),
    "topology": (span, height) => (
      <Panel title="Bridge" sub="topology" span={span} dense style={{ height }}>
        <Topology instances={instances} networks={nets ?? []} />
      </Panel>
    ),
    "storage": (span, height) => (
      <Panel title="Storage" sub={pools?.[0]?.driver ?? ""} span={span} dense style={{ height }}>
        <div style={{ display: "flex", justifyContent: "space-around", flex: 1, alignItems: "center", flexWrap: "wrap", gap: 8 }}>
          {(pools ?? []).map((p) => {
            const used = p.res?.space.used ?? 0;
            const total = p.res?.space.total ?? 1;
            return <PoolRing key={p.name} pct={(used / total) * 100} name={p.name} detail={`${fmtBytes(used)} / ${fmtBytes(total)}`} />;
          })}
          {pools && !pools.length && <div className="empty">No storage pools</div>}
        </div>
      </Panel>
    ),
    "gpu-utilization": (span, height) => (
      <Panel title="GPU utilization" sub="heatmap" span={span} dense style={{ height }}>
        {gpus ? (
          <div style={{ display: "grid", gridTemplateColumns: "44px 1fr", gap: "6px 8px", alignItems: "center" }} onMouseMove={onMove} onMouseLeave={onLeave}>
            {Array.from({ length: gpus }, (_, i) => (
              <>
                <span key={`l${i}`} className="mono muted" style={{ fontSize: 11 }}>
                  GPU {i}
                </span>
                <HeatStrip key={`s${i}`} series={demo ? demoSeries.gpuUtil[i] : last(`gpu.util.${i}`)} row />
              </>
            ))}
          </div>
        ) : (
          <div className="empty">No GPU on this host</div>
        )}
      </Panel>
    ),
    "operations": (span, height) => (
      <Panel title="Operations" sub={`${running.length} running`} span={span} dense style={{ height }}>
        <div className="table" style={{ gridTemplateColumns: "1fr 48px 32px" }}>
          {running.slice(0, 4).map((o) => (
            <a key={o.id} href="#/operations" style={{ display: "contents" }}>
              <span>{o.description}</span>
              <Bar pct={Number(String((o.metadata as { download_progress?: string })?.download_progress ?? "50%").replace("%", "")) || 50} color="var(--brand2)" />
              <span className="mono muted">{fmtAge(o.created_at)}</span>
            </a>
          ))}
          {!running.length && <span className="muted">nothing running</span>}
        </div>
        <div className="divider table" style={{ gridTemplateColumns: "52px 1fr", fontSize: 11 }}>
          {events.slice(0, 6).map((e, i) => (
            <span key={i} style={{ display: "contents" }}>
              <span className="mono muted">{e.t}</span>
              <span>
                <span style={{ color: "var(--ink)" }}>{e.kind}</span> <span className="muted">{e.text}</span>
              </span>
            </span>
          ))}
        </div>
      </Panel>
    ),
  };
  const shown = overviewLayout(ui.overview).filter((p) => !p.hidden);

  return (
    <div className="grid12" style={{ alignItems: "start" }}>
      {shown.map((p) => <Fragment key={p.id}>{panels[p.id](p.span, p.height)}</Fragment>)}
      {!shown.length && <div className="empty" style={{ gridColumn: "span 12" }}>Every panel is hidden; Settings › Overview brings them back.</div>}
    </div>
  );
}
