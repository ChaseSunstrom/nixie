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

// The control panel's Declare arrives here, as a name in the address: incusd
// serves that panel and runs nothing on this host, and this page already
// has the person signed in. An instance name and nothing else.
function declaring() {
  const m = /^#declare=([A-Za-z0-9][A-Za-z0-9._-]*)$/.exec(decodeURIComponent(location.hash));
  return m ? m[1] : null;
}

function actions() {
  const box = document.getElementById("actions");
  const name = declaring();
  const runnable = (name
    ? [{ id: "declare", label: "Declare " + name, argv: ["nixie", "declare", name], superuser: "require" }]
    : []
  ).concat(RUNNABLE);
  box.innerHTML =
    '<div class="card"><h2>Run</h2>' +
    (name
      ? '<p>Declaring <span class="mono">' + esc(name) + "</span> writes it into the site's guests.nix and applies. It keeps running; applying adopts it rather than making a second one.</p>"
      : "") +
    '<p class="muted">Each prints as it goes. Applying switches this machine and brings the guests the site declares with it.</p>' +
    runnable.map((r) => '<button id="run-' + r.id + '">' + esc(r.label) + "</button> ").join("") +
    '<pre id="output" class="mono out" hidden></pre></div>';
  const out = document.getElementById("output");
  const buttons = runnable.map((r) => document.getElementById("run-" + r.id));
  const idle = (on) => buttons.forEach((b) => (b.disabled = !on));
  for (const r of runnable) {
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

// Which exit each scope uses (modules/network/exits.nix), with a way to pin
// one or hand it back to its list. Absent when the host has no exits.
function egress() {
  const box = document.getElementById("egress");
  cockpit
    .spawn(["nixie", "egress", "status", "--json"], { superuser: "try", err: "message" })
    .then((out) => {
      const st = JSON.parse(out);
      const exits = Object.keys(st.exits);
      const arg = (scope) => (scope === "host" ? ["--host"] : scope === "guests" ? ["--guests"] : ["--guest", scope.slice(6)]);
      const scopes = Object.entries(st.scopes).filter(([s]) => !s.startsWith("tor-") && s !== "tailnet-clients");
      const rows = scopes.map(([s, v]) => [
        esc(s === "host" ? "this machine" : s === "guests" ? "guests" : s.slice(6)),
        v.using === "none" ? '<span class="err">cut off: no exit works</span>' : esc(v.using),
        '<span class="muted">' + esc(v.list.length ? v.list.join(" → ") : "direct") + "</span>",
        '<select data-scope="' + esc(s) + '"><option value="auto"' + (v.pinned ? "" : " selected") + ">follow the list</option>" +
          ["direct"].concat(exits).map((e) => '<option value="' + esc(e) + '"' + (v.pinned && v.using === e ? " selected" : "") + ">" + esc(e) + "</option>").join("") +
          "</select>",
      ]);
      const health = exits.map((e) => '<span class="' + (st.exits[e].up ? "" : "err") + '">' + esc(e) + (st.exits[e].up ? " up" : " down") +
        (st.servers && st.servers[e] ? " (" + esc(st.servers[e]) + ")" : "") + "</span>").join(" · ");
      box.innerHTML = '<div class="card"><h2>Egress</h2><p>' + health + "</p>" +
        table(["for", "leaving by", "list", "pin"], rows) + "</div>";
      for (const sel of box.querySelectorAll("select")) {
        sel.onchange = () => {
          const argv = sel.value === "auto" ? ["nixie", "egress", "auto"] : ["nixie", "egress", "use", sel.value];
          sel.disabled = true;
          cockpit.spawn(argv.concat(arg(sel.dataset.scope)), { superuser: "require", err: "message" })
            .then(() => setTimeout(egress, 2000))
            .catch((e) => { box.insertAdjacentHTML("beforeend", '<p class="err">' + esc(e.message || e) + "</p>"); sel.disabled = false; });
        };
      }
    })
    .catch(() => { box.innerHTML = ""; });
}

function load() {
  egress();
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
