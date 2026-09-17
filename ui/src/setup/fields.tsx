// One option as a form field: its plain label, the first sentence of its
// description with the rest behind "More", and a control for its type.
import { useEffect, useState, type ReactNode } from "react";
import { Toggle } from "../components/ui";
import { api, type Device, type Opt } from "./api";

const firstSentence = (s: string) => {
  const t = s.trim().replace(/\s+/g, " ");
  const m = /^(.+?[.!?])(\s|$)/.exec(t);
  return m ? m[1] : t;
};

function Help({ o }: { o: Opt }) {
  const [open, setOpen] = useState(false);
  const full = o.description.trim().replace(/\s+/g, " ");
  const short = firstSentence(o.description);
  // "Keyboard layout." under "Keyboard layout" says nothing.
  if (full.replace(/\.$/, "").toLowerCase() === (o.label ?? "").toLowerCase()) return null;
  return (
    <div className="caption field-help">
      {open ? full : short}
      {full.length > short.length && <button className="link" onClick={() => setOpen(!open)}>{open ? "Less" : "More"}</button>}
    </div>
  );
}

// The machine's own time zones as a real dropdown, by region. A datalist only
// suggests what matches the text already in the field, so with the default
// "UTC" in it the list was empty until the field was cleared.
function ZoneSelect({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const [zones, setZones] = useState<string[]>([]);
  useEffect(() => { api.timezones().then((r) => setZones(r.zones)).catch(() => undefined); }, []);
  const current = value || "UTC";
  const all = zones.includes(current) ? zones : [current, ...zones];
  const regions = new Map<string, string[]>();
  for (const z of all) {
    const r = z.includes("/") ? z.slice(0, z.indexOf("/")) : "";
    regions.set(r, [...(regions.get(r) ?? []), z]);
  }
  const city = (z: string, r: string) => (r ? z.slice(r.length + 1) : z).replaceAll("_", " ");
  return (
    <select className="input" value={current} onChange={(e) => onChange(e.target.value)}>
      {[...regions].map(([r, list]) =>
        r ? (
          <optgroup key={r} label={r}>{list.map((z) => <option key={z} value={z}>{city(z, r)}</option>)}</optgroup>
        ) : (
          list.map((z) => <option key={z} value={z}>{z}</option>)
        ),
      )}
    </select>
  );
}

// What each TPM measurement covers, in the order and with the meaning
// systemd gives them; 7 is the one the option defaults to.
const PCRS: [number, string][] = [
  [0, "Firmware code"],
  [1, "Firmware settings"],
  [2, "Add-in card firmware"],
  [3, "Add-in card settings"],
  [4, "Boot loader and kernel"],
  [5, "Boot loader settings, partition table"],
  [6, "Platform state"],
  [7, "Secure Boot state (recommended)"],
  [8, "Boot loader commands"],
  [9, "Kernel and initrd"],
  [10, "Integrity measurements"],
  [11, "Unified kernel image"],
  [12, "Kernel command line"],
  [13, "System extensions"],
  [14, "Shim certificates"],
  [15, "System identity"],
];

function PcrChecks({ value, onChange }: { value: number[]; onChange: (v: number[]) => void }) {
  // A value the site set beyond this list is still shown, so saving never drops it.
  const known = PCRS.map(([n]) => n);
  const items: [number, string][] = [...PCRS, ...value.filter((n) => !known.includes(n)).map((n): [number, string] => [n, "Set in the site"])];
  const toggle = (n: number) => onChange((value.includes(n) ? value.filter((x) => x !== n) : [...value, n]).sort((a, b) => a - b));
  return (
    <div className="pcrs">
      {items.map(([n, what]) => (
        <label key={n} className="pcr" data-on={value.includes(n)}>
          <input type="checkbox" checked={value.includes(n)} onChange={() => toggle(n)} />
          <span className="mono">{n}</span>
          <span>{what}</span>
        </label>
      ))}
    </div>
  );
}

const gb = (n: number) => (n >= 1e9 ? `${(n / 1e9).toFixed(n >= 1e10 ? 0 : 1)} GB` : `${Math.round(n / 1e6)} MB`);

// Where a folder goes: typed, or picked from the disks and drives this
// machine can see. Picking one mounts it, so what lands in the field is a
// directory that exists.
export function PathPicker({ value, onChange, placeholder }: { value: string; onChange: (v: string) => void; placeholder?: string }) {
  const [devices, setDevices] = useState<Device[] | null>(null);
  const [err, setErr] = useState("");
  const [busy, setBusy] = useState("");
  const open = () => {
    setErr("");
    if (devices) return setDevices(null);
    api.devices().then((r) => setDevices(r.devices)).catch((e) => setErr((e as Error).message));
  };
  const use = (d: Device) => {
    setBusy(d.path);
    api.mount(d.path)
      .then((r) => { onChange(`${r.mountpoint.replace(/\/$/, "")}/nixie`); setDevices(null); })
      .catch((e) => setErr((e as Error).message))
      .finally(() => setBusy(""));
  };
  return (
    <>
      <div className="row tight">
        <input className="input mono" value={value} placeholder={placeholder} onChange={(e) => onChange(e.target.value)} />
        <button type="button" className="btn" aria-expanded={devices !== null} onClick={open}>Choose a drive</button>
      </div>
      {devices !== null && (
        <div className="picker reveal">
          {devices.length === 0 && <div className="caption">No drive this machine can write to. Plug one in and choose again.</div>}
          {devices.map((d) => (
            <button type="button" key={d.path} className="pick" disabled={busy !== ""} onClick={() => use(d)}>
              <span className="pick-name">{d.label || d.model || d.path}</span>
              <span className="caption">{gb(d.size)} · {d.fstype}{d.removable ? " · removable" : ""}{d.mountpoint ? ` · at ${d.mountpoint}` : ""}</span>
            </button>
          ))}
        </div>
      )}
      {err && <div className="caption err">{err}</div>}
    </>
  );
}

export function OptionField({ o, value, onChange, locked }: { o: Opt; value: unknown; onChange: (v: unknown) => void; locked?: boolean }) {
  const label = o.label ?? o.path.replace(/^nixie\./, "");
  // Structured entries (monitors) have no form here; the editor on the review step takes them.
  if (o.type.includes("submodule")) return null;
  const row = (control: ReactNode) => (
    <div className="field">
      <div className="field-label">{label}</div>
      {control}
      <Help o={o} />
    </div>
  );
  if (o.type === "boolean")
    return (
      <div className="field" data-locked={locked || undefined}>
        <Toggle on={Boolean(value)} onChange={locked ? () => undefined : onChange} label={<span className="field-label">{label}{locked && <span className="chip brand">hardened</span>}</span>} />
        <Help o={o} />
      </div>
    );
  if (o.picker === "timezone") return row(<ZoneSelect value={value == null ? "" : String(value)} onChange={onChange} />);
  if (o.picker === "pcrs") return row(<PcrChecks value={Array.isArray(value) ? value.map(Number) : []} onChange={onChange} />);
  if (o.picker === "path") return row(<PathPicker value={value == null ? "" : String(value)} onChange={(v) => onChange(v || null)} placeholder={o.default ? String(o.default) : undefined} />);
  if (o.values.length) return row(<div className="tray" style={{ alignSelf: "flex-start" }}>{o.values.map((v) => <button key={v} className="seg" aria-pressed={value === v} onClick={() => onChange(v)}>{v}</button>)}</div>);
  if (o.type.startsWith("list of"))
    return row(<textarea className="input" rows={3} placeholder="one per line" value={Array.isArray(value) ? value.join("\n") : ""} onChange={(e) => { const l = e.target.value.split("\n").map((s) => s.trim()).filter(Boolean); onChange(o.type.includes("integer") ? l.map(Number).filter(Number.isInteger) : l); }} />);
  if (o.type.includes("integer") || o.type.includes("port")) return row(<input className="input mono" type="number" value={value == null ? "" : String(value)} onChange={(e) => onChange(e.target.value === "" ? null : Number(e.target.value))} />);
  return row(<input className="input mono" value={value == null ? "" : String(value)} onChange={(e) => onChange(e.target.value || null)} />);
}

// A step's options: the essentials, then the rest behind "More options".
// A hardened setup walks through every one of them instead, with the ones it
// turns on shown as locked.
export function OptionGroup({ opts, values, set, children, expanded, locked }: { opts: Opt[]; values: Record<string, unknown>; set: (k: string, v: unknown) => void; children?: ReactNode; expanded?: boolean; locked?: (o: Opt) => boolean }) {
  const [more, setMore] = useState(false);
  const field = (o: Opt) => <OptionField key={o.path} o={o} value={values[o.path]} onChange={(v) => set(o.path, v)} locked={locked?.(o)} />;
  const essential = opts.filter((o) => !o.advanced);
  const rest = opts.filter((o) => o.advanced);
  if (expanded)
    return (
      <div className="fields">
        {essential.map(field)}
        {children}
        {rest.map(field)}
      </div>
    );
  return (
    <div className="fields">
      {essential.map(field)}
      {children}
      {rest.length > 0 && (
        <>
          <button className="btn more" aria-expanded={more} onClick={() => setMore(!more)}>{more ? "Fewer options" : `More options (${rest.length})`}</button>
          {more && <div className="fields reveal">{rest.map(field)}</div>}
        </>
      )}
    </div>
  );
}
