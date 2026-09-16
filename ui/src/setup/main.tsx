// The installer wizard: every step is an option section or a phase, rendered
// from the option metadata the backend serves. It never does anything the
// CLI cannot; it only calls the phase scripts.
import { lazy, Suspense, useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import { applyFinish } from "../tokens";
import { Mark, Field } from "../components/ui";
import { api, type Opt, type Hardware, type State, type SiteFile, type Check } from "./api";
import { OptionGroup } from "./fields";
import { Checklist, Continuation, Log, type Item, type Step } from "./Checklist";
import "../tokens/base.css";
import "./setup.css";

// CodeMirror is most of the bundle and only the review step needs it.
const Editor = lazy(() => import("./Editor").then((m) => ({ default: m.Editor })));

const STEPS: { id: string; title: string; blurb: string }[] = [
  { id: "profile", title: "Machine", blurb: "What this machine is for." },
  { id: "hardware", title: "Disks", blurb: "Where to install, and what else was found." },
  { id: "site", title: "Name", blurb: "This machine's name, and where its configuration lives." },
  { id: "security", title: "Security", blurb: "Disk encryption and the administrator. Everything but encryption can change after install." },
  { id: "network", title: "Network", blurb: "Time zone, Tailscale and the guest network." },
  { id: "services", title: "Services", blurb: "Backups, monitoring and the host page. Each is off until you turn it on." },
  { id: "desktop", title: "Desktop", blurb: "The look, the keyboard and the apps." },
  { id: "review", title: "Review", blurb: "What you chose and the files it wrote. Change anything before installing." },
  { id: "install", title: "Install", blurb: "Erase the disk, install, and restart into setup." },
];
// Which option sections each step shows; the other steps are drawn by hand.
const STEP_SECTIONS: Record<string, string[]> = { site: ["site"], security: ["security", "auth"], network: ["network"], services: ["services"], desktop: ["desktop"] };
// A desktop has no guest bridge, Incus or front panel; NetworkManager configures it.
const SERVER_ONLY = /^nixie\.(incus\.|console\.|network\.(address|gateway|dns|bridge\.|egress|exitNode))/;
// Without a TPM these cannot work, so the step does not offer them.
const TPM_ONLY = /^nixie\.security\.(tpm|attestation)\./;
// Set by the wizard itself, or asked for as a secret instead of a path.
const NOT_FIELDS = ["nixie.network.tailscale.authKeyFile", "nixie.host.name", "nixie.auth.admin.passwordFile", "nixie.auth.totpSecretFile"];
const SECRET_LABEL: Record<string, string> = { passphrase: "Disk passphrase, asked at every start", pin: "TPM PIN", duress: "Duress passphrase: typed at start, it destroys the disk", tailscale: "Tailscale auth key", password: "Administrator password" };
const HOST_NAME = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/;
// The hardened setup: every security feature the installer can turn on without
// asking the person to decide, walked through instead of hidden. Kernel
// lockdown is left out on purpose (it rebuilds the kernel from source and
// stops unsigned drivers loading), and so is unlocking over SSH, which adds a
// way in rather than closing one.
const HARDENED: Record<string, unknown> = {
  "nixie.security.encryption.enable": true,
  "nixie.security.tpm.enable": true,
  "nixie.security.attestation.enable": true,
  "nixie.security.secureBoot.enable": true,
  "nixie.security.duress.enable": true,
  "nixie.security.hardening.ssh.enable": true,
  "nixie.security.hardening.usbguard.enable": true,
  "nixie.security.hardening.memoryEncryption.enable": true,
  "nixie.auth.secondFactor": "totp",
  "nixie.auth.ssh.passwordLogin": false,
};
const HYDE = "nixie.desktop.hyde.enable";
// HyDE brings its own look and keyboard settings; these apply to the Nixie desktop only.
const NIXIE_DESKTOP_ONLY = /^nixie\.desktop\.(finish|wallpaper|keyboard\.|monitors)/;

const gb = (b: number) => `${(b / 1e9).toFixed(0)} GB`;
const show = (v: unknown): string => (v === true ? "On" : v === false ? "Off" : v == null || v === "" ? "—" : Array.isArray(v) ? (v.length ? v.join(", ") : "—") : String(v));

// A value as Nix, for the option list's Add (strings escape `${`).
const nix = (v: unknown): string =>
  v === null || v === undefined ? "null" : typeof v === "string" ? JSON.stringify(v).replace(/\$\{/g, "\\${") : Array.isArray(v) ? `[ ${v.map(nix).join(" ")} ]` : typeof v === "object" ? `{ ${Object.entries(v).map(([k, x]) => `${JSON.stringify(k)} = ${nix(x)};`).join(" ")} }` : String(v);

function Wizard() {
  // Setup keeps one look; the machine's own finish is a choice in its configuration.
  useEffect(() => { applyFinish("graphite"); }, []);
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
  const [dir, setDir] = useState<"fwd" | "back">("fwd");
  const [values, setValues] = useState<Record<string, unknown>>({});
  const [secrets, setSecrets] = useState<Record<string, string>>({});
  const [host, setHost] = useState("");
  const [disk, setDisk] = useState("");
  const [dataDisk, setDataDisk] = useState("");
  const [uplinks, setUplinks] = useState<string[]>([]);
  const [hardened, setHardened] = useState(false);
  const [siteMode, setSiteMode] = useState<"new" | "clone" | "upload">("new");
  const [siteUrl, setSiteUrl] = useState("");
  const [siteHosts, setSiteHosts] = useState<string[]>([]);
  const [lines, setLines] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [running, setRunning] = useState<number | null>(null);
  const [failed, setFailed] = useState<number | null>(null);
  // What the running phase says it is doing, for the bar: "[nixie 3] step 2/7 …".
  const [phaseStep, setPhaseStep] = useState<Step | null>(null);
  const [totp, setTotp] = useState<{ uri: string; qr: string; secret: string } | null>(null);
  const [totpCode, setTotpCode] = useState("");
  const [totpOk, setTotpOk] = useState(false);
  // The review step: the site's files as written, the edits on top, and
  // whether the last evaluation passed with no edit since.
  const [tab, setTab] = useState<"summary" | "files" | "options">("summary");
  const [files, setFiles] = useState<SiteFile[]>([]);
  const [drafts, setDrafts] = useState<Record<string, string>>({});
  const [openFile, setOpenFile] = useState("site.nix");
  const [check, setCheck] = useState<Check | null>(null);
  const [checking, setChecking] = useState(false);
  const [edits, setEdits] = useState(0);
  const [checkedEdits, setCheckedEdits] = useState(-1);
  const [query, setQuery] = useState("");

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

  const profile = (values["nixie.profile"] as string) ?? "server";
  const steps = STEPS.filter((s) => s.id !== "desktop" || profile === "desktop");
  const set = (k: string, v: unknown) => setValues((x) => ({ ...x, [k]: v }));
  const offered = (o: Opt) => !NOT_FIELDS.includes(o.path) && !(profile === "desktop" && SERVER_ONLY.test(o.path)) && !(hw && !hw.tpm && TPM_ONLY.test(o.path));
  // A hardened setup turns these on and keeps them on; without a TPM the two
  // that need one are not offered at all, so they cannot be locked either.
  const lockedByHardening = (o: Opt) => hardened && o.path in HARDENED && offered(o);
  const setHardening = (on: boolean) => {
    setHardened(on);
    if (on) setValues((v) => ({ ...v, ...HARDENED }));
  };
  const stepOpts = useMemo(() => {
    const m: Record<string, Opt[]> = {};
    for (const [id, sections] of Object.entries(STEP_SECTIONS))
      m[id] = sections.flatMap((sec) => opts.filter((o) => o.section === sec && offered(o)).sort((a, b) => a.order - b.order));
    return m;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opts, profile, hw]);
  const secretsNeeded = useMemo(() => {
    const need = new Set<string>(["password"]);
    for (const o of opts) if (o.secret && o.secret !== "password" && values[o.path] === true && offered(o)) need.add(o.secret);
    return [...need];
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opts, values, profile, hw]);

  const run = async (n: number, body: Record<string, unknown> = {}) => {
    setBusy(true);
    setErr("");
    setRunning(n);
    setFailed(null);
    setPhaseStep(null);
    setLines((l) => [...l, `▶ phase ${n}`]);
    // A failing phase says why in its last lines; they become the step's error.
    const out: string[] = [];
    try {
      const r = await api.phase(n, body, (line) => {
        out.push(line);
        setLines((l) => [...l, line]);
        const m = /^\[nixie (\d+)\] step (\d+)\/(\d+) (.*)$/.exec(line);
        if (m) setPhaseStep({ phase: Number(m[1]), done: Number(m[2]), total: Number(m[3]), text: m[4] });
      });
      setLines((l) => [...l, r.rc === 0 ? `✓ phase ${n} done` : `phase ${n} exited ${r.rc}`]);
      if (r.rc !== 0 && r.rc !== 10 && r.rc !== 11) { setErr(out.slice(-3).join("\n") || `phase ${n} exited ${r.rc}`); setFailed(n); }
      await refresh();
      return r.rc;
    } catch (e) {
      setLines((l) => [...l, `error: ${(e as Error).message}`]);
      setErr((e as Error).message);
      setFailed(n);
      return 1;
    } finally {
      setRunning(null);
      setBusy(false);
    }
  };

  const evaluate = async (at: number) => {
    setChecking(true);
    try {
      setCheck(await api.check());
      setCheckedEdits(at);
    } catch (e) {
      setErr((e as Error).message);
    } finally {
      setChecking(false);
    }
  };
  // Saves what changed, then evaluates the host as phase 3 will.
  const saveAndCheck = async () => {
    setErr("");
    const at = edits;
    try {
      for (const f of files) if (drafts[f.path] !== f.content) await api.saveFile(f.path, drafts[f.path]);
    } catch (e) {
      return setErr((e as Error).message);
    }
    setFiles((fs) => fs.map((f) => ({ ...f, content: drafts[f.path] ?? f.content })));
    await evaluate(at);
  };

  const submitConfig = async () => {
    const settings: Record<string, unknown> = {};
    for (const o of opts) {
      if (!o.section || o.section === "hardware" || o.path === "nixie.profile" || !offered(o)) continue;
      if (o.section === "desktop" && profile !== "desktop") continue;
      const v = values[o.path];
      if (v === undefined || v === null || v === o.default || (Array.isArray(v) && v.length === 0 && Array.isArray(o.default) && o.default.length === 0)) continue;
      settings[o.path] = v;
    }
    const tsKey = values["nixie.network.tailscale.enable"] ? secrets.tailscale : "";
    if (tsKey) settings["nixie.network.tailscale.authKeyFile"] = "/var/lib/nixie/tailscale.key";
    await api.secrets({ passphrase: secrets.passphrase ?? "", pin: secrets.pin ?? "", duress: secrets.duress ?? "", "admin-password": secrets.password ?? "", "tailscale.key": tsKey ?? "", "age.key": siteMode === "new" ? "" : (secrets["age.key"] ?? "") });
    await api.config({ host, profile, systemDisk: disk, dataDisk: dataDisk || null, uplinks: profile === "server" ? uplinks : [], gpu: hw?.gpu ?? "none", tpm: hw?.tpm ?? false, settings, existingSite: siteMode !== "new" && siteHosts.includes(host) });
    if ((await run(1)) !== 0) return false;
    const f = (await api.files()).files;
    setFiles(f);
    setDrafts(Object.fromEntries(f.map((x) => [x.path, x.content])));
    setOpenFile((p) => (f.some((x) => x.path === p) ? p : f[0]?.path ?? ""));
    setCheck(null);
    setEdits(0);
    setCheckedEdits(-1);
    setTab("summary");
    return true;
  };

  if (paired === null) return <div className="boot"><Mark size={44} /></div>;
  if (!paired) {
    const pair = () => api.pair(code).then(() => location.reload()).catch((x) => setErr(x.message));
    return (
      <div className="pair">
        <div className="panel pair-card">
          <div className="brand-row"><Mark size={30} /><span className="wordmark">nixie</span><span className="chip">setup</span></div>
          <h1 className="title">Pair this browser</h1>
          <p className="caption">Check that the certificate fingerprint your browser shows matches the one on the machine's screen, then type the code shown next to it. It works once.</p>
          <div className="row">
            <input className="input mono code" autoFocus inputMode="numeric" placeholder="123456" value={code} onChange={(e) => setCode(e.target.value)} onKeyDown={(e) => e.key === "Enter" && pair()} />
            <button className="btn primary" onClick={pair}>Pair</button>
          </div>
          {err && <p className="notice err">{err}</p>}
        </div>
      </div>
    );
  }
  const done = st?.done ?? [];

  if (st?.mode === "continuation") {
    const count = done.filter((n) => n >= 4).length;
    return (
      <div className="wizard">
        <header className="wizard-head">
          <div className="brand-row"><Mark /><span className="wordmark">nixie</span><span className="chip">setup</span><span className="muted host">{String(st.state.host ?? "")} · {String(st.state.profile ?? "")}</span></div>
          <div className="progress"><i style={{ transform: `scaleX(${count / 5})` }} /></div>
        </header>
        <main className="wizard-main">
          <div className="wizard-body">
            <Continuation st={st} run={run} busy={busy} setBusy={setBusy} lines={lines} setLines={setLines} err={err} setErr={setErr} failed={failed} running={running} step={phaseStep} />
          </div>
        </main>
      </div>
    );
  }

  const s = steps[step];
  // Once the disk is erased there is no going back to change it.
  const locked = busy || done.includes(3);
  const go = (i: number) => { setErr(""); setDir(i < step ? "back" : "fwd"); setStep(i); };
  const on = (p: string) => Boolean(values[p]);
  // Combinations the modules refuse, caught here instead of failing phase 3.
  const problems = (): string[] => {
    const out: string[] = [];
    if (s.id === "security") {
      if (!on("nixie.security.encryption.enable")) {
        const needs = ["tpm", "attestation", "duress", "remoteUnlock"].filter((f) => on(`nixie.security.${f}.enable`));
        if (needs.length) out.push(`These need disk encryption: ${needs.join(", ")}. Turn encryption on, or these off.`);
      }
      if (["root", "nobody"].includes(String(values["nixie.auth.admin.name"]))) out.push("The administrator cannot be root or nobody: it is a normal account of its own that uses sudo.");
      // Remote unlock is an SSH login, so it needs a key to log in with.
      const keys = values["nixie.auth.sshKeys"];
      if (on("nixie.security.remoteUnlock.enable") && !(Array.isArray(keys) && keys.length > 0)) out.push("Unlock over SSH is on: add the SSH public key you will unlock with.");
    }
    // Fields restricted to a pattern say so in their type; a value that does
    // not match would only fail when phase 3 evaluates the site.
    for (const o of stepOpts[s.id] ?? []) {
      const pat = /^string matching the pattern (.+)$/.exec(o.type)?.[1];
      const v = values[o.path];
      if (pat && typeof v === "string" && v && !new RegExp(pat).test(v)) out.push(`${o.label ?? o.path} must match ${pat}.`);
    }
    if (s.id === "network" && values["nixie.network.egress"] === "exit-node") {
      if (values["nixie.network.bridge.mode"] !== "managed-nat") out.push("Guests going out through an exit node need the private guest network (managed-nat).");
      if (!on("nixie.network.tailscale.enable")) out.push("Going out through an exit node needs Tailscale.");
      if (!values["nixie.network.exitNode"]) out.push("Name the exit node.");
    }
    return out;
  };
  // A step's options as the step shows them: under HyDE, not the Nixie desktop's own.
  const shownOpts = (id: string) => (stepOpts[id] ?? []).filter((o) => o.path !== HYDE && !(id === "desktop" && on(HYDE) && NIXIE_DESKTOP_ONLY.test(o.path)));
  const secretField = (k: string) => <Field key={k} label={SECRET_LABEL[k] ?? k}><input className="input" type="password" autoComplete="new-password" value={secrets[k] ?? ""} onChange={(e) => setSecrets({ ...secrets, [k]: e.target.value })} /></Field>;
  const dirty = files.some((f) => drafts[f.path] !== f.content);
  const checkOk = Boolean(check?.ok) && checkedEdits === edits && !dirty;

  const diskRow = (d: Hardware["disks"][number], name: string, checked: boolean, pick: () => void) => (
    <label key={d.path} className="choice" data-on={checked}>
      <input type="radio" name={name} checked={checked} onChange={pick} />
      <span className="mono">{d.id ?? d.path}</span>
      <span className="mono muted">{gb(d.size)}</span>
      <span className="muted">{d.model ?? ""}</span>
    </label>
  );

  const summary = () => {
    const shown = (id: string) => shownOpts(id).filter((o) => !o.type.includes("submodule") && (!o.advanced || JSON.stringify(values[o.path]) !== JSON.stringify(o.default)));
    const fixed: Record<string, [string, string][]> = {
      profile: [
        ["What this machine is for", profile === "server" ? "Server" : "Desktop"],
        ["How much security", hardened ? "Hardened" : "Standard"],
      ],
      desktop: [["Desktop", on(HYDE) ? "HyDE" : "Nixie desktop"]],
      hardware: [["Install on", disk], ["Data disk", dataDisk || "—"], ...(profile === "server" ? [["Network ports for guests", uplinks.join(", ") || "—"] as [string, string]] : [])],
      site: [["Host name", host], ["Configuration", siteMode === "new" ? "Start new" : siteMode === "clone" ? siteUrl : "Uploaded"]],
    };
    return (
      <div className="summary">
        {steps.filter((x) => x.id !== "review" && x.id !== "install").map((x) => {
          const rows = [...(fixed[x.id] ?? []), ...(x.id === "site" && siteMode !== "new" ? [] : shown(x.id).map((o): [string, string] => [o.label ?? o.path, show(values[o.path])]))];
          if (x.id === "security") rows.push(...secretsNeeded.filter((k) => k !== "tailscale").map((k): [string, string] => [SECRET_LABEL[k] ?? k, secrets[k] ? "set" : "—"]));
          return (
            <section key={x.id} className="panel summary-card">
              <header><span className="t">{x.title}</span><button className="link" disabled={locked} onClick={() => go(steps.indexOf(x))}>Change</button></header>
              <dl>{rows.map(([k, v]) => <div key={k}><dt>{k}</dt><dd className={v === "Off" || v === "—" ? "muted" : ""}>{v}</dd></div>)}</dl>
            </section>
          );
        })}
      </div>
    );
  };

  const allOptions = () => {
    const q = query.trim().toLowerCase();
    const own = `hosts/${host}/configuration.nix`;
    const found = opts.filter((o) => !q || o.path.toLowerCase().includes(q) || (o.label ?? "").toLowerCase().includes(q) || o.description.toLowerCase().includes(q)).slice(0, 60);
    const add = (o: Opt) => {
      const text = drafts[own] ?? "";
      const at = text.lastIndexOf("}");
      if (at < 0) return;
      setDrafts({ ...drafts, [own]: `${text.slice(0, at)}  ${o.path} = ${o.required ? "null" : nix(o.default)};\n${text.slice(at)}` });
      setEdits((e) => e + 1);
      setOpenFile(own);
      setTab("files");
    };
    return (
      <div className="fields">
        <input className="input" autoFocus placeholder="Search every nixie option: backups, ssh, wallpaper…" value={query} onChange={(e) => setQuery(e.target.value)} />
        <div className="optlist">
          {found.map((o) => (
            <div key={o.path} className="optrow">
              <div className="grow">
                <div><span className="field-label">{o.label ?? o.path.replace(/^nixie\./, "")}</span> <span className="mono muted small">{o.path}</span></div>
                <div className="caption">{o.description.trim().split(/(?<=[.!?])\s/)[0]}</div>
                <div className="mono muted small">{o.type}{o.required ? "" : ` · default ${JSON.stringify(o.default)}`}</div>
              </div>
              <button className="btn" onClick={() => add(o)} disabled={!files.some((f) => f.path === own)}>Add</button>
            </div>
          ))}
        </div>
        <p className="caption">Add puts the option in hosts/{host}/configuration.nix with its default, for you to change under Files.</p>
      </div>
    );
  };

  const review = () => {
    const marks = (check?.locations ?? []).filter((l) => l.path === openFile).map((l) => ({ line: l.line, col: l.col, message: check?.message ?? "" }));
    const tone = checking ? "busy" : check ? (checkOk ? "ok" : check.ok ? "stale" : "err") : "stale";
    return (
      <div className="fields">
        <div className={`status ${tone}`}>
          <span className="status-dot" />
          <div className="grow">
            {checking ? "Checking the configuration…" : !check ? "Not checked yet." : checkOk ? "The configuration evaluates. Ready to install." : check.ok ? "Changed since the last check." : <><b>The configuration does not evaluate.</b><pre className="mono small">{check.message}</pre></>}
            {check && !check.ok && !checking && check.locations.length > 0 && <div className="facts">{check.locations.map((l, i) => <button key={i} className="chip err pick" onClick={() => { setOpenFile(l.path); setTab("files"); }}>{l.path}:{l.line}</button>)}</div>}
          </div>
          <button className="btn primary" disabled={checking || busy} onClick={saveAndCheck}>{dirty ? "Save and check" : "Check again"}</button>
        </div>
        <div className="tray" style={{ alignSelf: "flex-start" }}>
          {(["summary", "files", "options"] as const).map((t) => <button key={t} className="seg" aria-pressed={tab === t} onClick={() => setTab(t)}>{t === "summary" ? "Summary" : t === "files" ? `Files${dirty ? " •" : ""}` : "All options"}</button>)}
        </div>
        {tab === "summary" && summary()}
        {tab === "options" && allOptions()}
        {tab === "files" && (
          <div className="files">
            <nav className="file-list">
              {files.map((f) => {
                const n = (check?.locations ?? []).filter((l) => l.path === f.path).length;
                return <button key={f.path} className="file" aria-pressed={openFile === f.path} onClick={() => setOpenFile(f.path)}><span className="mono">{f.path}</span>{drafts[f.path] !== f.content && <span className="dot-edit" aria-label="edited" />}{n > 0 && <span className="chip err">{n}</span>}</button>;
              })}
            </nav>
            <div className="well editor">
              <Suspense fallback={<div className="skeleton tall" />}>
                {openFile && drafts[openFile] !== undefined && <Editor key={openFile} value={drafts[openFile]} opts={opts} marks={marks} onChange={(v) => { setDrafts((d) => ({ ...d, [openFile]: v })); setEdits((e) => e + 1); }} />}
              </Suspense>
            </div>
          </div>
        )}
        <p className="caption">Going back to change a step writes this machine's entry in site.nix and hardware.nix again. Your own settings belong in hosts/{host}/configuration.nix, which is kept.</p>
      </div>
    );
  };

  const body = () => {
    switch (s.id) {
      case "profile":
        return (
          <div className="fields">
            <div className="cards">
              {["server", "desktop"].map((p) => (
                <button key={p} className="card" aria-pressed={profile === p} onClick={() => set("nixie.profile", p)}>
                  <div className="card-title">{p === "server" ? "Server" : "Desktop"}</div>
                  <p className="caption">{p === "server" ? "Runs services as isolated guests, with a web control panel. No desktop software." : "A complete Hyprland workstation with the same boot security. No guests, monitoring or backups unless you turn them on."}</p>
                </button>
              ))}
            </div>
            <div className="field">
              <div className="field-label">How much security</div>
              <div className="cards">
                <button className="card" aria-pressed={!hardened} onClick={() => setHardening(false)}>
                  <div className="card-title">Standard</div>
                  <p className="caption">The disk is encrypted; everything else is a choice you make on the Security step, and can change later.</p>
                </button>
                <button className="card" aria-pressed={hardened} onClick={() => setHardening(true)}>
                  <div className="card-title">Hardened</div>
                  <p className="caption">{`Every feature on: ${hw?.tpm ? "TPM and PIN, an attestation code, " : ""}Secure Boot with your own keys, a duress passphrase, USB device blocking, memory encryption, key-only SSH and a second factor for the host page. The Security step walks through each one and asks for what it needs.`}</p>
                </button>
              </div>
              {hardened && !hw?.tpm && <p className="notice err">This machine has no TPM, so binding the disk to it and the attestation code are not part of this setup; everything else is.</p>}
            </div>
          </div>
        );
      case "hardware":
        if (hwErr) return <p className="notice err">The hardware scan failed: {hwErr}</p>;
        if (!hw) return <div className="fields"><div className="skeleton" /><div className="skeleton" /><div className="skeleton short" /></div>;
        return (
          <div className="fields">
            {!hw.efi && <p className="notice err">This machine started the installer in legacy BIOS mode, and Nixie installs a UEFI system. Turn on UEFI boot in the firmware (in VirtualBox: Settings, System, Enable EFI) and start the installer again.</p>}
            <div className="field"><div className="field-label">Install on (this disk is erased)</div><div className="choices">{hw.disks.map((d) => diskRow(d, "disk", disk === (d.id ?? d.path), () => setDisk(d.id ?? d.path)))}</div></div>
            {hw.disks.length > 1 && (
              <div className="field">
                <div className="field-label">Data disk (optional)</div>
                <div className="choices">
                  <label className="choice" data-on={dataDisk === ""}><input type="radio" name="data" checked={dataDisk === ""} onChange={() => setDataDisk("")} /><span>None: data lives on the system disk</span></label>
                  {hw.disks.filter((d) => (d.id ?? d.path) !== disk).map((d) => diskRow(d, "data", dataDisk === (d.id ?? d.path), () => setDataDisk(d.id ?? d.path)))}
                </div>
              </div>
            )}
            {profile === "server" && (
              <div className="field">
                <div className="field-label">Network ports for guests</div>
                <div className="choices">{hw.nics.map((n) => <label key={n.mac} className="choice" data-on={uplinks.includes(n.mac)}><input type="checkbox" checked={uplinks.includes(n.mac)} onChange={(e) => setUplinks(e.target.checked ? [...uplinks, n.mac] : uplinks.filter((m) => m !== n.mac))} /><span className="mono">{n.mac}</span><span className={`chip ${n.up ? "ok" : ""}`}>{n.up ? "cable in" : "no cable"}</span></label>)}</div>
              </div>
            )}
            <div className="facts"><span className="chip">GPU {hw.gpu}</span><span className={`chip ${hw.tpm ? "ok" : ""}`}>{hw.tpm ? "TPM 2.0" : "no TPM"}</span><span className={`chip ${hw.efi ? "ok" : "err"}`}>{hw.efi ? "UEFI" : "legacy BIOS"}</span></div>
          </div>
        );
      case "site":
        return (
          <div className="fields">
            <Field label="Host name"><input className="input mono" autoFocus value={host} onChange={(e) => setHost(e.target.value.toLowerCase())} placeholder="lowercase letters, digits and dashes" /></Field>
            <div className="field">
              <div className="field-label">Configuration</div>
              <div className="tray" style={{ alignSelf: "flex-start" }}>{(["new", "clone", "upload"] as const).map((m) => <button key={m} className="seg" aria-pressed={siteMode === m} onClick={() => setSiteMode(m)}>{m === "new" ? "Start new" : m === "clone" ? "From git" : "Upload"}</button>)}</div>
            </div>
            {siteMode === "clone" && <div className="row reveal"><input className="input mono grow" placeholder="https://… or ssh://…" value={siteUrl} onChange={(e) => setSiteUrl(e.target.value)} /><button className="btn" disabled={busy || !siteUrl} onClick={() => { setBusy(true); api.site({ mode: "clone", url: siteUrl }).then((r) => setSiteHosts(r.hosts)).catch((e) => setErr(e.message)).finally(() => setBusy(false)); }}>Clone</button></div>}
            {siteMode === "upload" && <input className="input reveal" type="file" accept=".tar,.tar.gz,.tgz" onChange={(e) => { const f = e.target.files?.[0]; if (!f) return; f.arrayBuffer().then((b) => api.site({ mode: "upload", tarball: btoa(String.fromCharCode(...new Uint8Array(b))) })).then((r) => setSiteHosts(r.hosts)).catch((x) => setErr(x.message)); }} />}
            {siteMode !== "new" && (
              <div className="field reveal">
                <div className="field-label">This machine's key, if the site already holds its secrets</div>
                <textarea className="input mono" rows={2} placeholder="AGE-SECRET-KEY-… (from `nixie backup kit`)" value={secrets["age.key"] ?? ""} onChange={(e) => setSecrets({ ...secrets, "age.key": e.target.value.trim() })} />
                <div className="caption field-help">Rebuilding a machine whose secrets are already in this site needs its old key; without one this machine gets a new identity and the site's existing secrets stay closed to it.</div>
              </div>
            )}
            {siteHosts.length > 0 && <div className="field reveal"><div className="caption">Machines in this site. Pick one to reinstall it, or type a new name to add this machine.</div><div className="facts">{siteHosts.map((h) => <button key={h} className="chip pick" aria-pressed={host === h} onClick={() => setHost(h)}>{h}</button>)}</div></div>}
            {siteMode === "new" && <OptionGroup opts={stepOpts.site} values={values} set={set} />}
          </div>
        );
      case "security":
        return (
          <OptionGroup opts={stepOpts.security} values={values} set={set} expanded={hardened} locked={lockedByHardening}>
            {secretsNeeded.filter((k) => k !== "tailscale").map(secretField)}
            {values["nixie.auth.secondFactor"] === "totp" && (
              <div className="panel reveal">
                <div className="field-label">Enrol the authenticator app</div>
                {!totp ? <button className="btn" style={{ alignSelf: "flex-start", marginTop: 8 }} onClick={() => api.totpNew().then(setTotp)}>Show QR code</button> : (
                  <div>
                    <pre className="well term qr">{totp.qr}</pre>
                    <div className="caption mono">{totp.secret}</div>
                    <div className="row"><input className="input mono" placeholder="code from the app" value={totpCode} onChange={(e) => setTotpCode(e.target.value)} /><button className="btn primary" onClick={() => api.totpVerify(totpCode).then(() => setTotpOk(true)).catch(() => setErr("That code is not right; try the next one."))}>Verify</button>{totpOk && <span className="chip ok">enrolled</span>}</div>
                  </div>
                )}
              </div>
            )}
          </OptionGroup>
        );
      case "network":
        return (
          <OptionGroup opts={stepOpts.network} values={values} set={set}>
            {on("nixie.network.tailscale.enable") && <div className="reveal"><Field label="Tailscale auth key (optional: without it, log in from the control panel later)"><input className="input mono" type="password" value={secrets.tailscale ?? ""} onChange={(e) => setSecrets({ ...secrets, tailscale: e.target.value })} /></Field></div>}
          </OptionGroup>
        );
      case "services":
        return <OptionGroup opts={shownOpts(s.id)} values={values} set={set} />;
      case "desktop":
        return (
          <div className="fields">
            <div className="cards">
              <button className="card" aria-pressed={!on(HYDE)} onClick={() => set(HYDE, false)}>
                <div className="card-title">Nixie desktop</div>
                <p className="caption">Hyprland in the installer's look. The finish colours everything, from the login screen to the apps. Installs offline.</p>
              </button>
              <button className="card" aria-pressed={on(HYDE)} disabled={!hw?.online} onClick={() => set(HYDE, true)}>
                <div className="card-title">HyDE</div>
                <p className="caption">{hw?.online ? "A complete third-party Hyprland desktop with its own themes, downloaded while installing." : "Needs a network connection while installing, and this machine is offline."}</p>
              </button>
            </div>
            <OptionGroup key={String(on(HYDE))} opts={shownOpts("desktop")} values={values} set={set} />
          </div>
        );
      case "review":
        return review();
      case "install": {
        const state = (n: number, prev: boolean): Item["state"] => (done.includes(n) ? "done" : running === n ? "running" : failed === n ? "failed" : prev ? "current" : "pending");
        const items: Item[] = [
          { key: "check", title: "Check the configuration", blurb: "It evaluates.", state: "done" },
          { key: "2", title: "Keys and secrets", blurb: "This machine's identity, and the secrets you typed, encrypted to it.", state: state(2, true), step: phaseStep?.phase === 2 ? phaseStep : undefined },
          { key: "3", title: `Erase ${disk} and install`, blurb: "Partition, format and install the system with the site.", state: state(3, done.includes(2)), step: phaseStep?.phase === 3 ? phaseStep : undefined },
          { key: "reboot", title: "Restart into setup", blurb: "Setup continues after the restart, on this screen and at this address.", state: done.includes(3) ? "current" : "pending", body: <div className="row"><button className="btn primary pulse" onClick={() => api.reboot()}>Restart now</button></div> },
        ];
        return (
          <div className="fields">
            <Checklist items={items} />
            {!done.includes(3) && <div className="row"><button className="btn primary" disabled={busy} onClick={async () => { if ((await run(2)) === 0) await run(3); }}>{busy ? "Installing…" : failed ? "Try again" : "Install"}</button></div>}
            <Log lines={lines} open={failed !== null} />
          </div>
        );
      }
    }
  };

  const canNext = () => {
    if (s.id === "hardware") return Boolean(disk) && (uplinks.length > 0 || profile === "desktop") && Boolean(hw?.efi);
    if (s.id === "site") return HOST_NAME.test(host);
    if (problems().length) return false;
    if (s.id === "security") return secretsNeeded.filter((k) => k !== "tailscale").every((k) => secrets[k]) && Boolean(values["nixie.auth.admin.name"]) && (values["nixie.auth.secondFactor"] !== "totp" || totpOk);
    if (s.id === "review") return checkOk;
    return true;
  };
  const next = async () => {
    if (steps[step + 1].id !== "review") return go(step + 1);
    setBusy(true);
    try {
      if (!(await submitConfig())) return;
    } catch (e) {
      return setErr((e as Error).message);
    } finally {
      setBusy(false);
    }
    go(step + 1);
    // The files were just written, so nothing to save first; edits counts from 0.
    void evaluate(0);
  };
  const problemList = problems();
  const following = steps[step + 1]?.id;

  return (
    <div className="wizard">
      <header className="wizard-head">
        <div className="brand-row"><Mark /><span className="wordmark">nixie</span><span className="chip">setup</span></div>
        <ol className="stepper">
          {steps.map((x, i) => (
            <li key={x.id} data-state={i < step ? "done" : i === step ? "current" : "pending"}>
              <button disabled={i >= step || locked} onClick={() => go(i)}><span className="num">{i < step ? "✓" : i + 1}</span><span className="label">{x.title}</span></button>
            </li>
          ))}
        </ol>
        <div />
        <div className="progress"><i style={{ transform: `scaleX(${step / (steps.length - 1)})` }} /></div>
      </header>
      <main className="wizard-main">
        <section key={s.id} className={`wizard-body step ${dir}`}>
          <div className="eyebrow">Step {step + 1} of {steps.length}</div>
          <h1 className="display">{s.title}</h1>
          <p className="caption lead">{s.blurb}</p>
          {body()}
          {problemList.map((m) => <p key={m} className="notice err">{m}</p>)}
          {err && <p className="notice err">{err}</p>}
        </section>
      </main>
      <footer className="wizard-foot">
        <button className="btn" disabled={step === 0 || locked} onClick={() => go(step - 1)}>Back</button>
        <span className="muted small">{busy && s.id !== "install" ? <span className="spinner" /> : null}</span>
        {following && <button className="btn primary" disabled={!canNext() || busy} onClick={next}>{following === "review" ? "Review" : following === "install" ? "Continue to install" : "Next"}</button>}
      </footer>
    </div>
  );
}

createRoot(document.getElementById("root")!).render(<Wizard />);
