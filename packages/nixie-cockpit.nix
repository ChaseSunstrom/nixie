# The host page's History screen: host generations, guest and data snapshots
# and restic backups, with the action for each. A Cockpit package, not a host
# agent: it asks the `nixie` command for JSON through the Cockpit bridge, so
# there is nothing new listening and nothing new to authenticate.
{
  pkgs,
  lib ? pkgs.lib,
}:
let
  t = (import ../lib/tokens.nix { inherit lib; }).forFinish "graphite";
  manifest = builtins.toJSON {
    version = 0;
    requires.cockpit = "266";
    menu.index = {
      label = "History";
      order = 30;
      docs = [
        {
          label = "What can be rolled back";
          url = "https://github.com/OWNER/nixie/blob/master/docs/guides/restore.md";
        }
      ];
    };
  };
in
pkgs.runCommand "nixie-cockpit" { meta.priority = 4; } ''
  d=$out/share/cockpit/nixie-history
  mkdir -p "$d"
  cat >"$d/manifest.json" <<'JSON'
  ${manifest}
  JSON
  cat >"$d/index.html" <<'HTML'
  <!DOCTYPE html>
  <html>
    <head>
      <meta charset="utf-8" />
      <title>History</title>
      <link rel="stylesheet" href="../base1/cockpit.css" />
      <style>
        body { background: ${t.bg}; color: ${t.ink}; font-family: Archivo, sans-serif; margin: 0; padding: 16px; }
        h2 { font-size: 15px; font-weight: 500; letter-spacing: -0.01em; margin: 18px 0 8px; }
        .card { background: ${t.s1}; border: 1px solid ${t.line}; border-radius: 10px; box-shadow: 0 8px 24px -14px ${t.shadow}; padding: 12px 14px; margin-bottom: 14px; }
        table { width: 100%; border-collapse: collapse; font-size: 12px; }
        td, th { text-align: left; padding: 5px 8px; border-bottom: 1px solid ${t.line}; }
        th { color: ${t.muted}; font-weight: 500; }
        .mono { font-family: "JetBrains Mono", monospace; }
        .muted { color: ${t.muted}; }
        .chip { background: ${t.brand}; color: ${t.bg}; border-radius: 999px; padding: 1px 8px; font-size: 11px; }
        .err { color: ${t.err}; }
      </style>
    </head>
    <body>
      <div id="root" class="muted">reading the host's history…</div>
      <script src="../base1/cockpit.js"></script>
      <script src="history.js"></script>
    </body>
  </html>
  HTML
  cat >"$d/history.js" <<'JS'
  // One call, one shape: whatever `nixie rollback --json` says.
  const el = document.getElementById("root");
  const esc = (s) => String(s === undefined || s === null ? "" : s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const when = (s) => (s ? new Date(s).toLocaleString() : "");

  function table(head, rows) {
    if (rows.length === 0) return '<p class="muted">none yet</p>';
    const th = head.map((h) => "<th>" + esc(h) + "</th>").join("");
    const tr = rows.map((r) => "<tr>" + r.map((c) => "<td>" + c + "</td>").join("") + "</tr>").join("");
    return "<table><thead><tr>" + th + "</tr></thead><tbody>" + tr + "</tbody></table>";
  }

  function render(h) {
    const gens = h.generations.slice().reverse().map((g) => [
      '<span class="mono">' + esc(g.generation) + "</span>",
      esc(g.label),
      '<span class="mono muted">' + esc(g.kernel) + "</span>",
      '<span class="muted">' + esc(when(g.date)) + "</span>",
      (g.current ? '<span class="chip">current</span> ' : "") + (g.booted && !g.current ? '<span class="chip">booted</span>' : ""),
      '<code class="muted">nixie rollback --generation ' + esc(g.generation) + "</code>",
    ]);
    const guests = h.guests.map((s) => [
      esc(s.guest),
      '<span class="mono">' + esc(s.name) + "</span>",
      '<span class="muted">' + esc(when(s.taken)) + "</span>",
      '<code class="muted">nixie rollback guest ' + esc(s.guest) + " --snapshot " + esc(s.name) + "</code>",
    ]);
    const data = h.data.map((s) => [
      '<span class="mono">' + esc(s.name) + "</span>",
      '<span class="muted">' + esc(when(s.taken)) + "</span>",
      '<code class="muted">nixie rollback data state --snapshot ' + esc(s.name) + "</code>",
    ]);
    const backups = h.backups.map((b) => [
      '<span class="mono">' + esc(b.id) + "</span>",
      '<span class="muted">' + esc(when(b.taken)) + "</span>",
      '<span class="muted">' + esc((b.paths || []).join(" ")) + "</span>",
      '<code class="muted">nixie restore ' + esc(b.id) + "</code>",
    ]);
    el.innerHTML =
      '<div class="card"><h2>System generations</h2>' + table(["gen", "label", "kernel", "taken", "", "roll back with"], gens) + "</div>" +
      '<div class="card"><h2>Guest snapshots</h2>' + table(["guest", "snapshot", "taken", "restore with"], guests) + "</div>" +
      '<div class="card"><h2>Data snapshots</h2>' + table(["snapshot", "taken", "restore with"], data) + "</div>" +
      '<div class="card"><h2>Backups</h2>' + table(["id", "taken", "paths", "restore with"], backups) + "</div>";
  }

  cockpit
    .spawn(["nixie", "rollback", "--json"], { superuser: "try", err: "message" })
    .then((out) => render(JSON.parse(out)))
    .catch((e) => {
      el.innerHTML = '<p class="err">The host did not answer: ' + esc(e.message || e) + "</p>";
    });
  JS
''
