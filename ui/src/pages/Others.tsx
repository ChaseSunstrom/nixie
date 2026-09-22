// Images, Profiles, Networks, Storage, Operations and Settings: the parts of
// the daemon the design names but does not draw, in the same recipes.
import { useState } from "react";
import { useStore } from "../lib/store";
import { Panel, PageHead, usePoll, Empty, Dialog, Field, KvEditor, Bar, Toggle } from "../components/ui";
import { fmtBytes, fmtAge } from "../lib/series";
import type { Profile } from "../lib/api";
import { finishes } from "../tokens";
import { RANGES } from "../lib/series";
import { PAGES } from "../components/Palette";
import { STATS, UI_KEY, overviewLayout, type UiConfig } from "../lib/ui-config";
import { Topology } from "../components/Topology";

export function Images() {
  const { api, run } = useStore();
  const [images, reload] = usePoll(() => api.images(), [api], 30000);
  const [alias, setAlias] = useState("");
  const [remote, setRemote] = useState("https://images.linuxcontainers.org");
  return (
    <>
    <PageHead title="Images" count={images?.length} sub="What new instances start from, pulled from an image server.">
      <input className="input mono" style={{ width: 300 }} value={remote} onChange={(e) => setRemote(e.target.value)} aria-label="remote" />
      <input className="input mono" placeholder="alias, e.g. debian/12" value={alias} onChange={(e) => setAlias(e.target.value)} />
      <button className="btn primary" disabled={!alias} onClick={() => run(`pull ${alias}`, api.pullImage(remote, alias)).then(reload)}>Pull</button>
    </PageHead>
    <Panel dense>
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
    </>
  );
}

export function Profiles() {
  const { api, run } = useStore();
  const [profiles, reload] = usePoll(() => api.profiles(), [api], 30000);
  const [edit, setEdit] = useState<{ p: Profile; isNew: boolean } | null>(null);
  return (
    <>
    <PageHead title="Profiles" count={profiles?.length} sub="Configuration and devices that instances share.">
      <button className="btn primary" onClick={() => setEdit({ p: { name: "", description: "", config: {}, devices: {}, used_by: [] }, isNew: true })}>New profile</button>
    </PageHead>
    <Panel dense>
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
    </>
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
    <>
    <PageHead title="Networks" count={nets?.length} sub="The bridge guests share, and what is attached to it." />
    <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
      <Panel title="Interfaces" dense>
        <div className="table" style={{ gridTemplateColumns: "100px 150px 1fr 56px 40px 1fr" }}>
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
    </>
  );
}

export function Storage() {
  const { api } = useStore();
  const [pools] = usePoll(async () => Promise.all((await api.pools()).map(async (p) => ({ ...p, res: await api.poolResources(p.name).catch(() => null), vols: await api.volumes(p.name).catch(() => []) }))), [api], 30000);
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      <PageHead title="Storage" count={pools?.length} sub="Storage pools and the volumes in them." />
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
    <>
    <PageHead title="Operations" count={`${operations.filter((o) => o.status === "Running").length} running`} sub="What the daemon is doing, and what it did." />
    <Panel dense>
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
    </>
  );
}

export function Settings() {
  const { api, run, finish, setFinish, site, demo, auth, ui, saveUi } = useStore();
  const [server] = usePoll(() => api.server(), [api], 60000);
  const [cfg, setCfg] = useState<Record<string, string> | null>(null);
  const config = cfg ?? server?.config ?? {};
  const [prom, setProm] = useState(localStorage.getItem("nixie.prometheus") ?? site.prometheusUrl ?? "");
  // Edits stay a draft until saved, so a half-made layout never reaches
  // the other browsers.
  const [draft, setDraft] = useState<UiConfig | null>(null);
  const d = draft ?? ui;
  const edit = (patch: Partial<UiConfig>) => setDraft({ ...d, ...patch });
  const layout = overviewLayout(d.overview);
  const setLayout = (l: typeof layout) => edit({ overview: l.map(({ id, span, hidden }) => ({ id, span, hidden })) });
  const move = (i: number, j: number) => {
    const l = [...layout];
    const [p] = l.splice(i, 1);
    l.splice(j, 0, p);
    setLayout(l);
  };
  const stats = d.stats ?? STATS.map(([id]) => id);
  const hiddenPages = d.hiddenPages ?? [];
  const links = d.links ?? [];
  const ownFinish = localStorage.getItem("nixie.finish");
  const swatch = (f: string) => (f === "graphite" ? "#1f2226" : f === "umber" ? "#231b16" : "#e4e1da");
  return (
    <>
    <PageHead title="Settings" sub="Saved on this host for every browser. They start from the site's nixie.ui.* settings; Reset goes back to those.">
      {draft && <span className="chip hot">unsaved changes</span>}
      <button className="btn" disabled={!draft} onClick={() => setDraft(null)}>Discard</button>
      <button className="btn" onClick={() => confirm("Reset the control panel settings to the site's defaults for every browser?") && run("reset panel settings", saveUi({})).then(() => setDraft(null))}>Reset</button>
      <button className="btn primary" disabled={!draft} onClick={() => run("save panel settings", saveUi(d)).then(() => setDraft(null))}>Save</button>
    </PageHead>
    <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>

      <Panel title="Appearance" dense>
        <div style={{ display: "flex", gap: 10, margin: "10px 0" }}>
          {finishes.map((f) => (
            <button key={f} className="btn" aria-pressed={finish === f} style={{ height: 40, borderColor: finish === f ? "var(--brand2)" : "var(--line2)", display: "flex", gap: 10, alignItems: "center" }} onClick={() => setFinish(f)}>
              <span style={{ width: 20, height: 20, borderRadius: 4, border: "1px solid var(--line2)", background: swatch(f) }} />
              {f[0].toUpperCase() + f.slice(1)}
            </button>
          ))}
        </div>
        <p className="muted" style={{ margin: "0 0 8px" }}>
          Every browser starts in {d.theme ?? site.theme} ({d.theme ? "set here" : "the site's nixie.ui.theme"}). {ownFinish ? `This browser keeps ${ownFinish}.` : "This browser follows that."}
        </p>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          <button className="btn" disabled={d.theme === finish} onClick={() => edit({ theme: finish })}>Start every browser in {finish}</button>
          <button className="btn" disabled={!ownFinish} onClick={() => setFinish(null)}>This browser follows the default</button>
        </div>
        <div style={{ marginTop: 12 }}>
          <Field label="Name shown beside the wordmark (empty: none)"><input className="input" value={d.title ?? ""} placeholder={server?.environment?.server_name ?? ""} onChange={(e) => edit({ title: e.target.value || undefined })} /></Field>
        </div>
      </Panel>

      <Panel title="Header" dense>
        <div className="muted" style={{ margin: "8px 0 6px" }}>Figures shown</div>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8 }}>
          {STATS.map(([id, label]) => (
            <Toggle key={id} on={stats.includes(id)} label={label} onChange={(on) => edit({ stats: STATS.map(([x]) => x).filter((x) => (x === id ? on : stats.includes(x))) })} />
          ))}
        </div>
        <div className="muted" style={{ margin: "14px 0 6px" }}>Time range a browser starts with</div>
        <div className="tray" style={{ alignSelf: "flex-start" }}>
          {Object.keys(RANGES).map((r) => (
            <button key={r} className="seg" aria-pressed={(d.range ?? "1h") === r} onClick={() => edit({ range: r })}>{r}</button>
          ))}
        </div>
      </Panel>

      <Panel title="Overview" sub="which panels, in what order, how wide" dense>
        <div className="table" style={{ gridTemplateColumns: "44px 1fr 120px 70px" }}>
          <span className="h">show</span>
          <span className="h">panel</span>
          <span className="h">width</span>
          <span className="h">order</span>
          {layout.map((p, i) => (
            <span key={p.id} style={{ display: "contents" }}>
              <Toggle on={!p.hidden} label="" ariaLabel={`show ${p.title}`} onChange={(on) => setLayout(layout.map((x) => (x.id === p.id ? { ...x, hidden: !on } : x)))} />
              <span style={{ color: p.hidden ? "var(--muted)" : undefined }}>{p.title}</span>
              <select className="input" style={{ height: 26 }} value={p.span} aria-label={`${p.title} width`} onChange={(e) => setLayout(layout.map((x) => (x.id === p.id ? { ...x, span: Number(e.target.value) } : x)))}>
                {[3, 4, 5, 6, 7, 8, 9, 12].map((n) => <option key={n} value={n}>{n === 12 ? "full width" : `${n} of 12`}</option>)}
              </select>
              <span style={{ display: "flex", gap: 2 }}>
                <button className="btn icon" style={{ height: 24, width: 28 }} aria-label={`move ${p.title} up`} disabled={i === 0} onClick={() => move(i, i - 1)}>↑</button>
                <button className="btn icon" style={{ height: 24, width: 28 }} aria-label={`move ${p.title} down`} disabled={i === layout.length - 1} onClick={() => move(i, i + 1)}>↓</button>
              </span>
            </span>
          ))}
        </div>
      </Panel>

      <Panel title="Navigation" dense>
        <div className="muted" style={{ margin: "8px 0 6px" }}>Pages in the bar (all stay in the command palette)</div>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8 }}>
          {PAGES.filter((p) => p !== "Settings").map((p) => (
            <Toggle key={p} on={!hiddenPages.includes(p)} label={p} onChange={(on) => edit({ hiddenPages: on ? hiddenPages.filter((x) => x !== p) : [...hiddenPages, p] })} />
          ))}
        </div>
        <div className="muted" style={{ margin: "14px 0 6px" }}>Extra links{site.links.length ? ` (after the site's own: ${site.links.map((l) => l.label).join(", ")})` : ""}</div>
        {links.map((l, i) => (
          <div key={i} style={{ display: "grid", gridTemplateColumns: "1fr 2fr 32px", gap: 6, marginBottom: 6 }}>
            <input className="input" placeholder="label" value={l.label} onChange={(e) => edit({ links: links.map((x, j) => (j === i ? { ...x, label: e.target.value } : x)) })} />
            <input className="input mono" placeholder="https://…" value={l.url} onChange={(e) => edit({ links: links.map((x, j) => (j === i ? { ...x, url: e.target.value } : x)) })} />
            <button className="btn icon" aria-label="remove link" onClick={() => edit({ links: links.filter((_, j) => j !== i) })}>×</button>
          </div>
        ))}
        <button className="btn" style={{ alignSelf: "flex-start" }} onClick={() => edit({ links: [...links, { label: "", url: "" }] })}>Add link</button>
      </Panel>

      <Panel title="History source" sub="dashboards" dense>
        <Field label="Prometheus URL (empty: rolling in-browser history only)"><input className="input mono" value={prom} onChange={(e) => { setProm(e.target.value); localStorage.setItem("nixie.prometheus", e.target.value); }} /></Field>
        {site.grafanaUrl && <p className="muted">Grafana: <a href={site.grafanaUrl} style={{ color: "var(--brand2)" }}>{site.grafanaUrl}</a></p>}
      </Panel>
      <Panel title="Site" dense>
        <div className="table" style={{ gridTemplateColumns: "140px 1fr" }}>
          <span className="muted">declared guests</span><span className="mono">{Object.keys(site.declared).join(", ") || "none"}</span>
          <span className="muted">site edits</span><span><Toggle on={site.allowSiteEdits} onChange={() => undefined} label={site.allowSiteEdits ? "Declare enabled (nixie.ui.allowSiteEdits)" : "off; set nixie.ui.allowSiteEdits to enable Declare"} /></span>
          <span className="muted">host page</span><span>{site.hostUiUrl ? <a href={site.hostUiUrl} style={{ color: "var(--brand2)" }}>{site.hostUiUrl}</a> : "off (nixie.hostUi.enable)"}</span>
        </div>
      </Panel>
      <Panel title="Daemon" sub={server?.environment?.server_version ?? ""} dense style={{ gridColumn: "span 2" }}>
        <div className="table" style={{ gridTemplateColumns: "140px 1fr" }}>
          <span className="muted">auth</span><span>{auth}{demo ? " · demo mode" : ""}</span>
          <span className="muted">name</span><span className="mono">{server?.environment?.server_name}</span>
          <span className="muted">kernel</span><span className="mono">{server?.environment?.kernel_version}</span>
          <span className="muted">storage</span><span className="mono">{server?.environment?.storage}</span>
          <span className="muted">auth methods</span><span className="mono">{server?.auth_methods?.join(", ")}</span>
        </div>
        <div className="muted" style={{ marginTop: 8 }}>Server configuration ({UI_KEY} holds the settings above)</div>
        <KvEditor value={config} onChange={setCfg} readOnlyKeys={/^$/} />
        <div style={{ display: "flex", justifyContent: "flex-end", marginTop: 8 }}><button className="btn primary" disabled={!cfg} onClick={() => run("save server config", api.updateServer(cfg!)).then(() => setCfg(null))}>Save</button></div>
      </Panel>
    </div>
    </>
  );
}
