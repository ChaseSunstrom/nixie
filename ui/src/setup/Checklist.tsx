// Setup as a checklist: the install and each phase after the first boot as
// one list, the current item open with what it needs, the phase output
// folded under Details.
import { useEffect, useRef, useState, type ReactNode } from "react";
import { Field } from "../components/ui";
import { PathPicker } from "./fields";
import { api, type State } from "./api";

export type ItemState = "done" | "current" | "running" | "failed" | "pending";
export type Step = { phase: number; done: number; total: number; text: string };
export type Item = { key: string; title: string; blurb: string; state: ItemState; body?: ReactNode; step?: Step };

function Icon({ state, n }: { state: ItemState; n: number }) {
  if (state === "done")
    return (
      <svg className="check-icon done" viewBox="0 0 24 24" aria-label="done">
        <circle cx="12" cy="12" r="11" />
        <path d="M7 12.5l3.2 3.2L17 9" />
      </svg>
    );
  if (state === "failed") return <span className="check-icon failed" aria-label="failed">!</span>;
  return <span className={`check-icon ${state}`} aria-label={state}>{state === "running" ? "" : n}</span>;
}

export function Checklist({ items }: { items: Item[] }) {
  // The kiosk has no one scrolling it: the step at work stays in view.
  const current = useRef<HTMLLIElement>(null);
  const at = items.findIndex((it) => it.state !== "done");
  useEffect(() => { current.current?.scrollIntoView({ block: "nearest", behavior: "smooth" }); }, [at]);
  return (
    <ol className="checklist">
      {items.map((it, i) => (
        <li key={it.key} ref={i === at ? current : undefined} className="check-item" data-state={it.state}>
          <Icon state={it.state} n={i + 1} />
          <div className="check-text">
            <div className="check-title">{it.title}</div>
            <div className="caption">{it.blurb}</div>
            {it.step && it.state === "running" && (
              <div className="step-progress">
                <div className="progress-line"><i style={{ width: `${Math.round((it.step.done / Math.max(1, it.step.total)) * 100)}%` }} /></div>
                <div className="caption small">{it.step.text} · {it.step.done} of {it.step.total}</div>
              </div>
            )}
            {it.body && it.state !== "done" && it.state !== "pending" && <div className="check-body reveal">{it.body}</div>}
          </div>
        </li>
      ))}
    </ol>
  );
}

export function Log({ lines, open }: { lines: string[]; open: boolean }) {
  const ref = useRef<HTMLPreElement>(null);
  useEffect(() => { ref.current?.scrollTo(0, ref.current.scrollHeight); }, [lines]);
  return (
    <details className="log" open={open || undefined}>
      <summary>Details</summary>
      <pre ref={ref} className="well term">{lines.join("\n") || "output appears here"}</pre>
    </details>
  );
}

type Run = (n: number, body?: Record<string, unknown>) => Promise<number>;

// For typing in by hand when a camera is not at hand.
const secretOf = (uri: string) => {
  try {
    return new URL(uri).searchParams.get("secret") ?? "";
  } catch {
    return "";
  }
};

// Phases 4 to 8 and Finish, on the installed machine's setup generation. It
// runs by itself: a phase this machine does not use is recorded without being
// shown, and the page stops only for what a person must do, typing the
// passphrase and PIN or restarting for Secure Boot.
export function Continuation({ st, run, busy, setBusy, lines, setLines, err, setErr, failed, running, step }: { st: State; run: Run; busy: boolean; setBusy: (b: boolean) => void; lines: string[]; setLines: (f: (l: string[]) => string[]) => void; err: string; setErr: (e: string) => void; failed: number | null; running: number | null; step: Step | null }) {
  const done = st.done;
  const features = (st.layout?.features ?? {}) as Record<string, boolean>;
  const host = String(st.state.host ?? st.host);
  const [secrets, setSecrets] = useState<Record<string, string>>({});
  const [recovery, setRecovery] = useState({ key: "", qr: "", attestUri: "", attestQr: "" });
  // What phase 5 asked for: 10 a restart that enrols the keys, 11 the firmware settings.
  const [sb, setSb] = useState<number | null>(null);
  // The kiosk browser is on this machine, where a download goes nowhere; the
  // headers can be written to a drive instead.
  const [dest, setDest] = useState("");
  const [copied, setCopied] = useState("");

  const phases = [
    { n: 4, title: "First start", blurb: "The identity and the site are in place.", used: true },
    { n: 5, title: "Secure Boot", blurb: "Turn Secure Boot on with this machine's own keys.", used: Boolean(features.secureBoot) },
    { n: 6, title: features.tpm ? "Disk unlock" : "Header backup", blurb: features.tpm ? "Bind the disk to this machine's TPM with a PIN, and test that they open it." : "Save a backup of the disk's encryption headers.", used: Boolean(features.encryption) },
    { n: 7, title: "Checks", blurb: "Confirm each security feature works on this start.", used: true },
    { n: 8, title: "Apply the site", blurb: "Create the guests, data and services the site declares.", used: true },
  ];
  const next = phases.find((p) => !done.includes(p.n));
  const waiting = next?.n === 5 ? sb !== null : next?.n === 6 && Boolean(features.tpm);

  const go = async (n: number) => {
    setSb(null);
    if (n === 6) await api.secrets({ passphrase: secrets.passphrase ?? "", pin: secrets.pin ?? "" });
    const rc = await run(n);
    if (n === 5 && (rc === 10 || rc === 11)) setSb(rc);
    if (n === 6 && rc === 0) api.attestation().then((a) => setRecovery({ key: a.recovery, qr: a.recoveryQr, attestUri: a.attestUri, attestQr: a.attestQr })).catch(() => undefined);
  };

  // Until Finish removes them, a reload must not lose what is shown once.
  useEffect(() => {
    if (done.includes(6) && (features.tpm || features.attestation)) api.attestation().then((a) => setRecovery({ key: a.recovery, qr: a.recoveryQr, attestUri: a.attestUri, attestQr: a.attestQr })).catch(() => undefined);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (next && !busy && !waiting && failed !== next.n) void go(next.n);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [next?.n, busy, waiting, failed]);

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
        setErr("Finish stopped; Details says why. Fix the site and press Finish again.");
        setBusy(false);
      }).catch(() => undefined), 3000);
    }).catch((e) => { setErr((e as Error).message); setBusy(false); });
  };

  const bodyFor = (n: number): ReactNode => {
    if (failed === n && !(n === 6 && features.tpm)) return <div className="row"><button className="btn primary" disabled={busy} onClick={() => go(n)}>Try again</button></div>;
    if (n === 5 && sb === 10)
      return (
        <>
          <p className="caption">The keys are ready. The firmware enrols them while the machine restarts, and setup carries on by itself afterwards.</p>
          <div className="row"><button className="btn primary pulse" onClick={() => api.reboot()}>Restart</button></div>
        </>
      );
    if (n === 5 && sb === 11)
      return (
        <>
          <ol className="caption steps">
            <li>In the firmware settings, find Secure Boot and keep it enabled.</li>
            <li>Delete or clear its keys; that is Setup Mode.</li>
            <li>Save and exit. Setup carries on by itself.</li>
          </ol>
          <div className="row">
            <button className="btn primary" onClick={() => api.reboot(true)}>Restart into firmware settings</button>
            <button className="btn" onClick={() => go(5)}>Check again</button>
          </div>
        </>
      );
    if (n === 6 && features.tpm)
      return (
        <form className="fields" onSubmit={(e) => { e.preventDefault(); void go(6); }}>
          <Field label="Disk passphrase"><input className="input" type="password" autoFocus value={secrets.passphrase ?? ""} onChange={(e) => setSecrets({ ...secrets, passphrase: e.target.value })} /></Field>
          <Field label="TPM PIN, asked at every start"><input className="input" type="password" value={secrets.pin ?? ""} onChange={(e) => setSecrets({ ...secrets, pin: e.target.value })} /></Field>
          <div className="row"><button className="btn primary" disabled={busy || !secrets.passphrase || !secrets.pin}>Continue</button></div>
        </form>
      );
    return null;
  };

  const items: Item[] = [
    { key: "install", title: "Install", blurb: `${host} is installed.`, state: "done" },
    ...phases.filter((p) => p.used).map((p): Item => ({
      key: String(p.n),
      title: p.title,
      blurb: p.blurb,
      state: done.includes(p.n) ? "done" : running === p.n ? "running" : failed === p.n ? "failed" : p === next ? "current" : "pending",
      body: bodyFor(p.n),
      step: step?.phase === p.n ? step : undefined,
    })),
    {
      key: "finish",
      title: "Finish",
      blurb: "Switch to the normal system and remove setup. From then on the control panel is the only web page on this host.",
      state: next ? "pending" : busy ? "running" : "current",
      body: (
        <>
          {features.encryption && (
            <div className="fields">
              <Field label="Copy the disk's encryption headers to a drive">
                <PathPicker value={dest} onChange={(v) => { setDest(v); setCopied(""); }} placeholder="a folder, or choose a drive" />
              </Field>
              <div className="row">
                <button className="btn" disabled={!dest} onClick={() => api.copyHeaderBackup(dest).then((r) => setCopied(r.path)).catch((e) => setErr((e as Error).message))}>Copy</button>
                <a className="btn" href="/api/download/header-backup" download>Download instead</a>
                {copied && <span className="caption">Written to {copied}</span>}
              </div>
            </div>
          )}
          <div className="row">
            <button className="btn primary" disabled={busy} onClick={finishSetup}>Finish</button>
          </div>
        </>
      ),
    },
  ];

  return (
    <>
      <h1 className="display">Setting up {host}</h1>
      <p className="caption lead">This runs by itself and picks up where it left off after a restart. It stops only when it needs you.</p>
      {(recovery.key || recovery.attestQr) && (
        <div className="panel keep reveal">
          <div className="check-title">Save these now: they are shown once</div>
          {recovery.key && <div><div className="caption">The recovery key opens the disk when the TPM cannot. It is never stored on this machine.</div>{recovery.qr && <img className="qr-img" src={recovery.qr} alt="The recovery key as a QR code" />}<pre className="well mono">{recovery.key}</pre></div>}
          {recovery.attestQr && <div><div className="caption">Scan the attestation code with your authenticator app, or type the secret under it.</div><img className="qr-img" src={recovery.attestQr} alt="The attestation secret as a QR code" /><div className="caption mono">{secretOf(recovery.attestUri)}</div></div>}
        </div>
      )}
      <Checklist items={items} />
      {err && <p className="notice err">{err}</p>}
      <Log lines={lines} open={failed !== null} />
    </>
  );
}
