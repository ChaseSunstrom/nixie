// Images, Profiles, Networks, Storage, Operations and Settings: the parts of
// the daemon the design names but does not draw, in the same recipes.
import { useState } from "react";
import { useStore } from "../lib/store";
import { Panel, usePoll, Empty, Dialog, Field, KvEditor, Bar, Toggle } from "../components/ui";
import { fmtBytes, fmtAge } from "../lib/series";
import type { Profile } from "../lib/api";
import { finishes } from "../tokens";
import { Topology } from "../components/Topology";

export function Images() {
  const { api, run } = useStore();
  const [images, reload] = usePoll(() => api.images(), [api], 30000);
  const [alias, setAlias] = useState("");
  const [remote, setRemote] = useState("https://images.linuxcontainers.org");
  return (
    <Panel title="Images" sub={images ? `${images.length}` : ""} dense>
      <div style={{ display: "flex", gap: 8, margin: "8px 0" }}>
        <input className="input mono" style={{ width: 320 }} value={remote} onChange={(e) => setRemote(e.target.value)} aria-label="remote" />
        <input className="input mono" placeholder="alias, e.g. debian/12" value={alias} onChange={(e) => setAlias(e.target.value)} />
        <button className="btn primary" disabled={!alias} onClick={() => run(`pull ${alias}`, api.pullImage(remote, alias)).then(reload)}>Pull</button>
      </div>
      <div className="table" style={{ gridTemplateColumns: "1.4fr 1.6fr 100px 100px 90px 90px 60px" }}>
        <span className="h">alias</span><span className="h">description</span><span className="h">fingerprint</span><span className="h">type</span><span className="h">size</span><span className="h">uploaded</span><span className="h" />
        {(images ?? []).map((i) => (
          <span key={i.fingerprint} style={{ display: "contents" }}>
            <span className="mono">{i.aliases.map((a) => a.name).join(", ") || "–"}</span>
            <span>{i.properties.description ?? ""}</span>
            <span className="mono muted">{i.fingerprint.slice(0, 12)}</span>
            <span>{i.type}</span>
            <span className="mono">{fmtBytes(i.size)}</span>
            <span className="muted">{fmtAge(i.uploaded_at)}</span>
            <button className="btn danger" style={{ height: 24, padding: "0 8px" }} onClick={() => confirm("Delete image?") && run("delete image", api.deleteImage(i.fingerprint)).then(reload)}>×</button>
          </span>
        ))}
      </div>
      {images && !images.length && <Empty>No images yet</Empty>}
    </Panel>
  );
}

export function Profiles() {
  const { api, run } = useStore();
  const [profiles, reload] = usePoll(() => api.profiles(), [api], 30000);
  const [edit, setEdit] = useState<{ p: Profile; isNew: boolean } | null>(null);
  return (
    <Panel title="Profiles" sub={profiles ? `${profiles.length}` : ""} dense>
      <div style={{ margin: "8px 0" }}><button className="btn primary" onClick={() => setEdit({ p: { name: "", description: "", config: {}, devices: {}, used_by: [] }, isNew: true })}>New profile</button></div>
      <div className="table" style={{ gridTemplateColumns: "140px 1fr 1fr 80px 120px" }}>
        <span className="h">name</span><span className="h">description</span><span className="h">devices</span><span className="h">used by</span><span className="h" />
        {(profiles ?? []).map((p) => (
          <span key={p.name} style={{ display: "contents" }}>
            <span style={{ fontWeight: 500 }}>{p.name}</span>
            <span className="muted">{p.description}</span>
            <span className="mono" style={{ fontSize: 11 }}>{Object.entries(p.devices).map(([n, d]) => `${n}:${d.type}`).join(" ")}</span>
            <span className="mono">{p.used_by.length}</span>
            <span style={{ display: "flex", gap: 4 }}>
              <button className="btn" style={{ height: 24, padding: "0 8px" }} onClick={() => setEdit({ p, isNew: false })}>Edit</button>
              <button className="btn danger" style={{ height: 24, padding: "0 8px" }} disabled={p.name === "default" || p.used_by.length > 0} onClick={() => run(`delete ${p.name}`, api.deleteProfile(p.name)).then(reload)}>×</button>
            </span>
          </span>
        ))}
      </div>
      {edit && <ProfileEditor {...edit} onClose={() => { setEdit(null); reload(); }} />}
    </Panel>
  );
}
function ProfileEditor({ p, isNew, onClose }: { p: Profile; isNew: boolean; onClose: () => void }) {
  const { api, run } = useStore();
  const [prof, setProf] = useState(p);
  return (
    <Dialog title={isNew ? "New profile" : `Profile ${p.name}`} onClose={onClose} wide footer={<button className="btn primary" disabled={!prof.name} onClick={() => run(`save ${prof.name}`, api.saveProfile(prof, isNew)).then(onClose)}>Save</button>}>
      <div style={{ display: "flex", gap: 12 }}>
        <Field label="Name"><input className="input" value={prof.name} disabled={!isNew} onChange={(e) => setProf({ ...prof, name: e.target.value })} /></Field>
        <Field label="Description"><input className="input" value={prof.description} onChange={(e) => setProf({ ...prof, description: e.target.value })} /></Field>
      </div>
      <div className="muted">Config</div>
      <KvEditor value={prof.config} onChange={(c) => setProf({ ...prof, config: c })} />
      <div className="muted">Devices (JSON)</div>
      <textarea className="input" rows={6} value={JSON.stringify(prof.devices, null, 2)} onChange={(e) => { try { setProf({ ...prof, devices: JSON.parse(e.target.value) }); } catch { /* keep typing */ } }} />
    </Dialog>
  );
}

export function Networks() {
  const { api, instances } = useStore();
  const [nets] = usePoll(async () => Promise.all((await api.networks()).map(async (n) => ({ ...n, st: await api.networkState(n.name).catch(() => null) }))), [api], 15000);
  return (
    <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
      <Panel title="Networks" sub={nets ? `${nets.length}` : ""} dense>
        <div className="table" style={{ gridTemplateColumns: "120px 80px 1fr 80px 60px 1fr" }}>
          <span className="h">name</span><span className="h">type</span><span className="h">addresses</span><span className="h">state</span><span className="h">used</span><span className="h">traffic</span>
          {(nets ?? []).map((n) => (
            <span key={n.name} style={{ display: "contents" }}>
              <span style={{ fontWeight: 500 }}>{n.name}</span>
              <span className="muted">{n.type}{n.managed ? "" : " · unmanaged"}</span>
              <span className="mono" style={{ fontSize: 11 }}>{n.st?.addresses.filter((a) => a.family === "inet").map((a) => `${a.address}/${a.netmask}`).join(" ") ?? ""}</span>
              <span className={`chip ${n.st?.state === "up" ? "ok" : ""}`} style={{ justifySelf: "start" }}>{n.st?.state ?? "?"}</span>
              <span className="mono">{n.used_by.length}</span>
              <span className="mono" style={{ fontSize: 11 }}>{n.st ? `↓${fmtBytes(n.st.counters.bytes_received)} ↑${fmtBytes(n.st.counters.bytes_sent)}` : ""}</span>
            </span>
          ))}
        </div>
      </Panel>
      <Panel title="Topology" dense><Topology instances={instances} networks={nets ?? []} /></Panel>
    </div>
  );
}

export function Storage() {
  const { api } = useStore();
  const [pools] = usePoll(async () => Promise.all((await api.pools()).map(async (p) => ({ ...p, res: await api.poolResources(p.name).catch(() => null), vols: await api.volumes(p.name).catch(() => []) }))), [api], 30000);
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      {(pools ?? []).map((p) => {
        const used = p.res?.space.used ?? 0;
        const total = p.res?.space.total ?? 0;
        return (
          <Panel key={p.name} title={p.name} sub={`${p.driver} · ${p.config.source ?? ""}`} value={<span style={{ color: total && used / total > 0.85 ? "var(--err)" : "var(--disk)" }}>{fmtBytes(used)} / {fmtBytes(total)}</span>} dense>
            <div style={{ margin: "6px 0" }}><Bar pct={total ? (used / total) * 100 : 0} color={total && used / total > 0.85 ? "var(--err)" : "var(--disk)"} /></div>
            <div className="table" style={{ gridTemplateColumns: "1fr 120px 120px 80px" }}>
              <span className="h">volume</span><span className="h">type</span><span className="h">content</span><span className="h">used by</span>
              {p.vols.map((v) => (
                <span key={`${v.type}/${v.name}`} style={{ display: "contents" }}>
                  <span className="mono">{v.name}</span><span className="muted">{v.type}</span><span className="muted">{v.content_type}</span><span className="mono">{v.used_by.length}</span>
                </span>
              ))}
              {!p.vols.length && <span className="muted">no volumes</span>}
            </div>
          </Panel>
        );
      })}
      {pools && !pools.length && <Empty>No storage pools</Empty>}
    </div>
  );
}

export function Operations() {
  const { operations, api, run } = useStore();
  const sorted = [...operations].sort((a, b) => b.created_at.localeCompare(a.created_at));
  return (
    <Panel title="Operations" sub={`${operations.filter((o) => o.status === "Running").length} running`} dense>
      <div className="table" style={{ gridTemplateColumns: "1fr 160px 90px 80px 80px" }}>
        <span className="h">description</span><span className="h">resource</span><span className="h">status</span><span className="h">age</span><span className="h" />
        {sorted.map((o) => (
          <span key={o.id} style={{ display: "contents" }}>
            <span>{o.description}</span>
            <span className="mono muted">{Object.values(o.resources ?? {}).flat().map((r) => r.replace(/^\/1\.0\/\w+\//, "")).join(", ")}</span>
            <span className={`chip ${o.status === "Running" ? "brand" : o.status === "Success" ? "ok" : "err"}`} style={{ justifySelf: "start" }}>{o.status}</span>
            <span className="muted">{fmtAge(o.created_at)}</span>
            <span>{o.may_cancel && o.status === "Running" && <button className="btn" style={{ height: 24, padding: "0 8px" }} onClick={() => run("cancel", api.cancelOperation(o.id))}>Cancel</button>}</span>
          </span>
        ))}
      </div>
      {!operations.length && <Empty>No operations</Empty>}
    </Panel>
  );
}

export function Settings() {
  const { api, run, finish, setFinish, site, demo, auth } = useStore();
  const [server] = usePoll(() => api.server(), [api], 60000);
  const [cfg, setCfg] = useState<Record<string, string> | null>(null);
  const config = cfg ?? server?.config ?? {};
  const [prom, setProm] = useState(localStorage.getItem("nixie.prometheus") ?? site.prometheusUrl ?? "");
  return (
    <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
      <Panel title="Appearance" dense>
        <div style={{ display: "flex", gap: 10, margin: "10px 0" }}>
          {finishes.map((f) => (
            <button key={f} className="btn" aria-pressed={finish === f} style={{ height: 40, borderColor: finish === f ? "var(--brand2)" : "var(--line2)", display: "flex", gap: 10, alignItems: "center" }} onClick={() => setFinish(f)}>
              <span style={{ width: 20, height: 20, borderRadius: 4, border: "1px solid var(--line2)", background: f === "graphite" ? "#1f2226" : f === "umber" ? "#231b16" : "#e4e1da" }} />
              {f[0].toUpperCase() + f.slice(1)}
            </button>
          ))}
        </div>
        <p className="muted" style={{ margin: 0 }}>The site's default finish is {site.theme}; this choice is kept in this browser.</p>
      </Panel>
      <Panel title="History source" sub="dashboards" dense>
        <Field label="Prometheus URL (empty: rolling in-browser history only)"><input className="input mono" value={prom} onChange={(e) => { setProm(e.target.value); localStorage.setItem("nixie.prometheus", e.target.value); }} /></Field>
        {site.grafanaUrl && <p className="muted">Grafana: <a href={site.grafanaUrl} style={{ color: "var(--brand2)" }}>{site.grafanaUrl}</a></p>}
      </Panel>
      <Panel title="Daemon" sub={server?.environment?.server_version ?? ""} dense>
        <div className="table" style={{ gridTemplateColumns: "140px 1fr" }}>
          <span className="muted">auth</span><span>{auth}{demo ? " · demo mode" : ""}</span>
          <span className="muted">name</span><span className="mono">{server?.environment?.server_name}</span>
          <span className="muted">kernel</span><span className="mono">{server?.environment?.kernel_version}</span>
          <span className="muted">storage</span><span className="mono">{server?.environment?.storage}</span>
          <span className="muted">auth methods</span><span className="mono">{server?.auth_methods?.join(", ")}</span>
        </div>
        <div className="muted" style={{ marginTop: 8 }}>Server configuration</div>
        <KvEditor value={config} onChange={setCfg} readOnlyKeys={/^$/} />
        <div style={{ display: "flex", justifyContent: "flex-end", marginTop: 8 }}><button className="btn primary" disabled={!cfg} onClick={() => run("save server config", api.updateServer(cfg!)).then(() => setCfg(null))}>Save</button></div>
      </Panel>
      <Panel title="Site" dense>
        <div className="table" style={{ gridTemplateColumns: "140px 1fr" }}>
          <span className="muted">declared guests</span><span className="mono">{Object.keys(site.declared).join(", ") || "none"}</span>
          <span className="muted">site edits</span><span><Toggle on={site.allowSiteEdits} onChange={() => undefined} label={site.allowSiteEdits ? "Declare enabled (nixie.ui.allowSiteEdits)" : "off; set nixie.ui.allowSiteEdits to enable Declare"} /></span>
          <span className="muted">host page</span><span>{site.hostUiUrl ? <a href={site.hostUiUrl} style={{ color: "var(--brand2)" }}>{site.hostUiUrl}</a> : "off (nixie.hostUi.enable)"}</span>
        </div>
      </Panel>
    </div>
  );
}
