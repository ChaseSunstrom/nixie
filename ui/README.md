# nixie-web

One npm workspace, two pages: the control panel (`/`) and the installer
wizard (`/setup/`). React, TypeScript, Vite; uPlot for dashboards; xterm.js
for terminals. Everything is vendored through the committed lockfile and
built with `buildNpmPackage`; fonts are copied in at build time. `?demo`
forces demo mode; otherwise the panel talks to the Incus API on its own
origin and falls back to demo data when the daemon is silent.
`npm run build` builds locally; `nix build .#nixie-ui` builds for real.
