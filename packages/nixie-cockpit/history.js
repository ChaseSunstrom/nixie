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

// What the machine wants you to know, above its history: a newer site
// waiting, an apply to confirm, a failed backup check.
function notices(n) {
  const box = document.getElementById("notices");
  if (!n.notices.length) { box.innerHTML = ""; return; }
  box.innerHTML = n.notices.map((x) =>
    '<div class="card ' + (x.level === "warn" ? "warn" : "") + '"><h2>' + esc(x.title) + "</h2>" +
    "<p>" + esc(x.detail) + "</p>" +
    (x.id === "update" ? '<button id="apply-update">Apply it now</button> ' : "") +
    '<code class="muted">' + esc(x.action) + "</code></div>").join("");
  const button = document.getElementById("apply-update");
  if (button) button.onclick = () => {
    button.disabled = true;
    button.textContent = "Applying…";
    cockpit.spawn(["nixie", "update", "--now"], { superuser: "require", err: "message" })
      .then(() => load())
      .catch((e) => { button.textContent = "It did not apply: " + (e.message || e); });
  };
}

// The three things a person opens the host page to run, with their output as
// it arrives rather than at the end. They are the same commands the machine
// runs for itself; nothing new is listening, the Cockpit bridge carries them.
const RUNNABLE = [
  { id: "apply", label: "Apply the site", argv: ["nixie", "apply", "--yes"], superuser: "require" },
  { id: "fetch", label: "Fetch the cache", argv: ["nixie", "fetch"], superuser: "require" },
  { id: "doctor", label: "Run the checks", argv: ["nixie", "doctor"], superuser: "try" },
];

function actions() {
  const box = document.getElementById("actions");
  box.innerHTML =
    '<div class="card"><h2>Run</h2>' +
    '<p class="muted">Each prints as it goes. Applying switches this machine and brings the guests the site declares with it.</p>' +
    RUNNABLE.map((r) => '<button id="run-' + r.id + '">' + esc(r.label) + "</button> ").join("") +
    '<pre id="output" class="mono out" hidden></pre></div>';
  const out = document.getElementById("output");
  const buttons = RUNNABLE.map((r) => document.getElementById("run-" + r.id));
  const idle = (on) => buttons.forEach((b) => (b.disabled = !on));
  for (const r of RUNNABLE) {
    document.getElementById("run-" + r.id).onclick = () => {
      idle(false);
      out.hidden = false;
      out.textContent = "$ " + r.argv.join(" ") + "\n";
      cockpit
        .spawn(r.argv, { superuser: r.superuser, err: "out" })
        .stream((data) => {
          out.textContent += data;
          out.scrollTop = out.scrollHeight;
        })
        .then(() => {
          out.textContent += "\n— done\n";
          idle(true);
          // What it did shows in the history and the notices below.
          actions();
load();
        })
        .catch((e) => {
          out.textContent += "\n— it stopped: " + (e.message || e) + "\n";
          idle(true);
        });
    };
  }
}

function load() {
  cockpit
    .spawn(["nixie", "notices", "--json"], { superuser: "try", err: "message" })
    .then((out) => notices(JSON.parse(out)))
    .catch(() => undefined);
  cockpit
    .spawn(["nixie", "rollback", "--json"], { superuser: "try", err: "message" })
    .then((out) => render(JSON.parse(out)))
    .catch((e) => {
      el.innerHTML = '<p class="err">The host did not answer: ' + esc(e.message || e) + "</p>";
    });
}

actions();
load();
