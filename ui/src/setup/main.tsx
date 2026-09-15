// The installer wizard: every step is an option section or a phase, rendered
// from the option metadata the backend serves. It never does anything the
// CLI cannot; it only calls the phase scripts.
import { useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { applyFinish, finishes, type Finish } from "../tokens";
import { Mark, Panel, Toggle, Field } from "../components/ui";
import { api, type Opt, type Hardware, type State } from "./api";
import "../tokens/base.css";

const SECTIONS: { id: string; title: string; blurb: string }[] = [
  { id: "profile", title: "Profile", blurb: "What this machine is for." },
  { id: "hardware", title: "Hardware", blurb: "The disk to install on, the ports that join the bridge, what was found." },
  { id: "site", title: "Site", blurb: "Where this machine's configuration lives: a new site here, a git URL, or an upload." },
  { id: "security", title: "Security", blurb: "Each feature is optional. Turning one on later is a config change and an apply, except full-disk encryption." },
  { id: "auth", title: "Authentication", blurb: "The administrator account, keys, and the second factor for the host page." },
  { id: "network", title: "Network", blurb: "Name, bridge, address, Tailscale and where guests go out." },
  { id: "desktop", title: "Desktop", blurb: "The session, look and packages." },
  { id: "review", title: "Review", blurb: "The files that will be written: the same a Nix user writes by hand." },
  { id: "install", title: "Install", blurb: "Partition, format and install, then reboot into the setup generation." },
];
const CONT = [
  { n: 4, title: "First boot", blurb: "The installed system is up." },
  { n: 5, title: "Secure Boot", blurb: "Enrol the keys from Setup Mode." },
  { n: 6, title: "TPM and attestation", blurb: "Bind the outer layer to this machine with a PIN, start attestation, save the header backup." },
  { n: 7, title: "Verify", blurb: "Reboot and prove every feature did its job." },
  { n: 8, title: "Apply", blurb: "Guests, data and services from the site." },
];
// A desktop has no guest bridge and no Incus; NetworkManager configures it.
const SERVER_ONLY = /^nixie\.(incus\.|network\.(address|gateway|dns|bridge\.|egress|exitNode))/;
// Without a TPM these cannot work, so the step does not offer them.
const TPM_ONLY = /^nixie\.security\.(tpm|attestation)\./;
// Set by the wizard itself from what is typed elsewhere on the page.
const WIZARD_WRITES = ["nixie.network.tailscale.authKeyFile"];
const SECRET_LABEL: Record<string, string> = { passphrase: "Disk passphrase (asked every boot)", pin: "TPM PIN", duress: "Duress passphrase (destroys the disk if typed at boot)", tailscale: "Tailscale auth key", password: "Administrator password" };

function Bytes({ b }: { b: number }) {
  return <span className="mono">{(b / 1e9).toFixed(0)} GB</span>;
}

function OptionField({ o, value, onChange }: { o: Opt; value: unknown; onChange: (v: unknown) => void }) {
  const desc = <div className="caption" style={{ whiteSpace: "pre-line", maxWidth: 640 }}>{o.description.trim()}</div>;
  const name = o.path.replace(/^nixie\./, "");
  // Structured entries (monitors) have no form here; the site file takes them.
  if (o.type.includes("submodule")) return null;
  if (o.type === "boolean") return <div style={{ display: "flex", flexDirection: "column", gap: 4 }}><Toggle on={Boolean(value)} onChange={onChange} label={<span style={{ fontWeight: 500 }}>{name}</span>} />{desc}</div>;
  if (o.values.length) return <Field label={name}><div className="tray" style={{ alignSelf: "flex-start" }}>{o.values.map((v) => <button key={v} className="seg" aria-pressed={value === v} onClick={() => onChange(v)}>{v}</button>)}</div>{desc}</Field>;
  if (o.type.startsWith("list of")) return <Field label={`${name} (one per line)`}><textarea className="input" rows={3} value={Array.isArray(value) ? value.join("\n") : ""} onChange={(e) => { const l = e.target.value.split("\n").map((s) => s.trim()).filter(Boolean); onChange(o.type.includes("integer") ? l.map(Number).filter(Number.isInteger) : l); }} />{desc}</Field>;
  if (o.type.includes("integer") || o.type.includes("port")) return <Field label={name}><input className="input mono" type="number" value={value == null ? "" : String(value)} onChange={(e) => onChange(e.target.value === "" ? null : Number(e.target.value))} />{desc}</Field>;
  return <Field label={name}><input className="input mono" value={value == null ? "" : String(value)} onChange={(e) => onChange(e.target.value || null)} />{desc}</Field>;
}

function Wizard() {
  const [finish, setFinish] = useState<Finish>("graphite");
  useEffect(() => { applyFinish(finish); }, [finish]);
  const [paired, setPaired] = useState<boolean | null>(null);
  const [code, setCode] = useState("");
  const [err, setErr] = useState("");
  const [st, setSt] = useState<State | null>(null);
  const [opts, setOpts] = useState<Opt[]>([]);
  const [hw, setHw] = useState<Hardware | null>(null);
  // A scan that fails must say so: the step used to sit on "Looking at
  // the hardware…" for ever with the reason thrown away.
  const [hwErr, setHwErr] = useState("");
  const [step, setStep] = useState(0);
  const [values, setValues] = useState<Record<string, unknown>>({});
  const [secrets, setSecrets] = useState<Record<string, string>>({});
  const [host, setHost] = useState("");
  const [disk, setDisk] = useState("");
  const [dataDisk, setDataDisk] = useState("");
  const [uplinks, setUplinks] = useState<string[]>([]);
  const [siteMode, setSiteMode] = useState<"new" | "clone" | "upload">("new");
  const [siteUrl, setSiteUrl] = useState("");
  const [siteHosts, setSiteHosts] = useState<string[]>([]);
  const [plan, setPlan] = useState<{ hardware: string; site: string } | null>(null);
  const [lines, setLines] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [totp, setTotp] = useState<{ uri: string; qr: string; secret: string } | null>(null);
  const [totpCode, setTotpCode] = useState("");
  const [totpOk, setTotpOk] = useState(false);
  const [attest, setAttest] = useState("");
  const [recovery, setRecovery] = useState<{ key: string; qr: string }>({ key: "", qr: "" });
  const logRef = useRef<HTMLPreElement>(null);

  const refresh = () => api.state().then(setSt).catch(() => undefined);
  useEffect(() => {
    api.state().then((s) => { setPaired(true); setSt(s); }).catch(() => setPaired(false));
  }, []);
  useEffect(() => {
    if (!paired) return;
    api.options().then((o) => {
      setOpts(o);
      const init: Record<string, unknown> = {};
      // Lists too, so a field shows its default ([7] reads "7") instead of
      // looking empty; submitConfig leaves an unedited one out by identity.
      for (const x of o) if (x.section && !x.required && x.default !== null && (typeof x.default !== "object" || Array.isArray(x.default))) init[x.path] = x.default;
      init["nixie.security.encryption.enable"] = true;
      setValues((v) => ({ ...init, ...v }));
    });
    // The endpoint answers 200 with {error} when the scan itself failed;
    // taking that as hardware crashes the step on hw.disks.map.
    api.hardware()
      .then((h) => ((h as unknown as { error?: string }).error ? setHwErr((h as unknown as { error: string }).error) : setHw(h)))
      .catch((e) => setHwErr((e as Error).message));
  }, [paired]);
  useEffect(() => { logRef.current?.scrollTo(0, logRef.current.scrollHeight); }, [lines]);

  const profile = (values["nixie.profile"] as string) ?? "server";
  const bySection = useMemo(() => {
    const m: Record<string, Opt[]> = {};
    for (const o of opts) if (o.section) (m[o.section] ??= []).push(o);
    for (const k in m) m[k].sort((a, b) => a.order - b.order);
    return m;
  }, [opts]);
  const enabledSteps = SECTIONS.filter((s) => s.id !== "desktop" || profile === "desktop");
  const set = (k: string, v: unknown) => setValues((x) => ({ ...x, [k]: v }));
  const secretsNeeded = useMemo(() => {
    const need = new Set<string>(["password"]);
    for (const o of opts) if (o.secret && o.secret !== "password" && values[o.path] === true) need.add(o.secret);
    if (values["nixie.network.tailscale.enable"] && values["nixie.network.tailscale.authKeyFile"]) need.add("tailscale");
    return [...need];
  }, [opts, values]);

  const run = async (n: number, body: Record<string, unknown> = {}) => {
    setBusy(true);
    setErr("");
    setLines((l) => [...l, `▶ phase ${n}`]);
    // A failing phase says why in its last lines; before the Install step
    // the log is not on screen, so they become the step's error.
    const out: string[] = [];
    try {
      const r = await api.phase(n, body, (line) => { out.push(line); setLines((l) => [...l, line]); });
      setLines((l) => [...l, r.rc === 0 ? `✓ phase ${n} done` : `phase ${n} exited ${r.rc}`]);
      if (r.rc !== 0 && r.rc !== 10) setErr(out.slice(-3).join("\n") || `phase ${n} exited ${r.rc}`);
      await refresh();
      return r.rc;
    } catch (e) {
      setLines((l) => [...l, `error: ${(e as Error).message}`]);
      return 1;
    } finally {
      setBusy(false);
    }
  };

  const submitConfig = async () => {
    const settings: Record<string, unknown> = {};
    for (const o of opts) {
      if (!o.section || o.path === "nixie.profile" || o.path === "nixie.host.name") continue;
      if (o.section === "hardware") continue;
      if (o.section === "desktop" && profile !== "desktop") continue;
      if (profile === "desktop" && SERVER_ONLY.test(o.path)) continue;
      const v = values[o.path];
      if (v === undefined || v === null || v === o.default || (Array.isArray(v) && v.length === 0 && Array.isArray(o.default) && o.default.length === 0)) continue;
      settings[o.path] = v;
    }
    const tsKey = secrets["tailscale"];
    if (tsKey) settings["nixie.network.tailscale.authKeyFile"] = "/var/lib/nixie/tailscale.key";
    await api.secrets({ passphrase: secrets.passphrase ?? "", pin: secrets.pin ?? "", duress: secrets.duress ?? "", "admin-password": secrets.password ?? "", "tailscale.key": tsKey ?? "" });
    await api.config({ host, profile, systemDisk: disk, dataDisk: dataDisk || null, uplinks: profile === "server" ? uplinks : [], gpu: hw?.gpu ?? "none", tpm: hw?.tpm ?? false, settings, existingSite: siteMode !== "new" && siteHosts.includes(host) });
    if ((await run(1)) !== 0) return false;
    setPlan(await api.plan());
    return true;
  };

  if (paired === null) return <div className="empty">…</div>;
  if (!paired) {
    return (
      <div style={{ maxWidth: 480, margin: "80px auto" }}>
        <Panel title="Pair this browser" sub="the code is on the machine's screen">
          <p className="caption">Compare the certificate fingerprint your browser shows with the one printed next to the code, then enter the code. It works once.</p>
          <div style={{ display: "flex", gap: 8 }}>
            <input className="input mono" autoFocus placeholder="123456" value={code} onChange={(e) => setCode(e.target.value)} onKeyDown={(e) => e.key === "Enter" && api.pair(code).then(() => location.reload()).catch((x) => setErr(x.message))} />
            <button className="btn primary" onClick={() => api.pair(code).then(() => location.reload()).catch((x) => setErr(x.message))}>Pair</button>
          </div>
          {err && <p style={{ color: "var(--err)" }}>{err}</p>}
        </Panel>
      </div>
    );
  }
  const cont = st?.mode === "continuation";
  const done = st?.done ?? [];
  const features = (st?.layout?.features ?? {}) as Record<string, boolean>;

  const header = (
    <header className="header" style={{ gridTemplateColumns: "200px 1fr auto" }}>
      <div className="brand"><Mark /><span className="wordmark">nixie</span><span className="chip" style={{ fontSize: 10 }}>setup</span></div>
      <div style={{ display: "flex", alignItems: "center", padding: "0 20px", gap: 20 }} className="muted">
        {cont ? CONT.map((c) => <span key={c.n} style={{ color: done.includes(c.n) ? "var(--ok)" : "inherit" }}>{done.includes(c.n) ? "✓ " : ""}{c.title}</span>) : enabledSteps.map((s, i) => <span key={s.id} style={{ color: i === step ? "var(--ink)" : i < step ? "var(--ok)" : "inherit", borderBottom: i === step ? "2px solid var(--brand2)" : "none" }}>{s.title}</span>)}
      </div>
      <div className="header-right"><div className="tray">{finishes.map((f) => <button key={f} className="swatch" aria-pressed={finish === f} aria-label={f} onClick={() => setFinish(f)} style={{ background: f === "graphite" ? "#1f2226" : f === "umber" ? "#231b16" : "#e4e1da" }} />)}</div></div>
    </header>
  );
  const log = <pre ref={logRef} className="well term" style={{ maxHeight: 320, overflow: "auto", whiteSpace: "pre-wrap", fontSize: 12 }}>{lines.join("\n") || "output appears here"}</pre>;

  if (cont) {
    const next = CONT.find((c) => !done.includes(c.n));
    // Success ends this page with the service; a failure leaves it up, so it
    // has to say why here rather than only in the journal.
    const finishSetup = () => {
      setBusy(true);
      setErr("");
      api.finish().then((r) => {
        setLines((l) => [...l, r.output]);
        if (!r.ok) return setBusy(false);
        const t = setInterval(() => api.finishStatus().then((s) => {
          if (!s.failed) return;
          clearInterval(t);
          setLines((l) => [...l, ...s.lines]);
          setErr("Finish stopped; the lines above say why. Fix the site and press Finish again.");
          setBusy(false);
        }).catch(() => undefined), 3000);
      }).catch((e) => { setErr((e as Error).message); setBusy(false); });
    };
    return (
      <div className="app" style={{ gridTemplateRows: "64px 1fr" }}>
        {header}
        <main className="page" style={{ maxWidth: 900, width: "100%", margin: "0 auto" }}>
          {!next ? (
            <Panel title="Finished" sub="the machine is yours">
              <p>Every phase is done. Finish switches to the normal system, removes the setup generation and this page; from then on the control panel is the only web page on this host.</p>
              <button className="btn primary" disabled={busy} onClick={finishSetup}>Finish</button>
              {log}
              {err && <p style={{ color: "var(--err)", whiteSpace: "pre-wrap" }}>{err}</p>}
            </Panel>
          ) : (
            <Panel title={`${next.n}. ${next.title}`} sub={next.blurb}>
              {((next.n === 5 && !features.secureBoot) || (next.n === 6 && !features.encryption)) && (
                <p className="caption">{next.n === 5 ? "Secure Boot is not enabled on this host" : "The disk is not encrypted"}, so this step only records that it is done.</p>
              )}
              {next.n === 5 && features.secureBoot && (
                <div className="caption" style={{ whiteSpace: "pre-line" }}>
                  {`Setup Mode checklist, in the firmware setup (usually F2 or Del at power-on):
1. Secure Boot: enabled.
2. Delete or clear all Secure Boot keys, which puts the firmware in Setup Mode.
3. Save and reboot; systemd-boot enrols the keys on that boot.
Run this step: it tells you which of these is still missing, and asks for a reboot when the keys are staged.`}
                </div>
              )}
              {next.n === 6 && features.encryption && (
                <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
                  {features.encryption && <Field label={SECRET_LABEL.passphrase}><input className="input" type="password" value={secrets.passphrase ?? ""} onChange={(e) => setSecrets({ ...secrets, passphrase: e.target.value })} /></Field>}
                  {features.tpm && <Field label={SECRET_LABEL.pin}><input className="input" type="password" value={secrets.pin ?? ""} onChange={(e) => setSecrets({ ...secrets, pin: e.target.value })} /></Field>}
                  <Field label="Also copy the header backup to this path (a USB stick), optional"><input className="input mono" value={(values.backupDest as string) ?? ""} onChange={(e) => set("backupDest", e.target.value)} /></Field>
                </div>
              )}
              {recovery.key && <div><div className="caption">The recovery key opens the disk when the TPM cannot. Write it down or scan it now; it is shown once and never stored on this machine.</div><pre className="well term" style={{ fontSize: 10, lineHeight: 1 }}>{recovery.qr}</pre><pre className="well mono">{recovery.key}</pre></div>}
              {attest && <div><div className="caption">Scan this with your authenticator app now; it is shown once.</div><pre className="well term" style={{ fontSize: 10, lineHeight: 1 }}>{attest}</pre></div>}
              <div style={{ display: "flex", gap: 8, marginTop: 10 }}>
                <button className="btn primary" disabled={busy} onClick={async () => {
                  if (next.n === 6) await api.secrets({ passphrase: secrets.passphrase ?? "", pin: secrets.pin ?? "" });
                  const rc = await run(next.n, next.n === 6 ? { backupDest: values.backupDest } : {});
                  if (next.n === 6 && rc === 0) api.attestation().then((a) => { setAttest(a.text); setRecovery({ key: a.recovery, qr: a.recoveryQr }); });
                  if ((next.n === 5 && rc === 10) || (next.n === 6 && rc === 0 && (features.tpm || features.attestation))) setLines((l) => [...l, "Reboot to continue."]);
                }}>Run</button>
                <button className="btn" onClick={() => api.reboot()}>Reboot</button>
                {done.includes(6) && <a className="btn" href="/api/download/header-backup" download>Download header backup</a>}
              </div>
              {log}
            </Panel>
          )}
        </main>
      </div>
    );
  }

  const s = enabledSteps[step];
  // Combinations the modules refuse, caught here instead of failing phase 3.
  const problems = (): string[] => {
    const on = (p: string) => Boolean(values[p]);
    const out: string[] = [];
    if (s.id === "security" && !on("nixie.security.encryption.enable")) {
      const needs = ["tpm", "attestation", "duress", "remoteUnlock"].filter((f) => on(`nixie.security.${f}.enable`));
      if (needs.length) out.push(`Needs disk encryption: ${needs.join(", ")}. Turn encryption on, or these off.`);
    }
    if (s.id === "network" && values["nixie.network.egress"] === "exit-node") {
      if (values["nixie.network.bridge.mode"] !== "managed-nat") out.push("Exit-node egress needs the managed-nat bridge mode.");
      if (!on("nixie.network.tailscale.enable")) out.push("Exit-node egress needs Tailscale.");
      if (!values["nixie.network.exitNode"]) out.push("Exit-node egress needs the exit node's name.");
    }
    return out;
  };
  const body = () => {
    switch (s.id) {
      case "profile":
        return (
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
            {["server", "desktop"].map((p) => (
              <button key={p} className="panel" aria-pressed={profile === p} style={{ textAlign: "left", cursor: "pointer", borderColor: profile === p ? "var(--brand2)" : "var(--line)" }} onClick={() => set("nixie.profile", p)}>
                <div className="title">{p === "server" ? "Server" : "Desktop"}</div>
                <p className="caption">{p === "server" ? "A hardened host that runs services as isolated Incus guests declared in Nix, with a web control panel. No desktop software at all." : "A complete Hyprland workstation with the same boot security, declared in the site. No Incus, monitoring or backups unless enabled."}</p>
              </button>
            ))}
          </div>
        );
      case "hardware":
        if (hwErr) return <div className="empty" style={{ color: "var(--err)" }}>The hardware scan failed: {hwErr}</div>;
        return !hw ? <div className="empty">Looking at the hardware…</div> : (
          <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
            <div><div style={{ fontWeight: 500 }}>System disk (wiped)</div>{hw.disks.map((d) => <label key={d.path} className="lane" style={{ height: 28, gridTemplateColumns: "20px 1fr 100px 200px", cursor: "pointer" }}><input type="radio" name="disk" checked={disk === (d.id ?? d.path)} onChange={() => setDisk(d.id ?? d.path)} /><span className="mono">{d.id ?? d.path}</span><Bytes b={d.size} /><span className="muted">{d.model ?? ""}</span></label>)}</div>
            <div><div style={{ fontWeight: 500 }}>Data disk (optional, its own pool)</div><label className="lane" style={{ height: 28, gridTemplateColumns: "20px 1fr", cursor: "pointer" }}><input type="radio" name="data" checked={dataDisk === ""} onChange={() => setDataDisk("")} /><span>none: data lives on the system disk</span></label>{hw.disks.filter((d) => (d.id ?? d.path) !== disk).map((d) => <label key={d.path} className="lane" style={{ height: 28, gridTemplateColumns: "20px 1fr 100px 200px", cursor: "pointer" }}><input type="radio" name="data" checked={dataDisk === (d.id ?? d.path)} onChange={() => setDataDisk(d.id ?? d.path)} /><span className="mono">{d.id ?? d.path}</span><Bytes b={d.size} /><span className="muted">{d.model ?? ""}</span></label>)}</div>
            {profile === "server" && <div><div style={{ fontWeight: 500 }}>Network ports joining the bridge</div>{hw.nics.map((n) => <label key={n.mac} className="lane" style={{ height: 28, gridTemplateColumns: "20px 1fr 100px", cursor: "pointer" }}><input type="checkbox" checked={uplinks.includes(n.mac)} onChange={(e) => setUplinks(e.target.checked ? [...uplinks, n.mac] : uplinks.filter((m) => m !== n.mac))} /><span className="mono">{n.mac}</span><span className={`chip ${n.up ? "ok" : ""}`}>{n.up ? "link up" : "no link"}</span></label>)}</div>}
            <div className="caption">Found: GPU {hw.gpu}, TPM {hw.tpm ? "2.0 present" : "not found"}, firmware {hw.efi ? "UEFI" : "legacy (unsupported)"}.</div>
            {!hw.efi && <p style={{ color: "var(--err)" }}>This machine started the installer in legacy BIOS mode, and Nixie installs a UEFI system. Turn on UEFI boot in the firmware (in VirtualBox: Settings, System, Enable EFI) and start the installer again.</p>}
          </div>
        );
      case "site":
        return (
          <div style={{ display: "flex", flexDirection: "column", gap: 10, maxWidth: 640 }}>
            <div className="tray" style={{ alignSelf: "flex-start" }}>{(["new", "clone", "upload"] as const).map((m) => <button key={m} className="seg" aria-pressed={siteMode === m} onClick={() => setSiteMode(m)}>{m === "new" ? "Start a new site here" : m === "clone" ? "Clone a git URL" : "Upload a tarball"}</button>)}</div>
            {siteMode === "clone" && <div style={{ display: "flex", gap: 8 }}><input className="input mono" style={{ flex: 1 }} placeholder="https://… or ssh://…" value={siteUrl} onChange={(e) => setSiteUrl(e.target.value)} /><button className="btn" onClick={() => api.site({ mode: "clone", url: siteUrl }).then((r) => setSiteHosts(r.hosts)).catch((e) => setErr(e.message))}>Clone</button></div>}
            {siteMode === "upload" && <input className="input" type="file" accept=".tar,.tar.gz,.tgz" onChange={(e) => { const f = e.target.files?.[0]; if (!f) return; f.arrayBuffer().then((b) => api.site({ mode: "upload", tarball: btoa(String.fromCharCode(...new Uint8Array(b))) })).then((r) => setSiteHosts(r.hosts)).catch((x) => setErr(x.message)); }} />}
            {siteHosts.length > 0 && <div className="caption">Hosts in this site: {siteHosts.join(", ")}. Use one of these names below to install it, or a new name to add a host.</div>}
            <Field label="This host's name"><input className="input mono" value={host} onChange={(e) => setHost(e.target.value.toLowerCase())} placeholder="lowercase, digits, dashes" /></Field>
            {err && <p style={{ color: "var(--err)" }}>{err}</p>}
          </div>
        );
      case "security":
      case "network":
      case "desktop":
        return (
          <div style={{ display: "flex", flexDirection: "column", gap: 16, maxWidth: 720 }}>
            {(bySection[s.id] ?? []).filter((o) => o.path !== "nixie.host.name" && !(profile === "desktop" && SERVER_ONLY.test(o.path)) && !(hw && !hw.tpm && TPM_ONLY.test(o.path)) && !WIZARD_WRITES.includes(o.path)).map((o) => <OptionField key={o.path} o={o} value={values[o.path]} onChange={(v) => set(o.path, v)} />)}
            {problems().map((m) => <p key={m} className="caption" style={{ color: "var(--err)" }}>{m}</p>)}
            {s.id === "security" && secretsNeeded.filter((k) => k !== "password" && k !== "tailscale").map((k) => <Field key={k} label={SECRET_LABEL[k] ?? k}><input className="input" type="password" value={secrets[k] ?? ""} onChange={(e) => setSecrets({ ...secrets, [k]: e.target.value })} /></Field>)}
            {s.id === "network" && Boolean(values["nixie.network.tailscale.enable"]) && <Field label="Tailscale auth key (optional; without it you log in from the control panel later)"><input className="input mono" type="password" value={secrets.tailscale ?? ""} onChange={(e) => setSecrets({ ...secrets, tailscale: e.target.value })} /></Field>}
          </div>
        );
      case "auth":
        return (
          <div style={{ display: "flex", flexDirection: "column", gap: 16, maxWidth: 720 }}>
            {(bySection.auth ?? []).filter((o) => !o.path.includes("passwordFile") && !o.path.includes("totpSecretFile")).map((o) => <OptionField key={o.path} o={o} value={values[o.path]} onChange={(v) => set(o.path, v)} />)}
            {Boolean(values["nixie.security.remoteUnlock.enable"]) && !(Array.isArray(values["nixie.auth.sshKeys"]) && (values["nixie.auth.sshKeys"] as string[]).length > 0) && <p className="caption" style={{ color: "var(--err)" }}>Remote unlock is on: add at least one SSH public key, the one you will unlock with.</p>}
            <Field label={SECRET_LABEL.password}><input className="input" type="password" value={secrets.password ?? ""} onChange={(e) => setSecrets({ ...secrets, password: e.target.value })} /></Field>
            {values["nixie.auth.secondFactor"] === "totp" && (
              <div className="panel" style={{ maxWidth: 520 }}>
                <div style={{ fontWeight: 500 }}>Enrol the authenticator app</div>
                {!totp ? <button className="btn" style={{ alignSelf: "flex-start", marginTop: 8 }} onClick={() => api.totpNew().then(setTotp)}>Show QR code</button> : (
                  <div>
                    <pre className="well term" style={{ fontSize: 10, lineHeight: 1 }}>{totp.qr}</pre>
                    <div className="caption mono">{totp.secret}</div>
                    <div style={{ display: "flex", gap: 8, marginTop: 8 }}><input className="input mono" placeholder="code from the app" value={totpCode} onChange={(e) => setTotpCode(e.target.value)} /><button className="btn primary" onClick={() => api.totpVerify(totpCode).then(() => setTotpOk(true)).catch(() => setErr("wrong code"))}>Verify</button>{totpOk && <span className="chip ok">enrolled</span>}</div>
                  </div>
                )}
              </div>
            )}
            {err && <p style={{ color: "var(--err)" }}>{err}</p>}
          </div>
        );
      case "review":
        return !plan ? <div className="empty">Writing the plan…</div> : (
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
            <Panel title={`hosts/${host}/hardware.nix`} sub="generated"><pre className="well term" style={{ fontSize: 12, whiteSpace: "pre-wrap" }}>{plan.hardware}</pre></Panel>
            <Panel title="site.nix" sub="your settings"><pre className="well term" style={{ fontSize: 12, whiteSpace: "pre-wrap" }}>{plan.site}</pre></Panel>
          </div>
        );
      case "install":
        return (
          <div>
            <p className="caption">Phase 2 writes the host identity and secrets; phase 3 partitions {disk}, installs, and copies the site. After it, reboot: the setup generation continues on the same screen and URL.</p>
            {log}
            <div style={{ display: "flex", gap: 8, marginTop: 10 }}>
              <button className="btn primary" disabled={busy || done.includes(3)} onClick={async () => { if ((await run(2)) === 0) await run(3); }}>Install</button>
              <button className="btn" disabled={!done.includes(3)} onClick={() => api.reboot()}>Reboot into the new system</button>
            </div>
          </div>
        );
    }
  };
  const canNext = () => {
    // A desktop has no guest bridge, so no ports to choose.
    if (s.id === "hardware") return Boolean(disk) && (uplinks.length > 0 || profile === "desktop") && Boolean(hw?.efi);
    if (s.id === "site") return /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/.test(host);
    if (problems().length) return false;
    if (s.id === "security") return secretsNeeded.filter((k) => k !== "password" && k !== "tailscale").every((k) => secrets[k]);
    // Remote unlock is an SSH login, so it needs a key to log in with.
    const keys = values["nixie.auth.sshKeys"];
    if (s.id === "auth") return Boolean(secrets.password) && Boolean(values["nixie.auth.admin.name"]) && (values["nixie.auth.secondFactor"] !== "totp" || totpOk) && (!values["nixie.security.remoteUnlock.enable"] || (Array.isArray(keys) && keys.length > 0));
    return true;
  };
  return (
    <div className="app" style={{ gridTemplateRows: "64px 1fr" }}>
      {header}
      <main className="page" style={{ maxWidth: 1000, width: "100%", margin: "0 auto" }}>
        <h1 className="display" style={{ margin: "8px 0 4px" }}>{s.title}</h1>
        <p className="caption" style={{ marginTop: 0 }}>{s.blurb}</p>
        {body()}
        <div style={{ display: "flex", justifyContent: "space-between", marginTop: 20 }}>
          <button className="btn" disabled={step === 0 || busy} onClick={() => setStep(step - 1)}>Back</button>
          {s.id !== "install" && <button className="btn primary" disabled={!canNext() || busy} onClick={async () => { if (enabledSteps[step + 1].id === "review") { setBusy(true); try { if (!(await submitConfig())) { setBusy(false); return; } } catch (e) { setErr((e as Error).message); setBusy(false); return; } setBusy(false); } setStep(step + 1); }}>Next</button>}
        </div>
        {err && s.id !== "site" && s.id !== "auth" && <p style={{ color: "var(--err)", whiteSpace: "pre-line" }}>{err}</p>}
      </main>
    </div>
  );
}

createRoot(document.getElementById("root")!).render(<Wizard />);
