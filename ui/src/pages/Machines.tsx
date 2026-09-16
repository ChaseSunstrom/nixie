// Every machine of this site, not only the one that serves this panel. The
// site file names them all, so each entry can open that machine's own panel.
import { useStore } from "../lib/store";
import { Panel, PageHead, Empty } from "../components/ui";

// Demo mode has no site file; two machines show what the page is for.
const DEMO = [
  { name: "server", profile: "server", url: "https://192.0.2.10:8443" },
  { name: "laptop", profile: "desktop", url: null },
];

export function Machines() {
  const { site, instances, demo } = useStore();
  const machines = site.machines.length ? site.machines : demo ? DEMO : [];
  const here = demo ? "server" : site.host;
  return (
    <>
      <PageHead title="Machines" count={machines.length} sub="The machines this site installs. Each runs its own panel; this page is the way between them." />
      <div className="grid12">
        {machines.map((m) => {
          const current = m.name === here;
          const url = m.url ?? `https://${m.name}:8443`;
          return (
            <Panel key={m.name} span={4} title={m.name} sub={m.profile === "unknown" ? undefined : m.profile} value={current ? <span className="chip brand">this machine</span> : undefined}>
              <div className="table" style={{ gridTemplateColumns: "90px 1fr" }}>
                <span className="muted">panel</span><span className="mono">{url}</span>
                <span className="muted">address</span><span>{m.url ? "fixed in the site" : "from the router; the name has to resolve"}</span>
                {current && <><span className="muted">guests</span><span>{instances.length}</span></>}
              </div>
              <div className="row" style={{ marginTop: 10 }}>
                {current ? <a className="btn" href="#/instances">Its guests</a> : <a className="btn primary" href={url}>Open its panel</a>}
              </div>
            </Panel>
          );
        })}
        {!machines.length && <Panel span={12}><Empty>This panel was built before the site listed its machines; the next `nixie apply` fills the list in.</Empty></Panel>}
        <Panel span={12} title="Add another machine" sub="from any machine of this site" dense>
          <p className="caption">Add it to <code>site.nix</code>, then install it from the ISO wizard with this site's repository, or over the network from a machine that has the site:</p>
          <pre className="well term" style={{ minHeight: 0 }}>{`nix run nixie#deploy -- --site . --host <name> root@<address>`}</pre>
          <p className="caption">The new machine writes its own <code>hosts/&lt;name&gt;/hardware.nix</code>, and appears here after the next <code>nixie apply</code>.</p>
        </Panel>
      </div>
    </>
  );
}
