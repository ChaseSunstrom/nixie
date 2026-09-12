// History: what this host can go back to. Generations come from the system
// profile, guest and data snapshots from the host, backups from restic; the
// page reads one JSON the CLI prints and never scrapes human output.
import { useEffect, useState } from "react";
import { Panel } from "../components/ui";

type Generation = { generation: number; date: string; label: string; kernel: string; current: boolean; booted: boolean };
type GuestSnap = { guest: string; name: string; taken: string };
type DataSnap = { name: string; taken: string };
type Backup = { id: string; taken: string; paths: string[] };
type Hist = { generations: Generation[]; guests: GuestSnap[]; data: DataSnap[]; backups: Backup[] };

const when = (s: string) => (s ? new Date(s).toLocaleString() : "");

export function History({ source }: { source?: () => Promise<Hist> }) {
  const [hist, setHist] = useState<Hist | null>(null);
  const [error, setError] = useState("");
  useEffect(() => {
    const load = source ?? (() => fetch("/nixie/history.json").then((r) => r.json()));
    load()
      .then(setHist)
      .catch((e) => setError(String(e)));
  }, [source]);

  if (error) return <Panel title="History"><p className="muted">The host has not published its history: {error}</p></Panel>;
  if (!hist) return <Panel title="History"><p className="muted">reading…</p></Panel>;

  return (
    <>
      <Panel title="System generations" sub={`${hist.generations.length} kept`}>
        <div className="rows">
          {hist.generations.slice().reverse().map((g) => (
            <div className="row gen" key={g.generation}>
              <span className="mono">{g.generation}</span>
              <span>{g.label}</span>
              <span className="muted mono">{g.kernel}</span>
              <span className="muted">{when(g.date)}</span>
              <span>
                {g.current && <span className="chip ok">current</span>}
                {g.booted && !g.current && <span className="chip">booted</span>}
              </span>
              <code className="muted">nixie rollback --generation {g.generation}</code>
            </div>
          ))}
        </div>
      </Panel>

      <Panel title="Guest snapshots" sub={`${hist.guests.length}`}>
        {hist.guests.length === 0 && <p className="muted">none yet; `nixie apply` takes one before it touches a guest</p>}
        <div className="rows">
          {hist.guests.map((s) => (
            <div className="row" key={`${s.guest}/${s.name}`}>
              <span>{s.guest}</span>
              <span className="mono">{s.name}</span>
              <span className="muted">{when(s.taken)}</span>
              <code className="muted">nixie rollback guest {s.guest} --snapshot {s.name}</code>
            </div>
          ))}
        </div>
      </Panel>

      <Panel title="Data snapshots" sub={`${hist.data.length}`}>
        {hist.data.length === 0 && <p className="muted">none yet</p>}
        <div className="rows">
          {hist.data.map((s) => (
            <div className="row" key={s.name}>
              <span className="mono">{s.name}</span>
              <span className="muted">{when(s.taken)}</span>
              <code className="muted">nixie rollback data state --snapshot {s.name}</code>
            </div>
          ))}
        </div>
      </Panel>

      <Panel title="Backups" sub={`${hist.backups.length} restic snapshots`}>
        {hist.backups.length === 0 && <p className="muted">none yet, or backups are off on this host</p>}
        <div className="rows">
          {hist.backups.map((b) => (
            <div className="row" key={b.id}>
              <span className="mono">{b.id}</span>
              <span className="muted">{when(b.taken)}</span>
              <span className="muted">{(b.paths ?? []).join(" ")}</span>
              <code className="muted">nixie restore {b.id}</code>
            </div>
          ))}
        </div>
      </Panel>
    </>
  );
}
