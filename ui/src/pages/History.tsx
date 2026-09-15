// History: what this host can go back to. Guest snapshots come from the Incus
// API like the rest of this panel. Host generations, data snapshots and
// backups are on the host page (ARCHITECTURE D22): going back runs `nixie` as
// the administrator, and this static bundle has no host process to ask.
import { Panel, usePoll } from "../components/ui";
import { useStore } from "../lib/store";

const when = (s: string) => (s ? new Date(s).toLocaleString() : "");

export function History() {
  const { api, instances, site } = useStore();
  const names = instances.map((i) => i.name);
  const [snaps] = usePoll(
    () => Promise.all(names.map((g) => api.snapshots(g).then((l) => l.map((s) => ({ guest: g, ...s }))).catch(() => []))).then((l) => l.flat()),
    [api, names.join(" ")],
    30000,
  );
  const rows = (snaps ?? []).slice().sort((a, b) => b.created_at.localeCompare(a.created_at));
  return (
    <>
      <Panel title="Guest snapshots" sub={snaps ? `${rows.length}` : "reading…"}>
        {snaps && rows.length === 0 && <p className="muted">none yet; `nixie apply` takes one before it changes a guest, and Snapshot on an instance takes one now</p>}
        {rows.length > 0 && (
          <div className="table" style={{ gridTemplateColumns: "140px 1fr 180px 1.4fr" }}>
            <span className="h">guest</span>
            <span className="h">snapshot</span>
            <span className="h">taken</span>
            <span className="h">to go back</span>
            {rows.map((s) => (
              <span key={`${s.guest}/${s.name}`} style={{ display: "contents" }}>
                <a href={`#/instances/${s.guest}/snapshots`}>{s.guest}</a>
                <span className="mono">{s.name}</span>
                <span className="muted">{when(s.created_at)}</span>
                <code className="muted">nixie rollback guest {s.guest} --snapshot {s.name}</code>
              </span>
            ))}
          </div>
        )}
      </Panel>

      <Panel title="Host generations, data snapshots and backups">
        <p className="muted">These are kept on the host page, behind the administrator's login, because going back to one runs `nixie` on the host.</p>
        {site.hostUiUrl ? (
          <a className="btn primary" href={`${site.hostUiUrl}/nixie-history`}>Open History on the host page</a>
        ) : (
          <p>Over SSH, <code>nixie rollback --list</code> shows them, as does the front panel on the machine's screen. With <code>nixie.hostUi.enable = true</code> they appear on the host page too.</p>
        )}
      </Panel>
    </>
  );
}
