// The bridge as a trunk with drops, as drawn in the design: host root dot,
// instance dots alternating above and below, the tunnel to the internet.
import type { Instance, Network } from "../lib/api";

export function Topology({ instances, networks }: { instances: Instance[]; networks: Network[] }) {
  const W = 520;
  const H = 190;
  const bridge = networks.find((n) => n.type === "bridge")?.name ?? "bridge";
  const tunnel = networks.some((n) => n.name === "tailscale0");
  const shown = instances.slice(0, 8);
  const gap = (W - 120) / Math.max(1, shown.length);
  return (
    <div className="well" style={{ margin: "0 0 4px", flex: 1 }}>
      <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", height: "100%", display: "block" }}>
        <line x1="30" x2={W - 90} y1={H / 2} y2={H / 2} stroke="var(--net)" strokeWidth="2" />
        <circle cx="30" cy={H / 2} r="5" fill="var(--ink)" />
        <text x="30" y={H / 2 + 22} fontSize="12" fontWeight="500" fill="var(--ink)" textAnchor="middle">
          host
        </text>
        <text x={(W - 60) / 2} y={H / 2 - 8} fontSize="10" fill="var(--muted)" textAnchor="middle">
          {bridge}
        </text>
        {shown.map((i, n) => {
          const x = 70 + n * gap;
          const up = n % 2 === 0;
          // The lower row sits clear of the legend along the bottom edge.
          const y = up ? 40 : H - 58;
          const frozen = i.status === "Frozen";
          const stopped = i.status === "Stopped";
          const ks = i.profiles?.includes("killswitch");
          return (
            <g key={i.name}>
              <line x1={x} x2={x} y1={H / 2} y2={y} stroke="var(--net)" strokeWidth="1.5" strokeDasharray={frozen || stopped ? "3 3" : undefined} />
              {ks && <circle cx={x} cy={y} r="10" fill="none" stroke="var(--err)" strokeWidth="2" />}
              <circle cx={x} cy={y} r="6" fill={stopped ? "var(--muted)" : frozen ? "var(--ice)" : "var(--ok)"} />
              <text x={x} y={up ? y - 12 : y + 18} fontSize="12" fontWeight="500" fill={frozen || stopped ? "var(--muted)" : "var(--ink)"} textAnchor="middle">
                {i.name}
              </text>
            </g>
          );
        })}
        {tunnel && (
          <g>
            <path d={`M${W - 90} ${H / 2} C ${W - 60} ${H / 2}, ${W - 60} ${H / 2 - 40}, ${W - 30} ${H / 2 - 40}`} fill="none" stroke="var(--ok)" strokeWidth="2.5" />
            <circle cx={W - 30} cy={H / 2 - 40} r="7" fill="none" stroke="var(--ok)" strokeWidth="2" />
            <text x={W - 30} y={H / 2 - 54} fontSize="12" fontWeight="500" fill="var(--ink)" textAnchor="middle">
              internet
            </text>
            <text x={W - 60} y={H / 2 + 14} fontSize="10" fill="var(--muted)" textAnchor="middle">
              tailnet
            </text>
          </g>
        )}
        <g transform={`translate(30 ${H - 12})`} fontSize="10" fill="var(--muted)">
          <circle cx="0" cy="-3" r="4" fill="var(--net)" />
          <text x="8" y="0">LAN</text>
          <circle cx="50" cy="-3" r="4" fill="var(--ok)" />
          <text x="58" y="0">tailnet</text>
          <circle cx="110" cy="-3" r="4" fill="none" stroke="var(--err)" strokeWidth="2" />
          <text x="118" y="0">killswitch</text>
        </g>
      </svg>
    </div>
  );
}
