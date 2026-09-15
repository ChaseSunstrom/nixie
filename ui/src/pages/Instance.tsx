import { useEffect, useState } from "react";
import { useStore, tier, exportEntry } from "../lib/store";
import { Panel, Dot, go, Sparkline, Bar, KvEditor, usePoll, Empty, Dialog, Field } from "../components/ui";
import { Terminal } from "../components/Terminal";
import { fmtBytes, fmtAge } from "../lib/series";
import type { Instance as I, Snapshot } from "../lib/api";

const TABS = ["overview", "configuration", "devices", "snapshots", "terminal", "logs", "files", "metrics"];

export function InstancePage({ name, tab }: { name: string; tab: string }) {
  const { api, run, history, site, toast } = useStore();
  const [inst, reload] = usePoll(() => api.instance(name), [api, name], 10000);
  const [snaps, reloadSnaps] = usePoll(() => api.snapshots(name), [api, name], 30000);
  const t = TABS.includes(tab) ? tab : "overview";
  if (!inst) return <Empty>Loading {name}…</Empty>;
  const running = inst.status === "Running";
  const act = (a: "start" | "stop" | "restart" | "freeze" | "unfreeze", force = false) => run(`${a} ${name}`, api.instanceAction(name, a, force)).then(reload);
  const addr = inst.state?.network ? Object.values(inst.state.network).flatMap((n) => n.addresses).filter((a) => a.scope === "global").map((a) => a.address).join(" · ") : "";
  const cpuS = history[`cpu.${name}`] ?? [];
  return (
    <div>
      <div className="titlebar">
        <div>
          <div className="crumb">
            <a href="#/instances">Instances</a> /
          </div>
          <h1>
            <Dot status={inst.status} /> {name}
            <span className={`chip ${tier(site, name) === "declared" ? "brand" : "hot"}`} style={{ fontSize: 12 }}>{tier(site, name)}</span>
          </h1>
          <div className="muted" style={{ fontSize: 12 }}>
            {inst.type === "virtual-machine" ? "virtual machine" : "container"} · {inst.status.toLowerCase()} · <span className="mono">{addr || "no address"}</span> · {inst.profiles.map((p) => <span key={p} className="chip" style={{ marginLeft: 4 }}>{p}</span>)}
          </div>
        </div>
        <div className="group">
          {running ? <button className="btn" onClick={() => act("stop")}>Stop</button> : <button className="btn" onClick={() => act("start")}>Start</button>}
          <button className="btn" onClick={() => act("restart")} disabled={!running}>Restart</button>
          {inst.status === "Frozen" ? <button className="btn" onClick={() => act("unfreeze")}>Unfreeze</button> : <button className="btn" onClick={() => act("freeze")} disabled={!running}>Freeze</button>}
          <button className="btn" onClick={() => run(`snapshot ${name}`, api.createSnapshot(name, `snap-${new Date().toISOString().slice(0, 16).replace(/[-:T]/g, "")}`)).then(reloadSnaps)}>Snapshot</button>
          <button className="btn" onClick={() => navigator.clipboard.writeText(exportEntry(inst)).then(() => toast("guests.nix entry copied"))}>Export</button>
          <button className="btn danger" onClick={() => confirm(`Delete ${name}? State in mounted directories is kept.`) && run(`delete ${name}`, api.deleteInstance(name)).then(() => go("instances"))}>Delete</button>
        </div>
      </div>
      <nav className="subnav" aria-label="Instance">
        {TABS.map((x) => (
          <a key={x} href={`#/instances/${name}/${x}`} aria-current={x === t ? "page" : undefined}>
            {x[0].toUpperCase() + x.slice(1)}
            {x === "devices" && <span className="badge">{Object.keys(inst.expanded_devices ?? inst.devices).length}</span>}
            {x === "snapshots" && snaps && <span className="badge">{snaps.length}</span>}
          </a>
        ))}
      </nav>
      {t === "overview" && (
        <div style={{ display: "grid", gridTemplateColumns: "1fr 400px", gap: 12 }}>
          <Panel title="CPU" sub="last samples" value={<span style={{ color: "var(--cpu)" }}>{(cpuS.at(-1) ?? 0).toFixed(0)} %</span>} dense>
            <div className="well"><Sparkline series={cpuS} /></div>
            <div className="table" style={{ gridTemplateColumns: "140px 1fr", marginTop: 8 }}>
              <span className="muted">memory</span><span><Bar pct={inst.state?.memory?.total ? (inst.state.memory.usage / inst.state.memory.total) * 100 : 0} /> <span className="mono">{fmtBytes(inst.state?.memory?.usage ?? 0)}</span></span>
              <span className="muted">disk</span><span className="mono">{Object.entries(inst.state?.disk ?? {}).map(([k, v]) => `${k} ${fmtBytes(v.usage)}`).join(" · ") || "–"}</span>
              <span className="muted">network</span><span className="mono">{Object.entries(inst.state?.network ?? {}).map(([k, v]) => `${k} ↓${fmtBytes(v.counters.bytes_received)} ↑${fmtBytes(v.counters.bytes_sent)}`).join(" · ") || "–"}</span>
              <span className="muted">created</span><span>{fmtAge(inst.created_at)} ago</span>
              <span className="muted">image</span><span className="mono">{inst.config["volatile.base_image"]?.slice(0, 12) ?? "–"}</span>
              <span className="muted">pid</span><span className="mono">{inst.state?.pid ?? "–"}</span>
            </div>
          </Panel>
          <Panel title="Snapshots" sub={snaps ? `${snaps.length}` : ""} dense>
            <SnapshotTable name={name} snaps={snaps ?? []} reload={reloadSnaps} compact />
          </Panel>
        </div>
      )}
      {t === "configuration" && <Configuration inst={inst} reload={reload} />}
      {t === "devices" && <Devices inst={inst} reload={reload} />}
      {t === "snapshots" && <Panel title="Snapshots" dense><SnapshotTable name={name} snaps={snaps ?? []} reload={reloadSnaps} /></Panel>}
      {t === "terminal" && (
        <Panel dense style={{ padding: 0 }}>
          <div className="toolbar"><span>exec · shell · {inst.status.toLowerCase()}</span><span>{running ? "connected over the exec websocket" : "start the instance to open a shell"}</span></div>
          {running ? <Terminal name={name} /> : <Empty>Instance is not running</Empty>}
        </Panel>
      )}
      {t === "logs" && <Logs name={name} />}
      {t === "files" && <Files name={name} />}
      {t === "metrics" && (
        <Panel title="Metrics" sub="from /1.0/metrics while this page is open" dense>
          <div className="well"><Sparkline series={cpuS} /></div>
          <p className="muted">Long history is on the <a href={`#/dashboards/guest/${name}`} style={{ color: "var(--brand2)" }}>guest dashboard</a>.</p>
        </Panel>
      )}
    </div>
  );
}

function Configuration({ inst, reload }: { inst: I; reload: () => void }) {
  const { api, run } = useStore();
  const [config, setConfig] = useState(inst.config);
  const [profiles, setProfiles] = useState(inst.profiles.join(", "));
  const [desc, setDesc] = useState(inst.description ?? "");
  useEffect(() => setConfig(inst.config), [inst]);
  return (
    <Panel title="Configuration" dense>
      <div style={{ display: "flex", gap: 12, marginTop: 8 }}>
        <Field label="Description"><input className="input" value={desc} onChange={(e) => setDesc(e.target.value)} /></Field>
        <Field label="Profiles (comma separated)"><input className="input mono" value={profiles} onChange={(e) => setProfiles(e.target.value)} /></Field>
      </div>
      <KvEditor value={config} onChange={setConfig} />
      <div style={{ display: "flex", justifyContent: "flex-end", marginTop: 8 }}>
        <button className="btn primary" onClick={() => run(`save ${inst.name}`, api.updateInstance(inst.name, { config, description: desc, profiles: profiles.split(",").map((s) => s.trim()).filter(Boolean) })).then(reload)}>Save</button>
      </div>
    </Panel>
  );
}

function Devices({ inst, reload }: { inst: I; reload: () => void }) {
  const { api, run } = useStore();
  const devices = inst.expanded_devices ?? inst.devices;
  const [adding, setAdding] = useState(false);
  const [dname, setDname] = useState("");
  const [dtype, setDtype] = useState("disk");
  const [props, setProps] = useState<Record<string, string>>({});
  const save = (d: Record<string, Record<string, string>>) => run(`devices of ${inst.name}`, api.updateInstance(inst.name, { devices: d })).then(reload);
  return (
    <Panel title="Devices" sub={`${Object.keys(devices).length}`} dense>
      <div className="table" style={{ gridTemplateColumns: "120px 80px 1fr 60px" }}>
        <span className="h">name</span><span className="h">type</span><span className="h">properties</span><span className="h" />
        {Object.entries(devices).map(([n, d]) => (
          <span key={n} style={{ display: "contents" }}>
            <span>{n}</span>
            <span className="mono" style={{ color: "var(--brand2)" }}>{d.type}</span>
            <span className="mono" style={{ fontSize: 11 }}>{Object.entries(d).filter(([k]) => k !== "type").map(([k, v]) => `${k}=${v}`).join("  ")}</span>
            <button className="btn" style={{ height: 24, padding: "0 8px" }} disabled={!(n in inst.devices)} onClick={() => confirm(`Remove device ${n}?`) && save(Object.fromEntries(Object.entries(inst.devices).filter(([k]) => k !== n)))}>×</button>
          </span>
        ))}
      </div>
      <div style={{ marginTop: 8 }}><button className="btn" onClick={() => setAdding(true)}>Add device</button></div>
      {adding && (
        <Dialog title="Add device" onClose={() => setAdding(false)} footer={<button className="btn primary" disabled={!dname} onClick={() => save({ ...inst.devices, [dname]: { type: dtype, ...props } }).then(() => setAdding(false))}>Add</button>}>
          <Field label="Name"><input className="input" value={dname} onChange={(e) => setDname(e.target.value)} /></Field>
          <Field label="Type">
            <select className="input" value={dtype} onChange={(e) => setDtype(e.target.value)}>
              {["disk", "nic", "gpu", "proxy", "unix-char", "unix-block", "usb", "tpm"].map((t) => <option key={t}>{t}</option>)}
            </select>
          </Field>
          <KvEditor value={props} onChange={setProps} readOnlyKeys={/^$/} />
        </Dialog>
      )}
    </Panel>
  );
}

function SnapshotTable({ name, snaps, reload, compact }: { name: string; snaps: Snapshot[]; reload: () => void; compact?: boolean }) {
  const { api, run } = useStore();
  return (
    <div className="table" style={{ gridTemplateColumns: compact ? "1fr auto auto" : "1fr 160px 100px 100px 180px" }}>
      <span className="h">name</span><span className="h">created</span>{!compact && <span className="h">size</span>}{!compact && <span className="h">expires</span>}<span className="h" />
      {snaps.map((s) => (
        <span key={s.name} style={{ display: "contents" }}>
          <span className="mono">{s.name}</span>
          <span className="muted">{fmtAge(s.created_at)} ago</span>
          {!compact && <span className="mono">{s.size ? fmtBytes(s.size) : "–"}</span>}
          {!compact && <span className="muted">{s.expires_at && !s.expires_at.startsWith("0001") ? fmtAge(s.expires_at) : "never"}</span>}
          <span style={{ display: "flex", gap: 4 }}>
            <button className="btn" style={{ height: 24, padding: "0 8px" }} onClick={() => confirm(`Restore ${name} to ${s.name}?`) && run(`restore ${s.name}`, api.restoreSnapshot(name, s.name))}>Restore</button>
            <button className="btn danger" style={{ height: 24, padding: "0 8px" }} onClick={() => run(`delete ${s.name}`, api.deleteSnapshot(name, s.name)).then(reload)}>Delete</button>
          </span>
        </span>
      ))}
      {!snaps.length && <span className="muted">no snapshots</span>}
    </div>
  );
}

function Logs({ name }: { name: string }) {
  const { api } = useStore();
  const [files] = usePoll(() => api.logs(name), [api, name], 30000);
  const [file, setFile] = useState<string>("");
  const [text, setText] = useState("");
  useEffect(() => {
    if (!file) return;
    api.log(name, file.replace(/^.*\//, "")).then(setText).catch((e) => setText(String(e)));
  }, [api, name, file]);
  return (
    <Panel title="Logs" dense style={{ padding: 0 }}>
      <div className="toolbar">
        <select className="input" style={{ height: 26 }} value={file} onChange={(e) => setFile(e.target.value)}>
          <option value="">choose a log</option>
          {(files ?? []).map((f) => <option key={f} value={f}>{f.replace(/^.*\//, "")}</option>)}
        </select>
        <span>{file ? "tail" : ""}</span>
      </div>
      <pre className="well term" style={{ whiteSpace: "pre-wrap", overflow: "auto", maxHeight: 520 }}>{file ? text || "this log is empty" : "select a log file"}</pre>
    </Panel>
  );
}

function Files({ name }: { name: string }) {
  const { api, toast } = useStore();
  const [path, setPath] = useState("/");
  const [entries, setEntries] = useState<string[]>([]);
  const [content, setContent] = useState<string | null>(null);
  const load = (p: string) => api.files(name, p).then((r) => {
    setPath(p);
    if (Array.isArray(r)) { setEntries(r); setContent(null); } else { setEntries([]); setContent(r.content); }
  }).catch((e) => toast(String(e.message), true));
  useEffect(() => { void load("/"); }, [name]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <Panel title="Files" sub={path} dense>
      <div style={{ display: "flex", gap: 8, margin: "8px 0" }}>
        <input className="input mono" style={{ flex: 1 }} value={path} onChange={(e) => setPath(e.target.value)} onKeyDown={(e) => e.key === "Enter" && load(path)} />
        <button className="btn" onClick={() => load(path.replace(/\/[^/]*\/?$/, "") || "/")}>Up</button>
        {content !== null && <button className="btn primary" onClick={() => api.putFile(name, path, content).then(() => toast("saved")).catch((e) => toast(String(e.message), true))}>Save</button>}
      </div>
      {content === null ? (
        <div className="table" style={{ gridTemplateColumns: "1fr" }}>
          {entries.map((e) => <a key={e} className="mono" onClick={() => load(`${path.replace(/\/$/, "")}/${e}`)}>{e}</a>)}
          {!entries.length && <span className="muted">empty directory</span>}
        </div>
      ) : (
        <textarea className="input" rows={24} value={content} onChange={(e) => setContent(e.target.value)} />
      )}
    </Panel>
  );
}
