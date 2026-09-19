import { useState } from "react";
import { useStore, tier, exportEntry } from "../lib/store";
import { Panel, PageHead, Dot, go, Dialog, Field, Empty, usePoll } from "../components/ui";
import { fmtBytes, fmtAge } from "../lib/series";
import { address, type Instance } from "../lib/api";

export function Instances() {
  const { instances, site, api, run, toast } = useStore();
  const [sel, setSel] = useState<Set<string>>(new Set());
  const [exporting, setExporting] = useState<Instance | null>(null);
  const toggle = (n: string) => setSel((s) => {
    const c = new Set(s);
    c.has(n) ? c.delete(n) : c.add(n);
    return c;
  });
  const bulk = (action: "start" | "stop" | "restart" | "freeze" | "unfreeze") => Promise.all([...sel].map((n) => run(`${action} ${n}`, api.instanceAction(n, action, action === "stop"))));
  // Declaring writes the site and applies, and incusd -- which serves this
  // panel -- runs nothing on the host. The host page does, with the person
  // already signed in to it, so Declare opens it there.
  const declare = (i: Instance) => {
    window.open(`${site.hostUiUrl}/nixie-history#declare=${encodeURIComponent(i.name)}`, "_blank", "noopener");
    toast(`${i.name}: finish on the host page`);
  };
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      <PageHead title="Instances" count={instances.length} sub="Declared guests come from the site; scratch ones were made here and apply leaves them alone.">
          {sel.size > 0 && (
            <div className="group">
              <button className="btn" onClick={() => bulk("start")}>Start</button>
              <button className="btn" onClick={() => bulk("stop")}>Stop</button>
              <button className="btn" onClick={() => bulk("restart")}>Restart</button>
              <button className="btn" onClick={() => bulk("freeze")}>Freeze</button>
              <button className="btn danger" onClick={() => confirm(`Delete ${sel.size} instance(s)?`) && Promise.all([...sel].map((n) => run(`delete ${n}`, api.deleteInstance(n))))}>Delete</button>
            </div>
          )}
          <button className="btn primary" onClick={() => go("instances/new")}>Create</button>
      </PageHead>
      <Panel dense style={{ padding: 0 }}>
        <div className="table" style={{ gridTemplateColumns: "28px 1.4fr 90px 100px 1fr 90px 100px 80px 150px", padding: "0 14px" }}>
          <span className="h" />
          <span className="h">name</span>
          <span className="h">type</span>
          <span className="h">status</span>
          <span className="h">address · profiles</span>
          <span className="h">memory</span>
          <span className="h">tier</span>
          <span className="h">age</span>
          <span className="h" />
          {instances.map((i) => {
            const addr = address(i.state);
            const t = tier(site, i.name);
            return (
              <span key={i.name} style={{ display: "contents" }}>
                <input type="checkbox" checked={sel.has(i.name)} onChange={() => toggle(i.name)} aria-label={`select ${i.name}`} />
                <a href={`#/instances/${i.name}`} style={{ display: "flex", alignItems: "center", gap: 8, fontWeight: 500 }}>
                  <Dot status={i.status} /> {i.name}
                </a>
                <span className="muted">{i.type === "virtual-machine" ? "VM" : "container"}</span>
                <span>{i.status}</span>
                <span>
                  <span className="mono">{addr}</span> {i.profiles.filter((p) => p !== "default").map((p) => <span key={p} className="chip" style={{ marginLeft: 4 }}>{p}</span>)}
                </span>
                <span className="mono">{i.state?.memory?.usage ? fmtBytes(i.state.memory.usage) : "–"}</span>
                <span className={`chip ${t === "declared" ? "brand" : "hot"}`} style={{ justifySelf: "start" }}>{t}</span>
                <span className="muted">{fmtAge(i.created_at)}</span>
                <span style={{ display: "flex", gap: 4 }}>
                  <button className="btn" style={{ height: 24, padding: "0 8px" }} onClick={() => setExporting(i)}>Export</button>
                  {t === "scratch" && site.allowSiteEdits && site.hostUiUrl && <button className="btn" style={{ height: 24, padding: "0 8px" }} onClick={() => declare(i)}>Declare</button>}
                </span>
              </span>
            );
          })}
        </div>
        {!instances.length && <Empty>No instances. Create one, or declare guests in the site.</Empty>}
      </Panel>
      {exporting && (
        <Dialog title={`Export ${exporting.name} to guests.nix`} onClose={() => setExporting(null)} wide footer={<button className="btn" onClick={() => navigator.clipboard.writeText(exportEntry(exporting)).then(() => toast("copied"))}>Copy</button>}>
          <p className="muted" style={{ margin: 0 }}>Paste this into the site's guests.nix and run nixie apply. Names must stay unique.</p>
          <textarea className="input" readOnly rows={14} value={exportEntry(exporting)} />
        </Dialog>
      )}
    </div>
  );
}

export function CreateInstance() {
  const { api, run } = useStore();
  const [name, setName] = useState("");
  const [type, setType] = useState("container");
  const [image, setImage] = useState("");
  const [profile, setProfile] = useState("default");
  const [images] = usePoll(() => api.images(), [api], 60000);
  const [profiles] = usePoll(() => api.profiles(), [api], 60000);
  const create = async () => {
    const src = image.includes("/") && !images?.some((i) => i.aliases.some((a) => a.name === image)) ? { type: "image", mode: "pull", server: "https://images.linuxcontainers.org", protocol: "simplestreams", alias: image } : { type: "image", alias: image };
    const r = await run(`create ${name}`, api.createInstance({ name, type, source: src, profiles: [profile], start: true }));
    if (r) go(`instances/${name}`);
  };
  return (
    <>
    <PageHead title="New instance" sub="A scratch instance: real, but not in the site. Export or Declare keeps it across reinstalls." />
    <Panel style={{ maxWidth: 560 }}>
      <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
        <Field label="Name"><input className="input" value={name} onChange={(e) => setName(e.target.value)} placeholder="lowercase, dashes" /></Field>
        <Field label="Type">
          <select className="input" value={type} onChange={(e) => setType(e.target.value)}>
            <option value="container">Container</option>
            <option value="virtual-machine">Virtual machine</option>
          </select>
        </Field>
        <Field label="Image (local alias, or remote alias like debian/12 to pull)">
          <input className="input mono" list="images" value={image} onChange={(e) => setImage(e.target.value)} />
          <datalist id="images">{(images ?? []).flatMap((i) => i.aliases.map((a) => <option key={a.name} value={a.name} />))}</datalist>
        </Field>
        <Field label="Profile">
          <select className="input" value={profile} onChange={(e) => setProfile(e.target.value)}>
            {(profiles ?? [{ name: "default" }]).map((p) => <option key={p.name} value={p.name}>{p.name}</option>)}
          </select>
        </Field>
        <div style={{ display: "flex", gap: 8, justifyContent: "flex-end" }}>
          <button className="btn" onClick={() => go("instances")}>Cancel</button>
          <button className="btn primary" disabled={!name || !image} onClick={create}>Create and start</button>
        </div>
      </div>
    </Panel>
    </>
  );
}
