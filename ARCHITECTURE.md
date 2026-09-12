# Nixie architecture

This document is the design the platform is built from. The brief in
`docs/NIXIE_PLATFORM_BRIEF.md` is the requirement; this file says how each
requirement is met, which parts of nixpkgs do the work, and where the platform
deviates from the brief and why. Section 14 lists the five questions the
process allows together with the default taken for each, because the work ran
unattended.

## 0. Verification environment

The build host has no system Nix. Nix 2.20 runs rootless through nix-portable
(bubblewrap + user namespaces) with the store under the user's home. KVM is
available and a NixOS test with `virtualisation.useEFIBoot` and
`virtualisation.tpm.enable` ran end to end in about two minutes, so every VM
test in this repo executes under KVM, not TCG. The pinned nixpkgs is
`nixos-26.05`. Every package and option named below was checked against that
pin with `nix eval` before it was written down.

## 1. Repository layout

```
flake.nix                 inputs, outputs; nothing else
lib/
  default.nix             re-exports mkSite and the guest/data helpers
  mk-site.nix             site.nix -> nixosConfigurations, packages, checks
  guests.nix              pure functions: guest attrset -> tofu, nft, backup, scrape lists
  tokens.nix              design tokens as Nix data (single source, see section 10)
modules/                  the `nixie.*` option tree; one concern per file
  default.nix             imports everything below; nothing else
  profile.nix             nixie.profile, disjointness assertions
  host.nix                nixie.host.*
  auth.nix                nixie.auth.*
  disks.nix               nixie.disks.* and the disko layout
  security/
    encryption.nix        LUKS2 root, panic=10, header backups
    tpm.nix               outer LUKS layer, PIN, lockout auth
    secure-boot.nix       lanzaboote wiring
    attestation.nix       tpm2-totp in initrd
    duress.nix            duress password handling in initrd
    remote-unlock.nix     initrd SSH
    lockdown.nix          kernel lockdown parameter
    hardening.nix         ssh, usbguard, memory encryption, remote journal, sysctl
  network/
    bridge.nix            uplinks -> systemd-networkd bridge
    egress.nix            direct / exit-node nftables chains
    firewall.nix          host default-drop, guest isolation
    tailscale.nix
  incus.nix               incusd, UI serving, listen policy, preseed
  guests.nix              the guest schema type and everything derived from it
  data.nix                data root, manifest type, fetch timer
  backups.nix             restic over state/ + guest backup paths
  monitoring.nix          prometheus, exporters, grafana, dashboards
  ui.nix                  nixie.ui.* (theme, tokens, links, allowSiteEdits)
  site.nix                nixie.site.* (checkout location)
  host-ui.nix             nixie.hostUi.* (Cockpit)
  setup.nix               nixie.setup.pending, the setup generation specialisation
  desktop/                nixie.desktop.* (session, shell, theme, packages, power)
profiles/
  server.nix              imports the server-only modules
  desktop.nix             imports the desktop-only modules
installer/
  phases/NN-<name>.sh     the eight idempotent phases, plain bash
  lib.sh                  marker handling, logging, shared helpers
  iso.nix                 the ISO module: kiosk, tty2 wizard, LAN backend
  kiosk.nix               cage + browser, shared by the ISO and the setup generation
packages/
  nixie-cli.nix           writeShellApplication set: apply fetch restore reseal export doctor
  nixie-setup/            installer backend (Python stdlib) + static wizard bundle
  deploy.nix              headless front end: gum + nixos-anywhere
  test-iso.nix            boots the ISO under QEMU/OVMF/swtpm and drives the wizard
ui/                       one npm workspace: tokens, components, nixie-ui, nixie-setup
data-kinds/               hf.nix oci.nix incus-images.nix http.nix
recipes/                  static-web.nix oci-service.nix
templates/site/           `nix flake init -t`
examples/site/            server example used by tests and screenshots
examples/desktop-site/    desktop example
tests/                    NixOS tests, throwaway sites (no-gpu, one-nic, no-tpm, no-data-disk, vm)
docs/                     concepts, guides, reference (generated option docs), design-tokens.md
```

The platform contains no hardware or user facts. A grep check in `checks`
fails on MAC addresses, device-node disk paths, PCI addresses, interface names, or board
names outside `tests/` and `examples/*/hosts/*/hardware.nix`.

## 2. Flake inputs

| input | why |
|---|---|
| nixpkgs (`nixos-26.05`) | everything |
| disko | declarative partitioning; the only maintained way to express nested LUKS + ZFS as data |
| lanzaboote | Secure Boot signing of the boot chain; nothing in nixpkgs does it |
| sops-nix | secrets in git for a site, decrypted at activation; the brief names it |
| terranix | guest attrset -> OpenTofu JSON without hand-writing HCL |

No other inputs. `nixos-anywhere` (1.13.0) is used as a nixpkgs package, not a
flake input. There is no home-manager, no flake-parts, no Hyprland flake;
Hyprland 0.55.4 from the pin is used.

## 3. Flake outputs

```
nixosModules.nixie          modules/default.nix
lib.mkSite                  lib/mk-site.nix
templates.site
packages.x86_64-linux.{nixie-ui,nixie-setup,nixie-cli,nixie-iso,deploy,test-iso}
checks.x86_64-linux.*       see section 12
formatter.x86_64-linux      nixfmt (rfc style)
```

## 4. The `nixie.*` option tree

Every description below is user-facing copy: the wizard renders it. Options
carrying `nixie.ui.section` metadata become wizard steps in the order listed.
Defaults are shown after the type.

### 4.1 profile and host

```
nixie.profile            enum "server" | "desktop"                       (required)
  Which kind of machine this is. A server runs services as isolated Incus
  guests and has no desktop software at all. A desktop is a full Hyprland
  workstation and has no Incus, monitoring or backup stack unless you turn
  them on. The choice is made at install and can be changed only by reinstall.

nixie.host.name          str                                             (required)
  The machine's hostname on the network and in the site repo.
nixie.host.timezone      str, default "UTC"
  Time zone for logs, timers and the clock.
nixie.host.keepGenerations  int, default 10                       (change request)
  How many earlier versions of this machine's system stay bootable. Each
  `apply` makes a new one; the boot menu, `nixie rollback --list` and the
  History page show them with the site commit, date and kernel. Older ones
  are removed by the weekly clean-up, and with Secure Boot on only these stay
  signed.
nixie.host.siteRevision  nullOr str, default null                 (change request)
  Internal: the site repository commit this system was built from, passed by
  the site flake; it becomes the generation's label.
```

### 4.2 auth

```
nixie.auth.admin.name           str                                     (required)
  The one administrator account created at install. It can use sudo, log in
  over SSH and open the web surfaces.
nixie.auth.admin.passwordFile   path (sops secret)                      (required)
  A file holding the password hash for the administrator. The installer writes
  it into the site's sops secrets.
nixie.auth.sshKeys              listOf str, default [ ]
  SSH public keys allowed to log in as the administrator. Any key type works.
  A hardware-backed key is a good choice but is not required. With no keys and
  password login off, SSH is unreachable, which is fine for a desktop.
nixie.auth.secondFactor         enum "none" | "totp", default "none"
  Extra step for web logins to the host UI. "totp" asks for a six-digit code
  from an authenticator app; you enrol it during setup. See deviation D3 for
  why passkeys are not offered here.
nixie.auth.totpSecretFile       path (sops secret), default null
  Internal: the enrolled TOTP secret when secondFactor = "totp".
nixie.auth.ssh.passwordLogin    bool, default false
  Allow SSH login with the password instead of a key. Turning this on lets
  anyone who can reach port 22 guess passwords; leave it off unless you have
  no way to use a key.
```

### 4.3 disks

```
nixie.disks.system       str (by-id path, from hardware.nix)             (required)
  The disk the operating system is installed on. It is wiped at install.
nixie.disks.data         nullOr str (by-id path), default null
  An optional second disk that holds the data root as its own ZFS pool.
  Without it the data root is a dataset on the system disk.
nixie.disks.layout       enum "single" | "system+data", default from .data
  Derived: "system+data" when a data disk is set.
```

### 4.4 security

```
nixie.security.encryption.enable      bool, default false (the ISO pre-selects true)
  Encrypt the whole system with LUKS2 so a stolen disk is unreadable. You type
  a passphrase every boot. This is the only setting that needs a reinstall to
  change; `nixie apply` refuses to flip it.
nixie.security.tpm.enable             bool, default false
  Add a second encryption layer tied to this machine's TPM chip plus a PIN.
  The disk then only opens in this machine, with the PIN and the passphrase.
  Needs a TPM 2.0. A firmware update or a changed boot chain can require a
  `nixie reseal`.
nixie.security.tpm.pcrs               listOf int, default [ 7 ]
  Which boot measurements the TPM layer is tied to. 7 tracks Secure Boot
  state. Adding more makes unlocking stricter and re-enrolment more frequent.
nixie.security.secureBoot.enable      bool, default false
  Sign the boot chain with your own keys so firmware refuses unsigned kernels.
  Setup walks you through putting the firmware into Setup Mode. Keys live in
  the site's sops secrets.
nixie.security.attestation.enable     bool, default false
  Before asking for the passphrase, show a six-digit code computed by the TPM
  from the boot measurements. Compare it to your authenticator app: a wrong
  code means the boot chain was tampered with. Needs a TPM; run `nixie reseal`
  after kernel updates.
nixie.security.duress.enable          bool, default false
  A second "duress" passphrase. Entering it at the unlock prompt destroys every
  key slot on both encryption layers, making the data permanently unreadable,
  then powers off. There is no undo.
nixie.security.remoteUnlock.enable    bool, default false
  Let you type the boot passphrase over SSH from another machine, using the
  keys in nixie.auth.sshKeys. Needed for servers without a keyboard.
nixie.security.remoteUnlock.port      port, default 2222
  Port the early-boot SSH server listens on.
nixie.security.lockdown               enum "none" | "integrity", default "none"
  Kernel lockdown. "integrity" stops root from changing the running kernel.
  It also refuses unsigned kernel modules; see deviation D4 before enabling.
nixie.security.hardening.ssh.enable             bool, default true
  Key-only SSH with modern ciphers, no root login, no X11 forwarding.
nixie.security.hardening.usbguard.enable        bool, default false (server true)
  Only USB devices present at setup are allowed; new ones are blocked until
  added to the allowlist.
nixie.security.hardening.usbguard.rules         lines, default ""
  The allowlist, generated by setup. Add lines to allow more devices.
nixie.security.hardening.usbguard.allow         listOf str, default [ ]   (change request)
  Devices to allow on top of the rules, as "vendor:product" or
  "vendor:product/serial". `nixie usb allow <device>` appends here in the
  site; a keyboard on the console is never blocked while setup or
  `nixie security reenroll` runs.
nixie.security.recoveryKey                      (no option)               (change request)
  With the TPM layer on, a recovery key is always enrolled on the outer
  layer at install, shown once as text and a QR, and never stored on this
  machine; the prompt accepts it whenever the TPM cannot unseal. It is not
  optional: without it a board, TPM or firmware failure loses the data.
  `nixie backup kit` enrols a fresh one and writes it into the kit.
nixie.security.hardening.memoryEncryption.enable  bool, default false
  Ask the CPU to encrypt RAM (AMD TSME) and enable the IOMMU so devices cannot
  read memory they were not given.
nixie.security.hardening.remoteJournal.enable   bool, default false
nixie.security.hardening.remoteJournal.url      str
  Send a copy of the system log to another machine so an intruder cannot erase
  it here.
```

### 4.5 network

```
nixie.network.bridge.uplinks    listOf str (MACs, from hardware.nix), default [ ]
  Which physical ports join the guest bridge. Chosen by hardware address so
  cable and slot changes do not matter.
nixie.network.bridge.vlanAware  bool, default false
  Let guests use VLAN tags on the bridge.
nixie.network.bridge.mode       enum "unmanaged-lan" | "managed-nat", default "unmanaged-lan"
  "unmanaged-lan": guests appear on your LAN like any other computer and get
  addresses from your router. "managed-nat": guests live on a private network
  behind this host and share its address.
nixie.network.bridge.natSubnet  str, default "10.90.0.0/24"
  Private network used only in managed-nat mode.
nixie.network.egress            enum "direct" | "exit-node", default "direct"
  "direct": guests reach the internet through your LAN. "exit-node": every
  guest, declared or not, is forced through the Tailscale exit node below and
  cannot reach the internet any other way.
nixie.network.exitNode          str, default ""
  The tailnet name of the exit node used when egress = "exit-node".
nixie.network.tailscale.enable  bool, default false
  Join a Tailscale network so you can reach this host and its web pages from
  anywhere without opening ports.
nixie.network.tailscale.authKeyFile   nullOr path (sops), default null
nixie.network.tailscale.serve   attrsOf str, default { }
  Extra tailscale serve entries (path -> target) beyond what guests declare.
nixie.network.address           nullOr str (CIDR), default null
  Static address for the host on the bridge. Empty means DHCP.
nixie.network.gateway / .dns    nullOr str / listOf str
```

### 4.6 incus, guests, data, backups, monitoring

```
nixie.incus.enable              bool, default (profile == "server")
  Run the Incus daemon that hosts guests.
nixie.incus.ui.listen           enum "tailnet" | "lan+tailnet", default "tailnet" if tailscale else "lan+tailnet"
  Where the control panel is reachable. "tailnet" is safest.
nixie.incus.ui.port             port, default 8443
nixie.incus.ui.package          package, default packages.nixie-ui
  Replace the control panel with another web bundle.
nixie.incus.oidc                submodule { issuer; clientId; audience; }, default null
  Log in to the control panel with an identity provider instead of a
  certificate.
nixie.incus.pools               attrsOf { driver = "zfs"|"dir"; source; }, default { default on data root }
nixie.incus.images.remotes      attrsOf str, default { images = "https://images.linuxcontainers.org"; }

nixie.guests                    attrsOf guest (section 6), default { }
  The declared guests. This is the only place guest names appear.

nixie.data.root                 path, default "/data"
  Where state/, cache/ and media live. state/ is backed up; cache/ is never
  backed up because `nixie fetch` can rebuild it.
nixie.data.mediaBackup          bool, default false
  Include media/ in backups. It can be large.
nixie.data.manifest             data manifest (section 7), default { }
nixie.data.fetch.timer          nullOr str (calendar spec), default null
  Run `nixie fetch` on a schedule as well as on demand.
nixie.data.kinds                attrsOf path, default { }
  Extra fetcher kinds provided by the site.

nixie.backups.enable            bool, default false
  Back up state/ and every guest's backup paths with restic on a schedule.
nixie.backups.repository        str
nixie.backups.passwordFile      path (sops)
nixie.backups.environmentFile   nullOr path (sops), default null
nixie.backups.schedule          str, default "daily"
nixie.backups.excludes          listOf str, default [ ]
nixie.backups.keep              { daily = 7; weekly = 4; monthly = 6; }
nixie.backups.snapshots         { hourly = 24; daily = 7; weekly = 4; }   (change request)
  Local ZFS snapshots of state/ and every guest's backup paths, on that
  schedule and before every `apply`; the last five pre-apply snapshots of a
  guest's root disk are kept as Incus snapshots. These are what `nixie
  rollback data|guest` restore from; they are on the same disk, so they are
  not a backup against disk loss.
nixie.backups.rcloneConfigFile  nullOr path (sops), default null           (change request)
  An rclone configuration for "rclone:" repositories (S3, B2 and friends).
  `nixie.backups.repository` also takes a local path or "sftp:".
nixie.backups.check             nullOr str (calendar spec), default "weekly" (change request)
  Run `restic check` on that schedule; `nixie doctor` reports the last result.

nixie.monitoring.enable         bool, default false
  Collect host, guest and GPU metrics with Prometheus for the dashboards.
nixie.monitoring.retention      str, default "30d"
nixie.monitoring.grafana.enable bool, default false
nixie.monitoring.grafana.port   port, default 3000
nixie.monitoring.gpuPowerCap    nullOr int (watts), default null
  Reference line on the GPU dashboard. Set to your card's limit.
nixie.monitoring.extraScrapeConfigs  list, default [ ]
nixie.monitoring.dashboards     attrsOf path, default { }   extra JSON dashboards
```

### 4.7 ui, site, hostUi, setup

```
nixie.ui.theme          enum "graphite" | "umber" | "paper", default "graphite"
  The finish used by the control panel, installer and (desktop) the whole
  desktop.
nixie.ui.tokens         nullOr path, default null
  A JSON file overriding any design token.
nixie.ui.links          listOf { label; url; }, default [ ]
  Extra entries in the control panel navigation.
nixie.ui.allowSiteEdits bool, default false
  Let the control panel commit to the site checkout on this host (Declare) and
  run `nixie apply`. Off means the panel can only export text for you to paste.

nixie.site.repo         nullOr str, default null      git URL of the site
nixie.site.ref          str, default "main"
nixie.site.path         path, default "/etc/nixie/site"
  Where the site checkout lives on the host. `nixie apply` runs from here.

nixie.hostUi.enable     bool, default false
  A separate web page for the host itself: files, terminal, journal, services,
  disks, and running nixie commands. It is Cockpit. Turning it on widens the
  attack surface of a hardened host, which is why it is off.
nixie.hostUi.listen     enum "tailnet" | "lan+tailnet", default "tailnet"
nixie.hostUi.port       port, default 9090

nixie.setup.pending     bool, default false
  Internal: true between first boot and Finish; adds the setup generation.
```

### 4.8 desktop

```
nixie.desktop.user               str, default nixie.auth.admin.name
nixie.desktop.finish             enum graphite|umber|paper, default nixie.ui.theme
nixie.desktop.wallpaper          nullOr path, default null (a generated one per finish)
nixie.desktop.accentFromWallpaper bool, default false
nixie.desktop.keyboard.layout    str, default "us"
nixie.desktop.keyboard.variant   str, default ""
nixie.desktop.monitors           listOf { name; mode; position; scale; }, default [ ] (auto)
nixie.desktop.keybinds           attrsOf str, default { } (merged over the platform set)
nixie.desktop.autostart          listOf str, default [ ]
nixie.desktop.defaultApps        { browser; terminal; editor; fileManager; }
nixie.desktop.packages.categories attrsOf (listOf str): browsers, terminals, editors, media, office, communication, gaming, creative
nixie.desktop.packages.extra     listOf package, default [ ]
nixie.desktop.flatpak.enable     bool, default false
nixie.desktop.power.backend      enum "power-profiles-daemon" | "tlp", default "power-profiles-daemon"
nixie.desktop.power.lid          enum "suspend" | "lock" | "ignore", default "suspend"
nixie.desktop.idle.lockAfter     int seconds, default 300
nixie.desktop.idle.screenOffAfter int, default 600
nixie.desktop.idle.suspendAfter  nullOr int, default null
nixie.desktop.nightLight.enable  bool, default true
nixie.desktop.overview.enable    bool, default true (hyprspace plugin; see D5)
nixie.desktop.look.gaps.inner    int, default 6              (change request, desktop rice)
nixie.desktop.look.gaps.outer    int, default 14
nixie.desktop.look.rounding      int, default 12
nixie.desktop.look.borderSize    int, default 2
nixie.desktop.look.blur          bool, default true
nixie.desktop.look.animations    enum full|reduced|none, default full
nixie.desktop.look.barPosition   enum top|bottom, default top
nixie.desktop.look.terminalOpacity float 0..1, default 0.92
nixie.desktop.look.cursor.theme  str, default "Bibata-Modern-Classic" (Bibata-Modern-Ice on paper)
nixie.desktop.look.cursor.size   int, default 24
nixie.desktop.look.iconTheme     str, default "Papirus-Dark" ("Papirus" on paper)
nixie.desktop.fonts.ui           str, default "Archivo"
nixie.desktop.fonts.mono         str, default "JetBrains Mono"
nixie.desktop.wallpapers         nullOr path, default null (the generated set: three per finish)
nixie.desktop.wallpaperCycle     nullOr int minutes, default null
nixie.desktop.favourites         listOf str (desktop-entry ids), default [ ]
nixie.desktop.workspaces.labels  listOf str, default [ ] (numbers)
nixie.desktop.clock.format       str, default "ddd d MMM  HH:mm"
nixie.desktop.terminal.greeting  bool, default true (fastfetch on a new shell)
```

### 4.9 console (change request, built as its own slice after the installer)

```
nixie.console.frontPanel.enable   bool, default true
  A status screen on the first text console instead of a bare login: host
  name, addresses, the control panel URL as a QR code, each instance as a
  lane with its state, GPU temperature and load, pool usage, and anything
  `nixie doctor` would flag, drawn in the chosen finish. Any key opens the
  normal login. The other consoles stay ordinary logins.
nixie.console.kiosk.enable        bool, default false
  Keep the setup kiosk permanently and point it at the control panel, so the
  local display shows the full web UI behind a lock page that checks the
  administrator password and second factor. Costs a compositor and a browser
  in the server closure.
nixie.console.kiosk.idleLock      str, default "10m"
  Re-lock the kiosk after this much inactivity.
```

The front panel is a `writeShellApplication` (same language as `nixie-cli`)
reading the Incus socket read-only through `curl` and the same metrics
endpoint the web UI uses; it is never a second data path. The kiosk is the
one `installer/kiosk.nix` module the setup generation already uses, with the
URL and a lock page as parameters. Console rendering: the initrd prompts,
the attestation code and tty1 must appear on the primary GPU; with the NVIDIA
driver that means `hardware.nvidia.modesetting.enable` and `nvidia-drm.fbdev=1`.
An Incus `gpu` device shares the host driver so the console keeps working;
VFIO passthrough to a VM takes the card away from the host and the console
goes dark, which `docs/console.md` says plainly.

Proposed resolution of the tty conflict (not yet built, awaiting a nod):
the setup generation's kiosk owns tty1 while `nixie.setup.pending` is true
and the front panel is not started then; in the normal generation the front
panel takes tty1, unless the kiosk is enabled, in which case the kiosk keeps
tty1 and the front panel moves to tty2. The kiosk's client certificate is
made at setup, trusted by incusd, and loaded into the kiosk browser's NSS
store with an auto-select policy for the panel URL.

### 4.10 showcase (change request, the last slice)

`packages.media` regenerates `docs/media/` from real VM runs only, with a
`SHOTLIST.md` naming the command and commit behind every asset; the README
is written last and its commands, option names and feature claims are
checked by `checks.readme`. Nothing in it may be mocked.

### 4.11 backups, rollback, recovery and hardware refresh (change request)

Brief additions to sections 6, 7, 10, 11 and 16, received after the console
slice. No new option beyond the ones marked above; the rest is CLI verbs on
`packages.nixie-cli`, units, and two pages.

Snapshots and backups (section 6):

- Local: `services.zfs.autoSnapshot` on the state datasets with the counts
  from `nixie.backups.snapshots`; `nixie apply` first snapshots
  `<pool>/data/state` recursively as `@pre-apply-<label>` and every guest it
  is about to replace as an Incus snapshot `pre-apply-<label>`, pruning to
  the last five of each.
- Offsite: the existing restic job, with `rclone:` repositories through
  `nixie.backups.rcloneConfigFile`, a `restic check` timer, and the result
  in `/var/lib/nixie/backup-check.json` for `nixie doctor`.
- `nixie backup now | list [--json] | verify | kit <file>`. The kit is a
  tar encrypted with a passphrase (`age -p`) holding the LUKS header
  backups of both layers, the host's sops age key, the restic password and
  environment, a freshly enrolled recovery key, and `README.txt` with the
  rebuild steps. `nixie restore <snapshot> [--path <p>] [--to <dir>]`
  restores in place (the default, as before) or beside the live data under
  `--to <dir>`.

Rollback (section 11):

- `nixie rollback` (previous host generation, now), `--list`,
  `--generation N`, `guest <name> [--snapshot s]` (Incus snapshot restore;
  the guest's `/data/state` mount is outside the snapshot and untouched),
  `data <name> [--snapshot s] [--in-place]` (ZFS clone beside the live
  path by default; `zfs rollback` with `--in-place` after a typed
  confirmation).
- Generation label: `system.nixos.tags` carries the site commit
  (`nixie.host.siteRevision`, from the site flake, see D19); the date is the
  profile link's time; the kernel is read from the generation. lanzaboote and
  systemd-boot keep `nixie.host.keepGenerations` entries; a weekly timer
  deletes older generations and collects garbage.
- `nixie apply --confirm-within <duration>`: after the switch, a transient
  timer runs `nixie rollback --auto` unless `nixie apply --confirm` (or
  `nixie doctor` passing when the operator's `deploy`/`.#apply` wrapper
  confirms) cancels it. The wrapper turns it on for remote applies with
  `10m`. `--auto` reverts the host to the previous generation and every
  guest touched by that apply to its `pre-apply-<label>` snapshot.
- Attestation on another generation: phase 6 and `nixie reseal` write the
  label they sealed for to `/boot/nixie/attestation-generation` (the ESP,
  not a secret); the initrd unit compares it with its own label and prints
  "attestation unavailable for this generation (sealed for <label>)"
  instead of a code that could not match.

Recovery (section 7):

- `nixie security reenroll`: phases 5, 6 and 7 again with `--force`, under
  `/var/lib/nixie/reenroll/` markers so setup's own markers stay; usable
  from the front panel's menu. It re-stages Secure Boot enrolment (Setup
  Mode checklist), replaces the TPM token slot, regenerates the attestation
  secret (new QR), sets the lockout auth, and rebuilds the header bundle.
- `nixie usb [--json]` lists blocked devices from usbguard; `nixie usb
  allow <vendor:product[/serial]>` appends to `usbguard.allow` in
  `hosts/<name>/usb.nix` (imported by `mkSite` when present) and commits. The
  generated rules always allow HID keyboards while `nixie.setup.pending`
  or a reenroll is running.

Hardware refresh (section 11):

- `nixie hardware scan` runs discovery and diffs it against
  `hosts/<name>/hardware.nix`; `nixie hardware refresh` shows the diff,
  writes the file, commits, and runs `apply`; `nixie hardware add-disk
  <by-id>` runs disko in format-and-mount mode for a generated layout that
  names only that device, and refuses any device already in `nixie.disks`.
- Rescue network: a lowest-priority networkd `.network` matching every
  wired interface with DHCP, ranked below the uplink units, so a NIC whose
  MAC is not in `hardware.nix` still gets an address; the front panel shows
  every address it has.
- `nixie doctor` adds drift: uplink MAC, GPU or declared disk missing; the
  last unlock used the recovery key or a passphrase instead of the TPM;
  Secure Boot state differs from the site; attestation needs a reseal;
  blocked USB devices. The front panel and the History page show the same
  list.

Pages (section 10): see section 10 below and D22.

## 5. The site contract

`site.nix` is data:

```nix
{
  hosts.web1 = {
    hardware = ./hosts/web1/hardware.nix;   # generated; sets nixie.disks.*, bridge.uplinks, hardware.* facts
    settings = { nixie.profile = "server"; nixie.host.name = "web1"; ... };   # a full NixOS module
    guests = import ./guests.nix;            # optional
    data = import ./data.nix;                # optional
    secrets = ./secrets/web1.yaml;           # optional sops file
  };
}
```

`mkSite ./site.nix` returns:

```
nixosConfigurations.<host>                the host
packages.x86_64-linux.<host>-guest-<g>    NixOS guest tarball + metadata (kind = "nixos")
packages.x86_64-linux.<host>-tofu         terranix JSON for the host
packages.x86_64-linux.<host>-vm           quick VM of the host
packages.x86_64-linux.apply               `nix run .#apply`: sync to the host and run `nixie apply`
checks.x86_64-linux.<host>-eval           the host evaluates and its guests build
```

`hardware.nix` is the only file the installer generates. It contains
`nixie.disks.system`, `nixie.disks.data`, `nixie.network.bridge.uplinks`,
`hardware.nvidia` facts, `boot.initrd.availableKernelModules`, CPU vendor
microcode and `hardware.cpu.*`, and nothing else.

## 6. Guest schema

Declared as a NixOS submodule type so errors name the field.

```nix
web = {
  kind = "nixos";               # "nixos" | "image" | "vm"
  recipe = null;                # "static-web" | "oci-service" | site-provided name
  ip = "auto";                  # "auto" | "a.b.c.d/nn"
  profiles = [ ];               # extra Incus profile names; "killswitch" is added under exit-node
  nesting = false; gpu = false;
  devices = { };                # raw Incus devices merged last
  limits = { memory = null; cpu = null; };
  mounts = { "/data/state/web" = "/var/lib/web"; };   # host -> guest, shift = true
  backup = [ "/data/state/web" ];
  expose = { tailnet = [ "https://web:8080" ]; lan = [ 80 443 ]; };
  module = ./guests/web/configuration.nix;   # nixos guests; merged with the recipe
  image = null;                 # { remote = "images"; fingerprint = "sha256..."; } for image/vm
  cloudInit = null;             # path to user-data for image/vm
  extraConfig = { };            # raw instance config
};
```

Derived, all in `lib/guests.nix` as pure functions used by the module and by
tests:

| from | to |
|---|---|
| name | Incus instance, nic `eth0` with `host_name = "veth-<name>"`, per-guest profile |
| `mounts` | disk devices with `shift = true`; `tmpfiles` rules creating the host paths |
| `gpu` | `gpu` device; nvidia container toolkit enabled on the host when `hardware.nvidia` is on |
| `nesting` | `security.nesting = true` |
| `expose.lan` | nftables accept rules on the bridge for that guest's address (static) or MAC |
| `expose.tailnet` | `tailscale serve` set entries |
| `backup` | restic paths |
| name | Prometheus scrape target label, dashboard variable list |
| everything | the UI's declared list (`/etc/nixie/guests.json`) |

Scratch instances are anything incusd knows that is not in this attrset. The
UI labels them from the same JSON file.

## 7. Data manifest

```nix
{
  hf."llm-small"    = { repo = "org/model"; rev = "abc123"; include = [ "*.safetensors" ]; };
  oci."web-image"   = { image = "docker.io/library/nginx"; digest = "sha256:..."; };
  incus-images.base = { remote = "images"; fingerprint = "..."; };
  http."dataset"    = { url = "https://..."; sha256 = "..."; };
}
```

Each kind is `data-kinds/<kind>.nix`: a function `{ pkgs, root }` returning
`{ runtimeInputs; fetch = "<bash taking the JSON manifest for that kind>"; }`.
`nixie fetch` runs every enabled kind with its slice of the manifest into
`<root>/cache/<kind>/<name>`, marking completion with `.complete`. A site adds
a kind through `nixie.data.kinds.<name> = ./my-kind.nix`.

## 8. Disk and boot chain

```
ESP (1 GiB, vfat)  ---------------------------------  systemd-boot or lanzaboote
system disk:
  [tpm.enable]  LUKS2 "outer"  (TPM2 + PIN, PCRs from option)
     [encryption.enable]  LUKS2 "root" (passphrase)
        ZFS pool "rpool": root, nix, var, home; data/{state,cache,media} when no data disk
data disk (optional):
  [encryption.enable] LUKS2 "data" (same passphrase, keyfile in initrd from root)
     ZFS pool "dpool": state, cache, media
```

With encryption off: ESP + ZFS directly. The disko layout is generated from
`nixie.disks` and `nixie.security.*` in `modules/disks.nix`; the same
expression is what phase 3 runs.

Initrd is `boot.initrd.systemd`. Unlock order in crypttab: outer, root, data.
Attestation runs as an initrd unit ordered before `systemd-cryptsetup@outer`
(or `@root` without TPM) and prints the TOTP code on the console. Duress is a
password agent wrapper: the passphrase prompt goes through a small initrd
script that compares the entry against the sops-provided duress hash before
handing it to cryptsetup; on match it runs `cryptsetup erase` on every layer
and powers off. Remote unlock uses `boot.initrd.network.ssh` with the admin
keys; prompts are relayed with `systemd-tty-ask-password-agent`.

Always on with encryption: `panic=10`, TPM lockout auth set from a sops secret
by phase 6, and LUKS header backups GPG-encrypted to a sops-held key written
where the wizard chose (a download in the browser path, a path in the
headless path).

## 9. Phase engine and installer state machine

Markers: `/var/lib/nixie/setup/<N>.done`, state in
`/var/lib/nixie/setup/state.json` (profile, host name, chosen options, no
secrets). Secrets stay in the running backend's memory and are written only
to their final sops or LUKS destinations. Every phase is `installer/phases/NN-<name>.sh`,
takes `--site <dir> --host <name>`, and exits 0 immediately when its marker
exists.

```
 ISO / kexec environment                         installed system, setup generation
 ┌──────────────────────────────┐                ┌──────────────────────────────────────┐
 │ 1 discover  -> hardware.nix  │                │ 4 first-boot  (unlock, network, ssh)  │
 │ 2 keys      -> host key, sops│    reboot      │ 5 secure boot (Setup Mode checklist)  │ reboot
 │ 3 install   -> disko, install│ ─────────────▶ │ 6 tpm enrol   (PIN, TOTP QR, lockout, │
 │             lanzaboote sign  │                │               header backups)         │ reboot
 └──────────────────────────────┘                │ 7 verify      (boot chain check)      │
                                                 │ 8 apply       (site, guests, fetch,   │
                                                 │               restore)                │
                                                 │ Finish: pending=false, apply, GC      │
                                                 └──────────────────────────────────────┘
```

Phases 5, 6, 7 exist only when their options are on; with everything off, the
kiosk goes 4 -> 8 -> Finish with no reboot pauses.

State across reboots: after phase 3 the installer writes
`hosts/<name>/setup-pending.nix` (sets `nixie.setup.pending = true`) into the
site checkout, which adds the `nixie-setup` specialisation (kiosk +
continuation service) to the built system, and runs `bootctl set-default` to
that entry. Every reboot inside phases 5 to 7 lands in the specialisation
because the default entry still points there. Finish deletes the pending
file, runs `nixie apply` (which switches to the plain generation), clears the
default entry, deletes older generations and collects garbage. A check
evaluates the example server host with pending = false and proves with
`nix why-depends` that no compositor or browser is in the closure.

Reenrol (change request): `nixie security reenroll` runs phases 5 to 7 with
`--force` and its own marker directory, so the same scripts serve setup and
recovery after a board, TPM or firmware change; the front panel offers it.

Front ends:

- Kiosk (ISO default, and the specialisation): `services.cage` running
  Chromium in kiosk mode against `https://127.0.0.1:9443` with the local
  certificate trusted. tty2 runs the `gum` wizard.
- LAN: the same backend on `:9443`; the console prints the URL, a six-digit
  single-use pairing code, the certificate fingerprint, and a QR.
- Headless: `deploy` runs the `gum` wizard locally and drives the phases over
  SSH through `nixos-anywhere` (kexec when the target is a foreign Linux,
  skipped when it is the Nixie ISO). The continuation phases run over SSH the
  same way with the same scripts.

`nixie-setup` backend: a Python 3 stdlib program (`http.server`, `ssl`,
`json`, `subprocess`). Endpoints: `POST /pair`, `GET /hardware`,
`GET /options` (option metadata rendered from the module tree at build time),
`POST /plan` (returns the `hardware.nix` and settings it will write),
`POST /phase/<n>` (streams output as SSE), `GET /state`, `POST /finish`.
Secrets are posted once and held in process memory. The port is bound only
while `state.json` says setup is incomplete.

## 10. Web surfaces

One npm workspace under `ui/` with a committed lockfile, built by
`buildNpmPackage`, no runtime network, fonts copied from the nixpkgs `archivo`
and `jetbrains-mono` packages at build time.

- `ui/tokens`: the 21 custom properties per finish, extracted from the design
  file (see `docs/design-tokens.md`), as JSON. `lib/tokens.nix` imports the
  same JSON so the desktop theme, greeter and Cockpit branding use one source.
- `ui/components`: panel, well, lane, heat strip, ring gauge, chart (uPlot),
  buttons, chips, command palette, terminal (xterm.js).
- `ui/nixie-ui`: React. Views in the design's nav order: Overview, Instances,
  Images, Profiles, Networks, Storage, Operations, Settings, plus Dashboards
  and Host (link). Data from the Incus REST API over the same origin
  (`INCUS_UI` serving), websocket for exec and events, `/1.0/metrics` for the
  rolling history, Prometheus `query_range` adapter for long history. Demo
  mode with the design's seeded random-walk generator when no daemon answers.
- `ui/nixie-setup`: React, the wizard steps of brief section 11, rendering
  option descriptions from the metadata JSON the backend serves.

Library choice: React because xterm.js, uPlot and the accessibility tooling
have first-party React bindings, and the design has no animation the virtual
DOM would fight.

History (change request, see D22): guest generations and snapshots live in
the control panel (Instances > Snapshots, from the Incus API, with restore).
Host generations, data snapshots, restic snapshots and the actions on them
(switch now, boot into on next reboot, restore a data snapshot beside or in
place, browse a restic snapshot and restore a file or directory, backup now,
verify) are a branded Cockpit page, `packages.nixie-cockpit`, reached from
the panel's Host link; it calls `nixie ... --json` through the Cockpit
bridge, so the admin login and second factor of the host page gate every
action. The tty1 front panel offers host rollback and "boot previous
generation" from its menu.

## 11. Desktop profile

Shell: **Quickshell** (0.3.0 in the pin). One process, QML, native Hyprland
IPC, Wayland layer-shell, and its theme is a single JSON the token source
generates. AGS 2 is a Gjs framework that needs a separate build step, GTK4
CSS theming and several helper daemons for the same result. Quickshell
matches the "one coherent shell layer" bar with less to hold together.

Layout of the desktop configuration: NixOS-level only. Hyprland's config,
the Quickshell shell, GTK/Qt themes, terminal and editor colours are
generated files under `/etc/xdg` and `/etc/nixie/desktop/` from
`lib/tokens.nix`; the user's `~/.config/nixie/local.conf` and Hyprland
`local.lua` are sourced last. No home-manager.

Components from the pin: Hyprland 0.55.4 (Lua configuration, see D25),
hyprlock, hypridle, swaybg (one process per wallpaper; see the slice (r) verification for why not awww or hyprpaper), hyprsunset (night light), grim + slurp + satty (screenshot and
annotation), wf-recorder, hyprpicker, cliphist, hyprpolkitagent, greetd +
regreet (greeter themed from tokens), PipeWire, NetworkManager, BlueZ,
xdg-desktop-portal-hyprland, power-profiles-daemon or TLP. Overview:
`hyprlandPlugins.hyprspace` (see D2). Fonts: Archivo (from `google-fonts`,
the design's UI face), JetBrains Mono, Material Symbols Rounded (the shell's
icons), Noto. Cursor: Bibata. Icons: Papirus. GTK: adw-gtk3 with per-finish
CSS.

### 11.1 The desktop rice (change request, 2026-09-11)

The request: a fully featured, modern desktop in the class of HyDE, still
declarative and still verified in a VM. What changes:

- **Hyprland config is Lua** (`/etc/xdg/hypr/hyprland.lua`, linked into
  `~/.config/hypr/hyprland.lua`), generated from the options: gaps, rounding,
  borders, blur with layered translucency, shadows, a curated set of curves
  and springs, workspace slide, layer fades, performance rules (fullscreen
  and games drop blur and animation), gestures, per-monitor lines, and the
  full keybinding scheme. It reads the active finish's palette at load time
  from `/etc/nixie/desktop/tokens/<finish>.json` (Lua can read a file), so a
  finish switch is `hyprctl reload`, not a rebuild. `~/.config/hypr/local.lua`
  is `require`d last when present.
- **Runtime finish switching, HyDE-style.** Every finish's assets are
  shipped (`/etc/nixie/desktop/<finish>/`: tokens, GTK CSS, kitty colours,
  hyprlock, wallpapers). The active finish is `~/.config/nixie/finish`
  (default: the site option). `nixie-shell finish <name>` writes it, relinks
  the per-user symlinks (`~/.config/gtk-{3,4}.0/gtk.css`,
  `~/.config/nixie/kitty.conf`, `~/.config/hypr/hyprlock.conf`), sets the
  GTK colour scheme, icon and cursor theme through `gsettings` (GTK apps
  follow live through the settings portal), reloads Hyprland, signals kitty
  (`SIGUSR1` reloads its config) and switches the wallpaper. The shell watches the file. `nixie.desktop.finish` stays the
  declared default and `nixie menu` still edits it in the site.
- **Wallpapers.** Three procedural wallpapers per finish are generated at
  build (blurred plasma tinted with the finish's palette, one with the
  Segment n mark), and `nixie.desktop.wallpapers` points at a directory of
  the person's own. `nixie-shell wallpaper next|prev|<path>` starts a new swaybg
  behind the old one and remembers the choice in `~/.config/nixie/wallpaper`; the
  shell has a picker grid; `wallpaperCycle` starts a timer. With
  `accentFromWallpaper`, the shell quantises the image (Quickshell's
  `ColorQuantizer`) and writes `~/.config/nixie/accent`, which the Lua config
  and the shell prefer over the finish's brand colour.
- **The shell** (Quickshell, one process, QML under
  `modules/desktop/shell/`): a floating bar (the mark, workspaces with
  labels and occupancy, the focused window with its icon or the playing
  track, tray, network, Bluetooth, volume, battery, clock, notification and
  control-centre buttons); launcher with app icons and a favourites row plus
  the file, calculator, emoji and clipboard modes; notification centre with
  do-not-disturb, app groups, images and actions; popups that stack; a
  control centre with sliders (volume, brightness), toggles (Wi-Fi,
  Bluetooth, DND, night light), power profiles, media controls, the three
  finish swatches and the wallpaper button; a calendar on the clock; OSDs
  with icons; the power menu as tiles with keyboard navigation; the window
  switcher with icons; the cheat-sheet; the wallpaper picker. For parity
  with HyDE it also carries processor, memory and temperature readouts in
  the bar, a Wi-Fi list that takes a password and joins, a list of paired
  Bluetooth devices, a volume slider per playing application, a screenshot
  menu (region, window, screen, delayed), a keep-awake inhibitor, and
  wallbash: with `accentFromWallpaper` the shell quantises the wallpaper
  (Quickshell's `ColorQuantizer`), writes `~/.config/nixie/accent` and
  reloads Hyprland, so borders and the shell follow the image. Icons are
  Material Symbols glyphs (a font, no image assets). IPC stays the socket
  `nixie-shell <verb>` already speaks.
- **Terminal.** kitty themed per finish with the chosen opacity, fish with a
  starship prompt from the tokens, fastfetch with the mark on a new shell
  (`terminal.greeting`).
- **Lock screen.** hyprlock with the blurred wallpaper, clock, user, battery
  and a themed input; per finish.

Verification: `vm-desktop` grows to screenshot and OCR every surface, assert
`hyprctl configerrors` is empty, list an app in the launcher, show a
notification, open the control centre, calendar, power menu and wallpaper
picker, switch the finish at runtime (border colour through
`hyprctl getoption`, kitty and GTK links, tokens file), change wallpaper
(the swaybg process), and lock the screen. `media-desktop` records the same for the
showcase.

Not built (and why): a dock (the bar's favourites row in the launcher covers
pinned apps; a dock duplicates it), weather (network in a VM test is a
fixture, and the brief does not ask), and a wallpaper-derived full palette
(matugen): the three finishes are the design system; the accent is the one
wallpaper-derived colour that keeps them recognisable.

`nixie menu`: a `gum` script in a terminal window (launcher entry) that edits
`site.nix` values through `nix-instantiate --eval` round trips, shows a diff,
and runs `nixie apply`.

## 12. Checks

| check | proves |
|---|---|
| `fmt`, `statix`, `deadnix` | style |
| `no-hardware-facts` | grep for MACs, device-node disk paths, PCI, interface and board names |
| `no-secrets-in-store` | closure grep for key-like material |
| `systemd-security` | every platform unit at "OK" or a `# exposure:` comment |
| `profiles-disjoint` | `nix why-depends` both directions on the examples |
| `option-docs` | every `nixie.*` option has a description |
| `eval-matrix` | throwaway sites: no GPU, one NIC, no TPM, no data disk, VM; evaluation only (the derivation paths are written without string context, so the check does not build each host's build closure) |
| `vm-boot-plain` | example server boots, incusd up |
| `vm-encryption` | OVMF + swtpm: LUKS root unlock, TPM layer + PIN, attestation code shown, duress wipes, remote unlock |
| `vm-egress` | declared and undeclared guest cannot reach the internet directly under exit-node |
| `vm-guest-nixos` | a NixOS guest image boots inside Incus on the host VM |
| `vm-apply` | delete guest, apply recreates; scratch untouched; export/declare round trip |
| `vm-data` | delete cache/, fetch restores (http kind against a test server); restore brings back state/ |
| `vm-monitoring` | scrape targets up, dashboards provisioned |
| `vm-installer-lan` | second VM's browser drives the wizard |
| `vm-desktop` | greeter, Hyprland session, no config errors, every shell surface by screenshot and OCR, runtime finish switch, wallpaper change, lock screen, finish switch after apply |
| `vm-host-ui` | Cockpit reachable with the admin login and TOTP; the History page lists generations and snapshots |
| `vm-backup` (change request) | pre-apply ZFS and Incus snapshots exist and are pruned; `nixie backup now\|list\|verify`; a deleted state file comes back with `nixie restore --path`; the kit decrypts with its passphrase and holds headers, age key, restic secrets and a recovery key |
| `vm-rollback` (change request) | a broken UI in a new generation is undone from the front panel; `apply --confirm-within` with no confirmation reverts host and guests; a guest snapshot restore leaves its `/data/state` untouched |
| `vm-hardware` (change request) | NIC MAC swap: rescue DHCP, `hardware refresh` restores the bridge; swtpm reset: recovery-key unlock, then `security reenroll`; a new USB device is blocked, `nixie usb` lists it, `allow` + `apply` admits it |
| `ui-build`, `setup-build`, `iso-build` | packages build |

## 13. Deviations from the brief

- **D1 nixpkgs release.** `nixos-26.05`, the current stable, rather than
  unstable, so package versions hold still across slices.
- **D2 No `hyprexpo`.** It is not packaged in the pin; `hyprspace` is and
  provides the same overview. Used behind `nixie.desktop.overview.enable`.
- **D3 No WebAuthn second factor.** The host UI is Cockpit, which
  authenticates through PAM on the server. A browser passkey cannot be
  presented to PAM, and `pam_u2f` needs the key plugged into the server, not
  the laptop. The only PAM-compatible second factor that works remotely is
  TOTP (`pam_google_authenticator`), which is what "totp" enrols. Offering
  "webauthn" would need an authenticating reverse proxy, a native host agent,
  which the brief defers. The enum is therefore `none | totp`; the wizard
  says so. Revisit when a host agent exists.
- **D4 Lockdown defaults off and is documented.** NixOS kernels do not sign
  modules, so `lockdown=integrity` refuses every module, in-tree included.
  The option exists, defaults to "none", and its description says why.
  Verified in a VM in slice (b).
- **D5 tpm2-totp has no NixOS module.** `modules/security/attestation.nix`
  provides the initrd unit; the package is in the pin.
- **D6 Second factor enrolment in the wizard is TOTP only** (follows D3).
- **D7 The setup generation is selected with `bootctl set-default`** rather
  than by rewriting the site between reboots; see section 9.
- **D9 Closure disjointness check.** Implemented as a pure `closureInfo`
  grep rather than `nix why-depends`, which cannot run inside a build; the
  manual command is in `VERIFICATION.md`. With `nixie.console.kiosk.enable`
  on, the server closure may contain exactly the kiosk stack (cage and the
  kiosk browser) and nothing else from the desktop list.
- **D10 TPM lockout password and header-backup encryption.** The lockout
  password is kept in `/var/lib/nixie/tpm-lockout-auth` on the encrypted root
  and printed into the header-backup bundle, not written to sops, because
  adding it to the site would change the built closure mid-setup. The bundle
  is encrypted with `age` to the host's key and every recipient in
  `.sops.yaml`, which is what "a sops key" is in this platform.
- **D11 Secrets are read from the site checkout at runtime.** `nixie.secrets.file`
  resolves to the same path under `nixie.site.path` and `sops.validateSopsFiles`
  is off, so no sops file enters the store and setup can extend it (phase 2
  adds Secure Boot keys and the TOTP secret) without rebuilding. Tests share
  the example site into the VM at that path.
- **D12 Two nftables families.** Per-guest chains keyed on `veth-<name>` and
  the catch-all `guest-undeclared` live in the `bridge` family, where a
  bridge port name is visible; the egress policy (tunnel only under
  exit-node) is enforced in the `inet` forward hook keyed on the bridge,
  which is where routed guest traffic actually passes. Exit-node egress
  requires the managed-nat bridge mode, because on an unmanaged LAN bridge
  guest frames never enter the host's IP stack.
- **D13 NixOS guest images are built inside the host closure**
  (`nixie.build.guestImages`), so `nixos-rebuild switch` on the host builds
  them and `nixie apply` only imports by alias. `mkSite` re-exports them as
  `<host>-guest-<name>`.
- **D14 Changed NixOS guests are replaced, not switched in place.** The image
  alias carries the store hash; tofu replaces the instance and the state in
  mounts is untouched. In-place `nixos-rebuild` inside the guest is not done.
- **D15 Long history and Grafana are reached through `tailscale serve`**
  (`/prometheus`, `/grafana` on the host's tailnet name) rather than by
  exposing plain-HTTP ports next to the TLS control panel; without Tailscale
  the panel keeps its in-browser rolling history.
- **D16 Declare from the control panel is wired to `nixie.json.declareUrl`**
  but no endpoint provides it yet: incusd cannot run host commands and the
  brief defers a host agent. Export works everywhere; Declare stays disabled
  until an agent exists. `nixie.ui.allowSiteEdits` is honoured by the UI.
- **D17 The kiosk lock page checks the password with `unix_chkpwd`** (the
  pam_unix helper, which reads it from stdin; `su` needs a terminal) and the
  TOTP code against the same secret the host page uses; it binds to loopback
  only.
- **D18 The system disk in tests is a plain device path** (`/dev/vda`,
  overridden with `mkForce`), because the test framework's virtio drive has
  no serial and so no by-id link. The ISO test driver attaches the disk with
  a serial so `hardware.nix` there holds a by-id path.
- **D19 The site flake passes its own revision.** Pure evaluation cannot
  see the site's `.git`, so `lib.mkSite` also accepts
  `{ site = ./site.nix; rev = self.shortRev or self.dirtyShortRev or null; }`
  and the template does that; the plain-path form still works and yields
  generations labelled "unknown". The generation date is the profile link's
  time, not baked into the build.
- **D20 The attestation "unavailable for this generation" message is
  decided in the initrd from a file on the ESP** (`/boot/nixie/attestation-generation`,
  written by phase 6 and `nixie reseal`), because the code is shown before
  the root file system is unlocked and the label itself is not secret.
- **D21 The recovery key is not in the on-host header bundle.** The brief's
  addition says never stored on the host; phase 6 shows it once, and
  `nixie backup kit` enrols a fresh one for the passphrase-encrypted kit.
  D10's bundle keeps the headers, lockout auth and TOTP reseal password.
- **D22 History is split across the two existing web surfaces** (built in
  slice (q): `packages.nixie-cockpit` is the host page's History screen and
  `ui/src/pages/History.tsx` the control panel's, both reading
  `nixie rollback --json` rather than scraping human output) rather
  than a new host agent: guest snapshots in the control panel (Incus API),
  host generations, data and restic snapshots and their actions on a
  branded Cockpit page that runs `nixie` through the Cockpit bridge. The
  brief keeps the host UI as Cockpit and forbids a native agent; the control
  panel is a static bundle with no host process to call.
- **D23 `nixie.backups.repository` stays the option name**; the addition's
  `nixie.backups.repo` is the same setting, and the docs say so.
- **D24 Local snapshots use `services.zfs.autoSnapshot`** with the counts
  mapped from `nixie.backups.snapshots`, rather than a hand-rolled timer;
  state is always a ZFS dataset (on the data pool or on root).
- **D25 Hyprland is configured in Lua, not `hyprland.conf`.** The pinned
  Hyprland (0.55.4) reads `hyprland.lua` first and treats the `.conf`
  format as legacy (its parser prints deprecation warnings on screen for
  `windowrulev2`, and the one-line `{ a = b; c = d }` blocks the old file
  used are not valid there). The Lua file also lets a finish switch happen
  at `hyprctl reload` time without a rebuild. The user override file is
  therefore `~/.config/hypr/local.lua` (the brief's "Hyprland `local.conf`").
- **D27 HyDE is supported two ways, neither of which is a flake input of
  the platform.** `nixie.desktop.hyde.themes` reads a HyDE theme directory
  as data at build time (its kitty palette and its wallpapers) and turns it
  into an ordinary Nixie finish, so all of HyDE's themes work with the Nixie
  shell, pinned and offline. `nixie.desktop.hyde.enable` stands every Nixie
  desktop module down so a site that imports hydenix gets the real HyDE
  desktop instead. The platform takes no dependency either way: adding
  hydenix as an input would pull home-manager and a large third-party tree
  into every evaluation, including servers that will never have a desktop,
  and HyDE's theme switcher fetches from the network at use, which the
  platform's own desktop never does.
- **D26 The active finish can be changed at runtime.** The brief says
  "changing finish is one option and an apply"; that stays the declared
  default, and the site is still the record. The runtime choice in
  `~/.config/nixie/finish` is a per-user preference like the wallpaper,
  the same class of thing as `local.conf`, and is what makes the desktop
  feel like a rice rather than a rebuild.
- **D8 Control panel scope.** The panel is built view by view in slice (h)
  starting from the two screens the design file draws. Every Incus feature the
  brief lists is implemented, but ones the design does not draw follow the
  same component recipes rather than a new design. `VERIFICATION.md` for the
  slice lists any feature that shipped in reduced form.

## 14. Questions and the defaults taken

1. Template URL owner. Docs use `github:OWNER/nixie`; replace when published.
2. Stable versus unstable nixpkgs. Stable `26.05` (D1).
3. UI framework. React + uPlot + xterm.js (section 10).
4. Desktop shell. Quickshell (section 11).
5. Header backup destination in the graphical path. Browser download in the
   LAN path, a chosen USB path in the kiosk and headless paths, both offered.

## 15. Change-request slices (added 2026-09-11)

After the console and showcase slices, in this order, one commit each with
`VERIFICATION.md` entries and the VM tests named in section 12:

- (m) backups: snapshots, restic backends and check, `nixie backup`,
  `nixie restore` extensions, the kit, the README "rebuild from nothing"
  section; `vm-backup`.
- (n) rollback: generation labels and limits, `nixie rollback`,
  `apply --confirm-within`, the attestation message, front-panel rollback;
  `vm-rollback`.
- (o) recovery: recovery-key policy, `nixie security reenroll`, `nixie usb`
  and `usbguard.allow`; part of `vm-hardware`.
- (p) hardware: `nixie hardware scan|refresh|add-disk`, rescue network,
  doctor drift; `vm-hardware`.
- (q) history: `packages.nixie-cockpit` page and the panel's snapshots view;
  `vm-host-ui` extension.
- (p) hardware: `nixie hardware scan|refresh|add-disk`, the rescue network,
  the per-host facts file and doctor drift; `vm-hardware` (done).
- (q) history: `packages.nixie-cockpit` and the control panel's History
  page, both on `nixie rollback --json`; `vm-host-ui` extension (done).
- (r) desktop rice (section 11.1, D25, D26): Lua Hyprland config, runtime
  finish switching, wallpapers and accent, the full shell, terminal and lock
  screen; `vm-desktop` and `media-desktop` extended.
