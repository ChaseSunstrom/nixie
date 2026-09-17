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
