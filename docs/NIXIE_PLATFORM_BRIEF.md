# Claude Code brief: build Nixie, a NixOS platform with a server profile and a desktop profile

You are building **Nixie**: a reusable, open-source NixOS platform with one installer and two profiles. The **server** profile turns any UEFI x86_64 machine into a hardened host that runs services as isolated Incus guests, declared in Nix, with a web UI. The **desktop** profile turns the same machine into a daily-driver workstation with a fully built Hyprland environment. One ISO, one installer, one security stack; a profile is chosen at install and a system contains only its own profile's software. The repo root contains `design/Nixie_Front_Panel.html`, the approved design for every web surface (the control panel and the installer); it is the visual source of truth.

This repo is the **platform**. It contains nothing about any particular person's services, hardware, or network. Users consume it from their own **site** repo, which holds their hosts, guests, data manifest, and choices. Build the platform so that a site can express anything in section 12 without patching the platform.

Read this whole brief before writing anything, then follow section 14.

## 1. The one-sentence goal

Boot a machine from the Nixie ISO, click through a short graphical setup on that machine or from a browser on the LAN, choose server or desktop, and end up with a reproducible NixOS system with every security feature the user chose enabled: a hardened Incus host ready for declared guests, or a complete Hyprland desktop, and the same thing reproducible headlessly from a site repo with one command.

## 2. Non-negotiable properties

1. **Nothing user-specific in the platform.** No service names, IP ranges, model lists, hardware, or network topology. Examples live in `examples/` and the site template, and are clearly generic (`web`, `db`, `worker`).
2. **Infrastructure as code, fully.** A site repo plus a generated `hardware.nix` fully determines a host. Anything the installer does is also a script the flake ships; the installer is a front end to those scripts, never a second implementation.
3. **Hardware-agnostic.** No disk paths, interface names, MACs, PCI addresses, GPU counts, or board names in the platform or in any comment. Hardware facts live only in a site's generated `hosts/<name>/hardware.nix`. The platform must evaluate and build for: no GPU, one NIC, no TPM, no second disk, and for a VM.
4. **Everything optional is off by default and switchable by option.** Encryption, TPM binding, Secure Boot, attestation, duress code, remote unlock, exit-node egress, Tailscale, monitoring, backups: each is one option with a plain-language description of what it does and what it costs. Turning any of them on later, or off, is a config change and an `apply`, never a reinstall (except full-disk encryption itself, which the installer must explain).
5. **Minimal.** Fewest flake inputs that do the job (target: nixpkgs, disko, lanzaboote, sops-nix, terranix; justify any addition in one sentence in `ARCHITECTURE.md`). No home-manager, no desktop, no shell full of tools. One concern per module. If two lines do the same thing, delete one. Prefer nixpkgs modules over hand-rolled code; prefer options over scripts; prefer scripts in the flake over README instructions.
6. **Extensible without forking.** Every module is a normal NixOS module a site can override. Every generated artifact (firewall rules, tofu config, dashboards, guest images) is derived from options a site sets. Hook points are named and documented (section 12).
7. **Isolated by default.** The host runs only what must run on the host: incusd, the firewall, optional tailscale, optional exporters, the UI, optional backup timer. Guests are unprivileged Incus instances; nesting, GPU, and extra devices are explicit per guest.
8. **Data separated by replaceability.** Re-downloadable artifacts are never backed up and always re-fetchable from a manifest. Irreplaceable state is backed up. They never share a directory.
9. **Reproducible.** `nix flake check` and every package build succeed from a clean checkout with the committed lockfile; no runtime fetching in builds; pinned image fingerprints and provider versions.
10. **Simple for someone who does not know Nix.** The graphical path (ISO, clicks) must get a person from bare metal to a running declared guest, or to a working desktop, without opening a terminal. The Nix path must be obvious to someone who does.
11. **Profiles are disjoint.** `nixie.profile = "server" | "desktop"`. The server closure contains no compositor, browser, or desktop package; the desktop closure contains no Incus, guest tooling, data manifest, or monitoring stack unless the site explicitly enables them. A check proves both directions with `nix why-depends`. The security stack (section 7) and the installer are shared and identical for both.

## 3. Architecture: platform flake, site flake

The platform flake exports:

```
nixosModules.nixie        # the platform module: declares the `nixie.*` option tree and implements it
lib.mkSite                # site.nix -> nixosConfigurations, tofu configs, guest images, checks
templates.site            # `nix flake init -t github:<org>/nixie#site`
packages.nixie-ui         # the control panel (section 10)
packages.nixie-setup      # the installer web app (section 11); shares tokens/components with nixie-ui
packages.nixie-cli        # `nixie apply|fetch|restore|reseal|export|doctor`, one binary or one writeShellApplication set
packages.nixie-iso        # bootable installer ISO that serves nixie-setup over the LAN
packages.deploy           # headless installer driving the same phases over SSH (nixos-anywhere)
checks.*                  # VM tests, lint, format
```

A site repo is small and looks like this after `nix flake init`:

```
flake.nix          # inputs: nixie (and nixpkgs via nixie); outputs = nixie.lib.mkSite ./site.nix
site.nix           # hosts.<name> = { hardware = ./hosts/<name>/hardware.nix; settings = { nixie.* ... }; guests = import ./guests.nix; data = import ./data.nix; }
guests.nix         # the guests attrset (section 5)
data.nix           # the data manifest (section 6)
guests/<name>/     # per-guest NixOS configuration.nix or cloud-init.yaml
hosts/<name>/hardware.nix   # GENERATED by the installer or deploy
secrets/ .sops.yaml         # sops-nix
```

`site.nix` is plain data; `mkSite` does all the wiring. A site may add arbitrary NixOS modules to a host (`settings` is a full NixOS module) and to any guest.

## 4. The `nixie.*` option tree

Design it in `ARCHITECTURE.md` first; the shape below is the contract. Every option has a `description` written for the installer UI (the UI renders option descriptions directly, so write them for a person, in sentence case, with consequences).

```
nixie.host.name, .timezone
nixie.auth.admin.name                       the primary user, created at install
nixie.auth.admin.passwordFile               password hash set during the wizard (sops-managed)
nixie.auth.sshKeys                          list; any key type; hardware keys suggested in the description, never required
nixie.auth.secondFactor = "none" | "totp" | "webauthn"    for the host UI and any web login; enrolled during install
nixie.auth.ssh.passwordLogin                default false; switchable on with a warning in the description
nixie.disks.system (by-id, from hardware.nix), .data (optional by-id), .layout = "single" | "system+data"
nixie.security.encryption.enable            LUKS2 root; passphrase every boot
nixie.security.tpm.enable                   outer LUKS layer bound to TPM2 with a required PIN
nixie.security.tpm.pcrs                     default [7]
nixie.security.secureBoot.enable            lanzaboote, keys in sops
nixie.security.attestation.enable           tpm2-totp code shown before the passphrase prompt
nixie.security.duress.enable                a second password that destroys all keyslots on both layers
nixie.security.remoteUnlock.enable          initrd SSH; key-based client auth (any key type)
nixie.security.lockdown                     kernel lockdown mode if compatible with configured modules
nixie.security.hardening.{ssh,usbguard,memoryEncryption,remoteJournal}.*
nixie.network.bridge = { uplinks = [MACs]; vlanAware; mode = "unmanaged-lan" | "managed-nat" }
nixie.network.egress = "direct" | "exit-node"; nixie.network.exitNode (tailnet name)
nixie.network.tailscale.enable / .serve
nixie.incus.*  (pools, images, ui listen = "tailnet" | "lan+tailnet", oidc, trust guidance)
nixie.data.root (default /data), .mediaBackup
nixie.backups.{enable, repo, schedule, excludes}
nixie.monitoring.{enable, prometheus, exporters.*, grafana.enable}
nixie.ui.{theme = "graphite"|"umber"|"paper", tokens (override file), links (extra nav entries), allowSiteEdits}
nixie.site.{repo, ref, path}   where the site checkout lives on the host (default /etc/nixie/site)
```

Defaults: encryption on when installed from the ISO (the installer asks), everything else in `security` off, `network.egress = "direct"`, monitoring off, backups off, UI listen `tailnet` when tailscale is on, otherwise `lan+tailnet`.

## 5. Guests: one attrset drives everything

Schema (document it as a NixOS option type so it is validated with clear errors):

```nix
web = {
  kind = "nixos";                       # nixos | image (foreign, cloud-init) | vm
  ip = "auto";                          # "auto" (DHCP) or a static address on the bridge
  profiles = [ ];                       # user-defined profile names; "killswitch" when egress is exit-node
  nesting = false; gpu = false;         # privilege is explicit and visible
  devices = { };                        # extra Incus devices, raw, for anything the schema lacks
  limits = { memory = null; cpu = null; };
  mounts = { "/data/state/web" = "/var/lib/web"; };   # host path -> guest path; shift=true
  backup = [ "/data/state/web" ];
  expose = { tailnet = [ ]; lan = [ ]; };             # tailscale serve / firewall openings
  module = ./guests/web/configuration.nix;            # nixos guests
  cloudInit = null; image = null;                     # foreign guests: pinned fingerprint + user-data
  extraConfig = { };                                  # raw Incus instance config passthrough
};
```

From this one file derive: the Incus instance (terranix), profiles and devices (nic with `host_name=veth-<name>`, disks with `shift=true`, gpu devices only when `gpu = true`), firewall rules, backup includes, scrape targets, dashboard instance lists, and the UI's declared list. Nothing else may list guest names.

Capabilities a site must be able to express, tested in `examples/`: a NixOS guest running a native service; a NixOS guest running an OCI image via podman with no daemon; a foreign image guest with cloud-init and pinned fingerprint; a guest with all host GPUs (NVIDIA via the `gpu` device and the nvidia container toolkit on the host when `hardware.nvidia` is on, verified against the pinned nixpkgs, with the known caveats documented); a nested guest running a container runtime; a VM; static IP on an unmanaged bridge; mounts from the data root; per-guest backup; tailnet exposure.

NixOS guests are built from the site flake with nixpkgs' `virtualisation/lxc-container.nix` (`system.build.tarball` + `system.build.metadata`), imported by hash, and updated in place by `nixie apply` (`nixos-rebuild` inside the guest) when possible, `incus rebuild` otherwise.

Two tiers, made obvious everywhere: **declared** (in `guests.nix`; survives reinstall; has firewall chain, mounts, backups, monitoring) and **scratch** (created from the UI or `incus launch`; real, not in git; never touched by `apply`; still gets the default egress policy). The UI labels each instance and offers **Export to guests.nix** (emits the schema entry for the instance's current state) and, when `nixie.ui.allowSiteEdits` is on and the site checkout is on the host, **Declare** (commits that entry to the site repo and runs `apply`).

## 6. Data directory and manifest

```
<root>/state/<name>   irreplaceable; restic-backed up when backups are on
<root>/cache/<kind>   re-fetchable; never backed up; populated by `nixie fetch`
<root>/media          library; backup per nixie.data.mediaBackup
```

`data.nix` declares everything in `cache/`. Ship fetchers as small, independently enabled kinds with a common interface (`kinds/<name>.nix`: a derivation-free script with `manifest -> idempotent fetch`), and implement at least: `hf` (Hugging Face repos pinned to a revision, `.complete` markers), `oci` (images into the local registry mirror), `incus-images` (by fingerprint), `http` (URL + sha256), plus a documented way for a site to add a kind without patching the platform. `nixie fetch` runs on demand and on an optional timer; deleting `cache/` and running it must reproduce it wherever the source allows.

Backups: `services.restic.backups` over `state/` plus each guest's `backup` paths, excluding `cache/`; `nixie restore -- <snapshot>` as the counterpart. Incus's own database is never backed up; `apply` regenerates it.

## 7. Security features (each optional, each independently testable)

- **Encryption**: disko layout with ESP + LUKS2 root (+ data device or dataset per `nixie.disks`). ZFS when a data disk exists, otherwise a dataset on root.
- **TPM binding**: a second, outer LUKS layer bound to TPM2 with a **required PIN** (`systemd-cryptenroll --tpm2-with-pin=yes`), PCR policy from `nixie.security.tpm.pcrs`. Passphrase and PIN on every boot; no auto-unlock path exists.
- **Secure Boot**: lanzaboote; keys in sops; enrollment is a setup phase with a Setup Mode checklist.
- **Attestation**: `tpm2-totp` sealed to PCRs 4,7,8,9, code shown before the passphrase prompt; `nixie reseal` after kernel updates; the setup phase shows the QR.
- **Duress**: a second password whose entry wipes all keyslots on both layers. Implement in `boot.initrd.systemd`; document the exact behavior; test in a VM.
- **Remote unlock**: `boot.initrd.network.ssh`, prompts relayed in crypttab order, SSH key client auth (any key type from `nixie.auth.sshKeys`).
- Always on with encryption: `panic=10`, TPM lockout auth set to a sops-stored random value, LUKS header backups for both layers GPG-encrypted to a sops key, written by setup to a user-chosen location off the system disk.
- **Lockdown**: integrity mode when compatible with the configured out-of-tree modules; otherwise the option exists, defaults off, and the incompatibility is documented.
- **Running-host hardening** (each its own option, sensible defaults on): SSH key-based by default with any key type (hardware keys suggested, never required), password login off by default and switchable on via `nixie.auth.ssh.passwordLogin` with a warning; host nftables default-drop inbound, guests cannot reach host SSH or the UI port; USBGuard with a setup-time allowlist; TSME/IOMMU kernel params; remote journald; systemd hardening on every unit the platform authors, with `systemd-analyze security` at "OK" or a comment naming the required exposure.

## 8. Networking

Bridge with the uplinks from `hardware.nix`, interface names derived from MACs via `systemd.network.links`, never hard-coded. Modes: unmanaged LAN bridge (guests get LAN addresses) or managed NAT bridge. Egress policy per site: `direct`, or `exit-node` where every guest's traffic is forced through a named Tailscale exit node by a host nftables chain keyed on `veth-<name>`, plus a catch-all chain for any undeclared `veth-*`, allowing only the exit-node path (udp 41641, udp 3478, tcp 443 to the coordination server, DHCP) and LAN as configured. A NixOS VM test proves both a declared and an undeclared guest cannot reach the internet directly under `exit-node`.

## 9. Monitoring and backups (optional)

Prometheus with node exporter, Incus `/1.0/metrics` scrape, NVIDIA exporter when a GPU is configured; Grafana behind `nixie.monitoring.grafana.enable`. The UI's long-history adapter points at Prometheus by default. Default dashboards ship as JSON: host, per-guest, and GPU (per detected card; power cap reference line from an option, no vendor-specific numbers in the platform).

## 10. The control panel (`packages.nixie-ui`)

Implement `design/Nixie_Front_Panel.html` faithfully. Extract its tokens (brand blues, surfaces, the semantic `--cpu/--mem/--net/--disk/--hot/--err/--ok` families, Graphite/Umber/Paper finishes, Archivo + JetBrains Mono bundled, the 40/22/15/13 type scale, radius on raised panels only, inset chart wells, instances as lanes with a CPU heat strip, bridge topology, ring gauges, the mark and wordmark) once as design tokens; every component, and the installer, consumes them. Theming: the three finishes plus a token-override file from `nixie.ui.tokens`; a site can add nav links and dashboards without rebuilding.

Scope: everything the stock Incus UI does (instances with create/start/stop/restart/freeze/delete/bulk, detail tabs Configuration, Devices, Snapshots, Terminal over the exec websocket, Logs, Files, Metrics; images with pull; profiles; networks with state and topology; storage with volumes; operations with cancel; settings; trust-store guidance when the daemon reports `untrusted`; OIDC login when configured), dashboards (in-browser rolling history from `/1.0/metrics`, Prometheus `query_range` adapter, panel types time series/gauge/stat/bar gauge/table/heatmap/log tail, synced cursors, time-range picker, JSON dashboards editable and importable), declared/scratch labels, Export to guests.nix, Declare when allowed, command palette, keyboard-complete, demo mode with generic seeded data when no daemon is reachable.

Technical: static bundle, TypeScript, React/Solid/Svelte your choice, uPlot or ECharts, xterm.js, everything vendored, no runtime CDN or font requests, `buildNpmPackage` with a committed lockfile. Served by incusd via `INCUS_UI`; listen policy and auth from `nixie.incus.*`.

## 11. The installer: graphical over the LAN, headless over SSH, one phase engine

**Phase engine** (`packages.nixie-cli` / `packages.deploy`): idempotent phases with markers under `/var/lib/nixie/setup/` on the target so any front end resumes after any reboot: (1) hardware discovery → `hardware.nix`; (2) host key + sops wiring; (3) partition, format, install (disko + nixos-install; lanzaboote signs before first boot when Secure Boot is chosen); (4) first boot, unlock; (5) Secure Boot enrollment with Setup Mode checklist; (6) TPM enrollment with PIN, attestation init with QR, lockout auth, header backups; (7) verification reboot; (8) `apply`: site checkout, guest images, tofu, fetch, optional restore. Phases 5–7 exist only when the corresponding options are on.

**Graphical, on the machine itself** (the default the ISO boots into): the ISO starts a kiosk session, a minimal Wayland compositor (`cage`) running a browser in kiosk mode against the local `nixie-setup` backend, so a person with one PC gets the full wizard on that PC's screen with keyboard and mouse. tty2 has the terminal wizard as a fallback, and the LAN path below runs in parallel, so a phone browser works too. After the first reboot, the installed system's **setup generation** finishes the job: the installer writes a NixOS specialisation containing the same kiosk stack and the continuation service, the machine boots into it, the wizard continues on screen through phases 4–8, and on **Finish** it switches to the normal generation and deletes the setup one, so no compositor or browser remains in a server system (a check proves the final server closure has none). The desktop profile simply continues inside its own session.

**Graphical, over the LAN** (same ISO, same `packages.nixie-setup`): the ISO also generates a self-signed certificate and prints on the console the URL (`https://<ip>:9443`), a six-digit pairing code, and the certificate fingerprint, plus a QR of the URL. From any browser on the LAN: pair (code + fingerprint confirmation), then a short wizard in the Nixie design system: **Profile** (server or desktop, with a one-paragraph description of each); **Hardware** (pick the system disk and optional data disk from a list with sizes and models, pick uplinks by MAC, see detected GPUs and TPM); **Site** (start a new site on this host, or clone a git URL, or upload a tarball); **Security** (each section-7 feature as a toggle with its description and consequences; secrets entered here: passphrase, PIN, duress password, all held in the backend process only); **Authentication** (admin username and password; SSH public keys pasted or uploaded, optional; second factor for web logins chosen from none / authenticator app / passkey or hardware key, and enrolled right there: the TOTP QR is shown in the wizard, WebAuthn registration runs in the wizard's own browser; nothing here requires owning a hardware key); **Network** (hostname, bridge mode, address, optional Tailscale auth key, egress mode; on desktop: NetworkManager and hostname only); **Desktop** (desktop profile only: user account, package categories with curated defaults and a search box over nixpkgs, theme finish, wallpaper, keyboard layout, monitors); **Review** (shows the generated `hardware.nix` and the `settings` it will write; the same files a Nix user would write by hand); **Install** (streamed progress). After the reboot the installed host runs a one-shot `nixie-setup` continuation service on the same URL with the same certificate (copied during install) so the browser session simply continues through phases 4–8, including the Setup Mode checklist, the PIN enrollment, the TOTP QR, and a header-backup download. On **Finish** the continuation service disables itself and removes its listener; from then on the only web surface is the control panel. Every wizard step corresponds to an option or a phase; the wizard never does anything the CLI cannot.

Secrets over the LAN are acceptable only over the paired TLS session; the backend binds the setup port only while setup is incomplete; pairing codes are single-use.

**Headless** (`nix run nixie#deploy -- --site <path> --host <name> <target>`): a terminal wizard (`gum`) over the same phases, driving the target over SSH with nixos-anywhere. It detects whether the target is an existing Linux (kexec into the installer) or already the Nixie ISO (skip kexec). Prints the bare-metal prerequisites it cannot perform and asks for confirmation: UEFI with CSM off, TPM enabled and cleared in firmware, Secure Boot off with keys cleared (Setup Mode; also required for kexec under lockdown), undeclared disks unplugged.

**`nixie apply`, the everyday command**, on the host against the site checkout (and `nix run .#apply` from a site repo as a thin wrapper that syncs and runs it): (1) `nixos-rebuild switch` on the host so every derived piece exists before a guest has an interface; (2) build changed guest images and import by hash; (3) `tofu apply` from terranix; in-place switch for changed NixOS guests. Safe to re-run with no changes; prints a plan before mutating unless `--yes`. Removing a guest destroys the instance, never its `state/` or backups. `nixie doctor` checks trust, certificates, PCR drift, pending reseal, and disk space, and the UI surfaces its results.

## 12. Profiles

Both profiles are NixOS modules under `profiles/`; `nixie.profile` selects one; a site may enable pieces of the other explicitly (`nixie.incus.enable` on a desktop, for someone who wants both), but nothing crosses over by default.

### 12.1 Server profile

Everything in sections 5–11. Plus an optional **host UI** for people who want to reach the host itself from a browser, `nixie.hostUi.enable`, default off:

- Scope: host filesystem browser with upload/download/edit, root terminal, journal viewer, service list with start/stop, storage and disk health, users, `nixie apply` / `fetch` / `doctor` with streamed output, reboot/power. Everything Incus's API cannot reach, which is why it is a separate service.
- Implementation: Cockpit (`services.cockpit` with the files, terminal, storage, and podman plugins) branded with the Nixie tokens and linked from the Nixie nav as **Host**. Building a native host agent is a later milestone; do not build one now. Note in `docs/` that it is the one component whose look will not fully match the design file.
- Auth: the admin password via PAM plus the second factor chosen at install (`nixie.auth.secondFactor`): none, TOTP from an authenticator app, or WebAuthn with a hardware key or a platform/software passkey. Never require a hardware key. Binding to the tailnet only by default, LAN by option, never reachable from guests; session and action audit to the journal. The option description must say plainly that this widens the attack surface of a hardened host and that it is off for that reason.

### 12.2 Desktop profile

A complete, opinionated Hyprland desktop, installed and usable without touching a config file, and fully declared in the site. The benchmark is Omarchy; the bar is a more modern look, better motion, more built-in capability, and everything declarative.

- **Session**: Hyprland from nixpkgs, greetd with a greeter styled from the Nixie tokens, PipeWire, NetworkManager, Bluetooth, xdg portals, fonts, cursors, Flatpak optional.
- **Shell**: one coherent shell layer (Quickshell or AGS, pick one and justify): top bar with workspaces, window title, tray, clock, system indicators; launcher with app, file, calculator, emoji, and clipboard modes; notification center; OSDs for volume, brightness, caps lock; power menu; lock screen with blur; idle handling; keybind cheat-sheet overlay; window switcher; screenshot with annotation and screen recording; color picker; night light; per-monitor configuration. No grab bag of unrelated tools: one visual language, one keybinding scheme, documented on one page.
- **Motion**: curated bezier curves; workspace transitions, window open/close/move, layer fade, blur with layered translucency, rounding and shadows tuned per finish; an overview mode (hyprexpo-style) if the plugin is stable on the pinned nixpkgs; performance mode that drops blur and animations when a fullscreen or gaming window is focused. Respect `prefers-reduced-motion` equivalents where the toolkit offers them.
- **Theme**: the same three finishes as the web UI (Graphite, Umber, Paper) applied consistently across Hyprland, the shell, GTK, Qt, terminal, editor themes, and browser accents, generated from one token source; optional wallpaper-derived accent. Wallpaper transitions. Changing finish is one option and an `apply`.
- **Packages**: categories in the installer (browsers, terminals and shells, editors and dev tools, media, office, communication, gaming, creative), each with a curated default set and a free-text search over nixpkgs; the selection is written into the site as a list, never into a mutable package database. Flatpak stays optional and off by default.
- **Easy config**: `nixie.desktop.*` options for finish, wallpaper, keybinds, monitors, autostart, default apps, packages; a `~/.config/nixie/local.conf` (and Hyprland `local.conf`) sourced last for per-user tweaks that do not need a rebuild; a `nixie menu` launcher entry (finishes, wallpapers, packages, update, keybinds, system info) that edits the site config and runs `nixie apply`, with a clear diff before applying.
- **Laptop and power**: profiles, lid and idle behavior, battery indicators, TLP or power-profiles-daemon by option.
- **Home-manager**: allowed only inside the desktop profile if the environment cannot be declared cleanly without it; it must not appear in the server closure. Prefer NixOS-level configuration with generated XDG config files where that is clean.
- **Security**: identical options to the server (encryption on by default, TPM/PIN, Secure Boot, attestation, duress, remote unlock, hardening), so a laptop gets the same boot chain.

## 13. Extension points (document each in `docs/extending.md` with an example)

- Add a host module: `settings` in `site.nix` is a full NixOS module.
- Add a guest: one attrset entry plus a directory; `extraConfig`/`devices` for anything the schema lacks.
- Add a data kind: a fetcher file with the common interface, referenced from `data.nix`.
- Add a firewall rule, a scrape target, a dashboard, a UI nav link: each an option, never an edit to the platform.
- Replace the UI: `nixie.incus.ui.package`.
- Add an installer wizard step for a site-specific option: options carry `nixie.ui.section` metadata; the wizard renders any option that declares it.
- Recipes: an optional `recipes/` mechanism where a guest may be `{ recipe = "<name>"; }` resolving to a platform- or site-provided module; the platform ships two generic ones (`static-web`, `oci-service`) and no more.

## 14. Documentation and examples

`README.md` (what it is, the ISO-and-browser path in five lines, the Nix path in five lines), `docs/` (concepts: platform vs site, hosts, guests, data, security choices and what each costs; guides: install graphically, install headlessly, add a guest, add a data kind, enable a security feature later, restore; reference: the `nixie.*` tree generated from option descriptions), `examples/site/` (server) and `examples/desktop-site/` used by tests and screenshots, `CHANGELOG.md`. Screenshots of every screen in all three finishes, generated from demo mode in CI.

## 15. Process and quality bar

1. Read this brief and the design file. Ask at most five questions. Write `ARCHITECTURE.md` first (including the profile split and the desktop shell choice): layout, the full `nixie.*` option tree with descriptions, the site contract, the guest and data schemas, input justifications, the phase engine diagram, the installer state machine across reboots, and every intended deviation from this brief with a reason. Stop for review.
2. Implement in slices, each a commit with `nix flake check` green: (a) flake skeleton, option tree, `mkSite`, site template, a bootable minimal host; (b) encryption/TPM/Secure Boot/attestation/duress/remote unlock, each behind its option, with the swtpm + OVMF VM test; (c) network, egress modes, firewall with VM test; (d) Incus, guest schema, terranix, image build, `nixie apply`; (e) examples for every capability in section 5; (f) data kinds, `fetch`, backups, `restore`; (g) monitoring; (h) control panel; (i) installer: phase engine, ISO with kiosk session, LAN wizard, setup generation and continuation, headless wizard; (j) desktop profile: session, shell, motion, theme, packages, `nixie menu`; (k) host UI option; (l) docs, screenshots, final ARCHITECTURE pass.
3. Verify every NixOS option against the pinned nixpkgs (`nix eval`, `nixos-option`, module source); never from memory; never invent options.
3a. **Run everything you claim works, in a VM, yourself.** Writing a test is not verifying; a slice is done only when its tests have executed in this environment and the evidence is committed. Tooling, in order of speed:
   - `nixos-rebuild build-vm` / `nix run .#nixosConfigurations.<host>.config.system.build.vm` for quick iteration on a host config.
   - The NixOS test framework for every check in `checks.*`: `nix build .#checks.x86_64-linux.<name> -L`; use the interactive driver (`nix build .#checks...driverInteractive` then `./result/bin/nixos-test-driver`) to debug, and `machine.screenshot()` / `machine.get_screen_text()` to capture evidence. Multi-machine tests cover: guest egress under both policies; a NixOS guest image booting inside Incus on the host VM; the LAN installer driven from a second VM's browser; encryption boot with OVMF + swtpm (`virtualisation.useEFIBoot`, `virtualisation.tpm.enable`).
   - `packages.test-iso`: a script that boots the built ISO in QEMU with OVMF (Secure Boot capable firmware, in Setup Mode), swtpm, a blank virtual disk, and a user-mode network with the setup port forwarded, then drives the wizard end to end (via the setup backend's HTTP API, and via the kiosk with a browser automation tool for at least one full run), through every reboot, and asserts the final state over SSH. Screenshots and serial logs land in `tests/artifacts/`.
   - `nix flake check -L` as the gate before every commit.
   Detect KVM (`/dev/kvm`); if it is missing, run under TCG anyway, mark the run as slow in the log, and say so in the slice summary. Never mark an acceptance criterion as met on the strength of "it should work". If a VM test cannot be made to run in this environment, stop and report exactly why with the command and its output.
3b. Each slice's commit includes `VERIFICATION.md` (or a section in the PR description): what was run, the commands, pass/fail per test, links to the artifacts, and any criterion that could not be verified and why.
4. `nix fmt` with `nixfmt-rfc-style`, `statix`, `deadnix`, all in `checks`.
5. No secrets in the store; a check greps the closure for key-like material.
6. Comments explain why, never what, and never mention specific hardware or any user.
7. Every module and option has a description a non-Nix user can act on; the installer renders them, so they are user-facing copy.

## 16. Acceptance criteria

- Clean clone: `nix flake check` passes with every VM test actually executed (not skipped) in the final run; every package builds; the example site builds offline after `nix flake archive`. The final `VERIFICATION.md` lists every criterion below with the command that proved it.
- The platform evaluates with sites for: no GPU, one NIC, no TPM, no data disk, and a VM; proven by throwaway sites in `tests/`.
- Graphical path, single machine: from the ISO in a VM with OVMF + swtpm and no other device, using only the on-screen kiosk, a person can install the server profile with all security features on, finish the continuation phases in the setup generation, and declare a running guest from the UI; the final server closure contains no compositor or browser. The same with all security features off takes fewer steps and no reboot pauses.
- Graphical path, LAN: the same install completed from a browser on another VM.
- Desktop: from the ISO, a person can install the desktop profile and land in a working Hyprland session with the chosen finish, packages, and user, with encryption on; the desktop closure contains no Incus, tofu, or monitoring unless enabled. Switching finish through `nixie menu` takes effect after `apply` without a reboot.
- Headless path: `nix run nixie#deploy` reaches the same end state with the same phase markers, from both an existing Linux (kexec) and the ISO.
- Toggling any security feature on or off in `site.nix` and running `apply` takes effect without reinstalling, except encryption, which the CLI refuses with a clear message.
- Deleting `cache/` and running `fetch` restores it; deleting a guest and running `apply` recreates it; `restore` brings back `state/`.
- An undeclared instance cannot reach the internet except through the exit node under `exit-node` egress, is left alone by `apply`, and round-trips through Export/Declare into a declared guest with zero tofu diff.
- `grep -rn` for MACs, `/dev/disk`, interface names, PCI addresses, or board names finds hits only under `tests/` and the generated `hardware.nix` of the example site.
- Every platform-authored unit passes `systemd-analyze security` at "OK" or better, or documents its exposure.
- The control panel and the installer match the design file side by side in all three finishes.

If any requirement conflicts with another or with what nixpkgs can do, raise it in step 1 with a proposed resolution rather than quietly picking one.
