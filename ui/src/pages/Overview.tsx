import { useStore, tier } from "../lib/store";
import { Panel, Chart, Ring, PoolRing, HeatStrip, Dot, Bar, useCursor, usePoll, go } from "../components/ui";
import { at, slice, RANGES, fmtBytes, fmtAge } from "../lib/series";
import { Topology } from "../components/Topology";
import { demoSeries } from "../lib/demo";

export function Overview() {
  const { history, range, instances, operations, events, site, api, cursor, demo } = useStore();
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

  return (
    <div className="grid12" style={{ gridTemplateRows: "198px 252px auto" }}>
      <Panel title="CPU" sub="host" value={<span style={{ color: "var(--cpu)" }}>{at(slice(hostCpu), frac).toFixed(0)} %</span>} span={3} dense>
        <Chart series={[hostCpu]} colors={["var(--cpu)"]} minutes={minutes} />
      </Panel>
      <Panel title="Memory" sub="host" value={<span style={{ color: "var(--mem)" }}>{at(slice(hostMem), frac).toFixed(0)} %</span>} span={3} dense>
        <Chart series={[hostMem]} colors={["var(--mem)"]} minutes={minutes} />
      </Panel>
      <Panel title="GPU power" sub={gpus ? `${gpus} cards` : "no GPU"} value={site.gpuPowerCap ? <span style={{ color: "var(--err)" }}>cap {site.gpuPowerCap} W</span> : undefined} span={3} dense>
        {gpus ? <Chart series={Array.from({ length: gpus }, (_, i) => last(`gpu.power.${i}`))} colors={["var(--hot)", "var(--disk)"]} max={Math.max(300, site.gpuPowerCap ?? 0) * 1.2} cap={site.gpuPowerCap ?? undefined} unit=" W" minutes={minutes} /> : <div className="empty">No GPU on this host</div>}
      </Panel>
      <Panel title="GPU temperature" span={3} dense>
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

      <Panel title="Instances" sub={`${instances.length} · ${instances.filter((i) => i.status === "Running").length} running`} span={7} dense style={{ padding: 0, overflow: "hidden" }}>
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
                  <span className="ip">{i.state?.network ? Object.values(i.state.network).flatMap((n) => n.addresses).find((a) => a.family === "inet" && a.scope === "global")?.address ?? "" : ""}</span>
                  {tier(site, i.name) === "scratch" && <span className="chip hot" style={{ fontSize: 10, padding: "0 5px" }}>scratch</span>}
                </span>
                <HeatStrip series={i.status === "Running" ? s : []} scale={1.6} />
                <span className="mono" style={{ fontSize: 12, textAlign: "right", color: v > 40 ? "var(--hot)" : "var(--ink)" }}>
                  {v.toFixed(0)} %
                </span>
                <span style={{ display: "flex", alignItems: "center", gap: 6 }}>
                  <Bar pct={memTotal ? (mem / memTotal) * 100 : 0} />
                  <span className="mono" style={{ fontSize: 11, width: 44, textAlign: "right" }}>
                    {fmtBytes(mem)}
                  </span>
                </span>
              </a>
            );
          })}
          {!instances.length && <div className="empty">No instances yet</div>}
          {cursor !== null && <div className="crosshair" style={{ left: `calc(176px + (100% - 176px - 190px) * ${cursor})` }} />}
        </div>
      </Panel>

      <Panel title="Bridge" sub="topology" span={5} dense>
        <Topology instances={instances} networks={nets ?? []} />
      </Panel>

      <Panel title="Storage" sub={pools?.[0]?.driver ?? ""} span={4} dense>
        <div style={{ display: "flex", justifyContent: "space-around", flex: 1, alignItems: "center", flexWrap: "wrap", gap: 8 }}>
          {(pools ?? []).map((p) => {
            const used = p.res?.space.used ?? 0;
            const total = p.res?.space.total ?? 1;
            return <PoolRing key={p.name} pct={(used / total) * 100} name={p.name} detail={`${fmtBytes(used)} / ${fmtBytes(total)}`} />;
          })}
          {pools && !pools.length && <div className="empty">No storage pools</div>}
        </div>
      </Panel>
      <Panel title="GPU utilization" sub="heatmap" span={5} dense>
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
      <Panel title="Operations" sub={`${running.length} running`} span={3} dense>
        <div className="table" style={{ gridTemplateColumns: "1fr 48px 32px" }}>
          {running.slice(0, 4).map((o) => (
            <a key={o.id} href="#/operations">
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
    </div>
  );
}
