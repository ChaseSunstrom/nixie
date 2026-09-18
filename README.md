# Nixie

Nixie is a reusable NixOS platform with one installer ISO and two profiles: a
hardened **server** that runs services as isolated Incus guests declared in
Nix with a web control panel, and a **desktop** with a complete Hyprland
environment. A profile is chosen at install; a system contains only its own
profile's software. Your machines, guests and choices live in a small *site*
repository; this repository is the platform and holds nothing specific to
anyone.

## Gallery

Every picture and video below is a real run in a virtual machine: a NixOS
test that boots the machine, drives it and screenshots or records it.
`nix run .#media` regenerates the lot, and `docs/media/SHOTLIST.md` names the
run and the commit behind each file. The gallery stays under 100 MB with each
video under 8 MB, so it lives in git with no large-file storage; that command
fails rather than exceed it. GitHub does not play the videos inline, so they
are linked.

### Installing

The wizard on the machine's own screen, and the same pages from a browser on
another device. The steps are Machine, Disks, Name, Security, Network,
Services and, on a desktop, Desktop.

| | |
|---|---|
| ![The wizard on the machine's own screen](docs/media/installer-kiosk-wizard.png) | ![What this machine is for](docs/media/installer-profile.png) |
| ![Disks](docs/media/installer-hardware.png) | ![Security and the administrator](docs/media/installer-security.png) |
| ![Network: the time zone comes from the machine's own list](docs/media/installer-network.png) | ![Services: a backup folder can be picked from the drives this machine can see](docs/media/installer-services-backup-drive.png) |

Review shows a summary of every step, opens each file the install uses in an
editor with completion and help for every `nixie.*` option, and checks that
the machine evaluates before Install is allowed. Install is a checklist with a
progress bar per step.

| | |
|---|---|
| ![Review](docs/media/installer-review.png) | ![Install](docs/media/installer-install-streaming.png) |

After the restart, setup runs by itself: steps this machine does not use are
skipped without being shown, and it stops only for the Secure Boot restart and
for the disk passphrase and PIN.

![Setup after the first restart](docs/media/installer-continuation-kiosk.png)

### Booting

The splash in the machine's finish, over a quiet boot from the loader on: the
mark and an indeterminate bar while it starts, the attestation code under
everything while anything is asked, and the TPM PIN and the passphrase on the
same screen, with a note when one was wrong and while the disk opens. Hardened
machines get it too, and the duress passphrase works at every prompt.
`nixie.host.splashTheme` swaps in any Plymouth theme: one Plymouth ships, a
package, or a directory from any repository.

| | |
|---|---|
| ![Attestation code](docs/media/boot-attestation-code.png) | ![PIN prompt](docs/media/boot-pin-prompt.png) |

### Control panel

Every screen in all three finishes; here Graphite and Paper. A walk-through
video: [`docs/media/panel-walkthrough.webm`](docs/media/panel-walkthrough.webm).

| | |
|---|---|
| ![Overview](docs/media/panel-overview-graphite.png) | ![An instance](docs/media/panel-instances-web-graphite.png) |
| ![Machines: every machine of the site](docs/media/panel-machines-graphite.png) | ![Settings](docs/media/panel-settings-graphite.png) |
| ![Overview in Paper](docs/media/panel-overview-paper.png) | ![Machines in Paper](docs/media/panel-machines-paper.png) |

### Console, host page and desktop

The front panel on the first text console, the kiosk's lock page, Cockpit
with the Nixie tokens, and the desktop profile's Hyprland session.

| | |
|---|---|
| ![Front panel](docs/media/front-panel.png) | ![Kiosk lock page](docs/media/kiosk-lock.png) |
| ![Host page](docs/media/hostui-overview.png) | ![Desktop](docs/media/desktop-bar.png) |

More of the desktop: the launcher, notification centre, control centre,
calendar, wallpaper picker, lock screen and power menu are in `docs/media/`,
with videos of the window motion
([`desktop-motion.webm`](docs/media/desktop-motion.webm)) and a runtime finish
switch ([`desktop-finish-runtime.webm`](docs/media/desktop-finish-runtime.webm)).

## Requirements

- An x86_64 machine with UEFI firmware (CSM off). The ISO starts in BIOS mode
  too, but only to say so: installing needs UEFI (in VirtualBox, Settings,
  System, Enable EFI).
- A TPM 2.0 is optional; it enables TPM binding with a PIN and attestation.
- Any GPU or none. NVIDIA cards get the proprietary driver with modesetting
  so the console keeps rendering; giving a card to a guest as an Incus `gpu`
  device shares it, VFIO passthrough to a VM takes it away from the host
  ([docs/console.md](docs/console.md)).
- Memory: 4 GB is enough for a server host; guests add their own.

## Quick start A: the ISO and a browser

1. `nix build .#nixie-iso` makes `result/iso/nixie_<version>_x86_64-linux.iso`;
   write it to a USB stick (or attach it to a VM with EFI turned on) and boot
   it. The menu offers the graphical wizard on this screen, a browser on
   another device, or the terminal.
2. Use the wizard on the machine's screen, or open the printed
   `https://<address>:9443/` on another device, compare the fingerprint and
   enter the pairing code.
3. Walk the steps: Machine, Disks, Name, Security, Network, Services, and
   Desktop on a desktop. Each field shows the first sentence of its help,
   with More for the rest; anything advanced is behind More options. A field
   the machine can answer for you offers a list rather than a blank: the time
   zone comes from this machine's own tzdata, and a backup folder can be
   picked from the drives it can see, which are mounted when picked. The
   Machine step also asks how much security you want: **Standard** leaves
   each feature a choice, **Hardened** turns them all on (TPM and PIN, an
   attestation code, Secure Boot, a duress passphrase, USB device blocking,
   memory encryption, key-only SSH, a second factor) and walks through every
   one of them, asking for what each needs.
4. Review: a summary of every step, and every file the install uses
   (`site.nix`, the machine's own `configuration.nix`, `hardware.nix`,
   `guests.nix`, `data.nix`, `flake.nix`) in an editor with Nix
   highlighting, completion and help for every `nixie.*` option. The
   machine is evaluated the way the install will build it and errors are
   marked on their line; Install waits for that check to pass. Then
   install and restart. Installing is a checklist with a progress bar per
   step.
5. Setup carries on by itself after the restart, in the same front end, as
   a checklist: steps this machine does not use are skipped without being
   shown, and it stops only for what needs you — one restart for Secure
   Boot enrolment, and the disk passphrase and PIN to bind the TPM. On an
   encrypted machine the last step writes the disk's header backup to a
   drive you pick, or downloads it. Finish removes the wizard. Details:
   [docs/guides/install-graphically.md](docs/guides/install-graphically.md).

## Quick start B: Nix

1. `nix flake init -t github:OWNER/nixie#site` in a new repository.
2. Edit `site.nix`: one entry per host with `nixie.profile`, the
   administrator and the security options; put guests in `guests.nix` and
   cache contents in `data.nix`.
3. `nix run github:OWNER/nixie#deploy -- --site . --host <name> root@<target>`
   installs over SSH (kexec if the target is another Linux, the ISO as is),
   restarts the machine, waits for it and carries on with the rest of setup
   in your own terminal: the passphrase, the PIN, the Secure Boot restarts
   and Finish. An encrypted target is unlocked at its screen, or over SSH on
   port 2222 when remote unlock is on, before it comes back.
4. From then on, `nixie apply` on the host: it commits hand edits in
   `/etc/nixie/site`, switches the system, and pushes the site back when
   `nixie.site.repo` is set. Details:
   [docs/guides/install-headlessly.md](docs/guides/install-headlessly.md).

## Profiles

| | server | desktop |
|---|---|---|
| contains | incusd, nftables, the control panel, optional Tailscale, exporters, backup timer, the front panel | Hyprland, greetd, the shell, PipeWire, NetworkManager, Bluetooth, the chosen packages |
| never contains | a compositor, a browser or any desktop package (unless `nixie.console.kiosk.enable`, which adds exactly cage and the kiosk browser) | Incus, OpenTofu, Prometheus, Grafana, restic, Cockpit (unless the site enables them) |
| proven by | [closure checks](VERIFICATION.md#profiles) | [closure checks](VERIFICATION.md#profiles) |

Both share the boot chain, the security stack, the installer and the
`nixie` command ([docs/concepts/hosts.md](docs/concepts/hosts.md)).

## Security features

| option | what it does | what it costs | default |
|---|---|---|---|
| `nixie.security.encryption.enable` | LUKS2 under ZFS on the system disk (and the data disk, keyed from the root) | a passphrase every boot; the one change that needs a reinstall | off (the ISO pre-selects on) |
| `nixie.security.tpm.enable` | an outer LUKS layer bound to the TPM 2.0 with a required PIN, PCRs from `nixie.security.tpm.pcrs` | a PIN every boot; `nixie reseal` after firmware changes | off |
| `nixie.security.secureBoot.enable` | lanzaboote signs the boot chain with your keys, enrolled from Setup Mode | a firmware visit; unsigned media will not boot | off |
| `nixie.security.attestation.enable` | a TOTP code from the TPM before the passphrase prompt | comparing a code at boot; `nixie reseal` after kernel updates | off |
| `nixie.security.duress.enable` | a second passphrase that erases every key slot and powers off | no undo | off |
| `nixie.security.remoteUnlock.enable` | early-boot SSH with the administrator's keys | the early-boot host key on the boot partition | off |
| `nixie.security.lockdown` | kernel lockdown integrity mode | a kernel rebuild and no unsigned modules | `none` |
| `nixie.security.hardening.usbguard.enable` | USB allowlist from setup, plus `usbguard.allow` | new devices blocked until `nixie usb allow` lists them | on for servers |

Each was exercised in a VM with OVMF and swtpm
([VERIFICATION.md#encryption](VERIFICATION.md#encryption)); the table's
costs are from [docs/concepts/security.md](docs/concepts/security.md).

## The site model

```nix
# site.nix
{
  hosts.server = {
    hardware = ./hosts/server/hardware.nix;   # written by the installer
    secrets = ./secrets/server.yaml;          # sops, read on the host at activation
    guests = import ./guests.nix;
    data = import ./data.nix;
    settings = {
      nixie.profile = "server";
      nixie.auth.admin.name = "admin";
    };
  };
}
```

One site holds as many machines as you like: another entry under `hosts`,
installed from the same ISO with this site's repository or with
`nix run nixie#deploy`. Every machine of the site is listed on the panel's
Machines page, on each of them.

```nix
# guests.nix: the only place guest names appear
{
  web = {
    recipe = "static-web";
    ip = "192.0.2.10/24";
    mounts."/data/state/web" = "/var/www";
    backup = [ "/data/state/web" ];
    expose.lan = [ 80 ];
    module = ./guests/web/configuration.nix;
  };
}
```

```nix
# data.nix: what lives in cache/, by fetcher kind
{
  http.dataset = { url = "https://example.invalid/dataset.tar"; sha256 = "…"; };
  hf.model = { repo = "org/model"; rev = "main"; };
}
```

The example site in `examples/site` declares one guest per capability
(native service, OCI image under podman, GPU, nesting, VM, foreign image
with cloud-init, fixed address, mounts, backups, tailnet exposure). The
checked snippet below lists them:

```sh test
test -f site.nix && test -f guests.nix && test -f data.nix
grep -c '= {' guests.nix | grep -qx 7
grep -q 'recipe = "static-web"' guests.nix
grep -q 'kind = "vm"' guests.nix
grep -q 'nesting = true' guests.nix
grep -q 'gpu = true' guests.nix
```

## Everyday commands

| command | does |
|---|---|
| `nixie apply [--yes]` | commits hand edits in `/etc/nixie/site`, host switch, guest images by hash, `tofu apply`, then pushes the site to `nixie.site.repo` when set; shows a plan first ([VERIFICATION.md#guests](VERIFICATION.md#guests)) |
| `nixie site key` | the host's key for the site repository: give it write access there and apply pushes every change |
| `nixie fetch` | fills `cache/` from `data.nix`; idempotent ([VERIFICATION.md#data](VERIFICATION.md#data)) |
| `nixie backup now\|list\|verify\|kit <file>` | run a backup, list snapshots, check the repository, write the disaster kit ([VERIFICATION.md#slice-m-backups](VERIFICATION.md#slice-m-backups)) |
| `nixie restore <snapshot> [--path <p>] [--to <dir>]` | puts `state/` (or one path) back in place, or beside the live data with `--to` |
| `nixie apply --confirm-within 10m` | as above, and reverts host and touched guests unless `nixie apply --confirm` arrives in time ([VERIFICATION.md#slice-n-rollback](VERIFICATION.md#slice-n-rollback)) |
| `nixie rollback [--list \| --generation N \| --boot-previous]` | back to the previous system now, list generations (site commit, date, kernel), or boot the previous one next time |
| `nixie rollback guest <name> [--snapshot s]` | restore a guest's root disk from a snapshot; its `state/` is untouched |
| `nixie rollback data <name> [--snapshot s] [--in-place]` | a state directory from a ZFS snapshot, beside the live one or in place |
| `nixie reseal` | reseals attestation to the running boot chain |
| `nixie security reenroll` | after a board, TPM or firmware change: Secure Boot enrolment, TPM + PIN binding with a new recovery key, attestation, lockout password, header backups; resumable, also from the front panel (`e`) ([VERIFICATION.md#slice-o-recovery](VERIFICATION.md#slice-o-recovery)) |
| `nix run .#apply [<machine>]` | from a site checkout: copy it to that machine and run its own `nixie apply` there; with no machine, this one |
| `nixie update [--check \| --now]` | whether the site repository is ahead of this machine, and apply it; the timer does this by itself (`nixie.updates.mode`) |
| `nixie update --inputs [name…]` | update what the site pins, the platform itself among them, then apply; the other machines follow it as they do any change |
| `nixie notices` | what this machine wants you to know, as the front panel, the control panel, the host page and the desktop show it |
| `nixie secure-boot [--sign] [--at <dir>]` | what the firmware holds, what is staged and what is signed, when a start says "Access Denied"; `--at` reads a machine opened with `nixie disk open` from the installer image, for one that will not start at all |
| `nixie security add-key` | enrol another FIDO2 security key for the disk (a spare); asks for the passphrase, the key's PIN and a touch |
| `nixie disk open [<partition>] [--mount <dir>] [--write]`, `nixie disk close` | open another Nixie disk, on the installer image or another machine, with a security key, the recovery key or the passphrase, its pools under temporary names at `/mnt/nixie` and that disk's boot partition at `/mnt/nixie/boot`, read-only unless `--write` |
| `nixie rollback --json` | every generation, guest and data snapshot and backup as JSON; the History screens read this |
| `nixie hardware scan \| refresh` | compare the machine with `hosts/<name>/hardware.nix`, then rewrite it, commit and apply |
| `nixie hardware add-disk <by-id> [name]` | format and mount a disk the site does not declare; it refuses any that it does |
| `nixie usb [--json]`, `nixie usb allow <vendor:product[/serial]>` | blocked USB devices; allow one in `hosts/<name>/usb.nix` and commit, then `nixie apply` |
| `nixie doctor` | TPM, attestation, Secure Boot, key slots, whether the last unlock needed the recovery key, blocked USB devices, guests, backup check, disk space |
| `nixie export <instance>` | a `guests.nix` entry for a scratch instance |
| `nixie menu` | the desktop menu: finish, wallpaper, packages, update, keybinds |

## One site, several machines

Every machine of a site follows the same git repository (`nixie.site.repo`).
`nixie apply` on one of them commits what you changed, applies it and pushes
it; the others notice and, depending on `nixie.updates.mode`, either say so
or catch up:

| mode | what a machine does when the repository moves ahead |
|---|---|
| `notify` (the default) | says so on the front panel, the control panel, the host page, a desktop notification and at login, and waits for `nixie update --now` |
| `auto` | applies it by itself, then confirms only if `nixie doctor` comes out no worse than before; otherwise the machine puts itself back (`nixie.updates.confirmWithin`) |
| `off` | does not look |

Applying is `nixie apply`, so a change reaches the host and the guests the
site declares in the same step: a server's instances and a desktop's own
configuration follow the same way. `nixie.updates.schedule` sets how often to
look (hourly by default), and a machine that was off looks as soon as it is
back.

The platform travels the same way: `nixie update --inputs` (or the desktop
menu's "Update inputs") updates what the site's lock pins, applies it and
pushes it, and the other machines see a newer site like any other change.

## Rebuild from nothing

What the kit plus the site repository give back, and the order:

1. Install from the ISO (either quick start), cloning the site repository
   on the Name step, and give that step `age.key` from the kit (the
   headless deploy asks for its path) so the secrets the site already holds
   for this machine decrypt again.
2. Put `restic-password` (and `restic-env` or `rclone.conf` if the kit has
   them) back as the site's sops secrets for `nixie.backups`.
3. On the new machine: `nixie apply`, then `nixie restore latest`. Guests
   come back from `guests.nix` with their restored `state/`; `cache/` is
   refetched with `nixie fetch`.
4. `headers/` in the kit restores a damaged LUKS header
   (`cryptsetup luksHeaderRestore <device> --header-backup-file <name>.header`);
   `recovery-key.txt` opens the TPM layer when the TPM cannot. The key from
   setup was shown once and is kept nowhere on the host; after using it,
   `nixie security reenroll` rebinds the TPM and shows a new one.

`nixie backup kit <file>` writes the kit, encrypted with a passphrase you
type; keep it offline. Local ZFS snapshots (`nixie.backups.snapshots`, and
one before every `apply`) cover mistakes on a healthy disk; restic covers
losing the disk.

## Control panel

`https://<host>:8443/ui/` is the Incus daemon serving the panel: instances
with their terminal, files, logs, snapshots and metrics, images, profiles,
networks, storage, operations, dashboards and guest history. Machines lists
every machine in the site, not only the one serving the page, and opens any
other machine's panel; the list is written from `site.nix` by `lib.mkSite`,
so a machine added to the site appears there after the next `nixie apply`.
A browser gets in with a client certificate the daemon trusts; the panel's first page gives
the commands. The gear in the header opens Settings: the finish, the figures
in the header, the time range a browser starts with, which Overview panels
show and in what order and width, the pages in the navigation and extra
links. They are kept on the host for every browser, in the daemon's
`user.nixie.ui` setting, and start from `nixie.ui.theme` and
`nixie.ui.links`
([VERIFICATION.md#a-server-installed-through-the-web-wizard](VERIFICATION.md#a-server-installed-through-the-web-wizard)).
The panel, the installer and the machine's own screens share one set of
tokens and one look: the same three finishes, the same controls, and motion
that stops when the browser asks for reduced motion.

## Console and kiosk

The first text console shows a front panel (`nixie.console.frontPanel.enable`,
on by default); any key opens the normal login. `nixie.console.kiosk.enable`
keeps a kiosk with the control panel behind a lock page on the local display
([docs/console.md](docs/console.md), [VERIFICATION.md#console](VERIFICATION.md#console)).

## Desktop

The desktop profile is a complete Hyprland rice, declared in the site and
switchable at runtime ([docs/desktop.md](docs/desktop.md),
[VERIFICATION.md#slice-r-desktop-rice](VERIFICATION.md#slice-r-desktop-rice)):
a floating bar (mark, workspaces, focused window or playing track, tray,
processor, memory and temperature readouts, network, Bluetooth, volume,
battery, clock), a launcher with app icons and favourites plus file,
calculator, emoji and clipboard modes, a notification centre with
do-not-disturb, a control centre (sliders, toggles, media, the finish
swatches, wallpaper), lists that join a Wi-Fi network, connect a paired
device and set the volume of each playing app, a screenshot menu, a
keep-awake inhibitor, a calendar, OSDs, a tiled power menu, a window
switcher, a wallpaper picker, a keybind cheat-sheet, a themed lock screen,
kitty with a starship prompt and fastfetch. Hyprland is configured
in Lua from `nixie.desktop.*` (`look.gaps`, `look.rounding`, `look.blur`,
`look.animations`, `fonts.ui`, `favourites`, `workspaces.labels` and the
rest); `~/.config/hypr/local.lua` is loaded last. `Super+T` cycles the
finish and `Super+W` the wallpaper for the session with no rebuild;
`nixie.desktop.finish` stays the declared default.

Themes are data. `nixie.desktop.themes` adds finishes of your own from a
handful of colours, and `nixie.desktop.hyde.themes` imports a HyDE theme
directory straight from its own files, so HyDE's themes and wallpapers work
with the Nixie shell, pinned and offline. With `accentFromWallpaper` the
accent follows the wallpaper. If you would rather run HyDE itself,
`nixie.desktop.hyde.enable` (a choice on the installer's Desktop step) brings in
the real HyDE through the hydenix flake and keeps the same installer, security
options and `nixie` command.

## Host page

`nixie.hostUi.enable` adds Cockpit with the files, terminal, storage and
podman plugins, in the same finish as the control panel, behind the
administrator password and the second factor from `nixie.auth.secondFactor`
(TOTP). It is off because it widens the attack surface of a hardened host
([VERIFICATION.md#host-page](VERIFICATION.md#host-page)).

## Extending

Every hook point is an option a site sets: [docs/extending.md](docs/extending.md).
The option reference is generated from the module tree:
[docs/reference/options.md](docs/reference/options.md).

## Architecture

[ARCHITECTURE.md](ARCHITECTURE.md): layout, the option tree, the site
contract, the phase engine, the installer state machine, the desktop shell
choice, and every deviation from the brief with its reason.

## Status

Version 0.1.0, unreleased. By section of the brief:

| section | state |
|---|---|
| 3 platform flake, site flake, template | done |
| 4 option tree | done ([VERIFICATION.md#slice-a](VERIFICATION.md#slice-a)) |
| 5 guests: schema, derivations, declared/scratch, Export | done; Declare from the panel waits for a host agent |
| 6 data and manifest, backups, restore | done; change request: local snapshots, verify, kit, restore beside ([VERIFICATION.md#slice-m-backups](VERIFICATION.md#slice-m-backups)) |
| 11 rollback (change request) | done: generations kept and labelled, `nixie rollback`, `apply --confirm-within`, front-panel rollback ([VERIFICATION.md#slice-n-rollback](VERIFICATION.md#slice-n-rollback)) |
| 7 recovery (change request) | done: recovery key shown once and never stored, unlock falls back to it, `nixie security reenroll`, `nixie usb`, keyboards allowed during setup and reenroll ([VERIFICATION.md#slice-o-recovery](VERIFICATION.md#slice-o-recovery)) |
| 7 security features | done; lockdown integrity is an option that rebuilds the kernel and is documented, not runtime-verified |
| 8 networking, exit-node egress | done for managed-nat; exit-node needs managed-nat by design |
| 9 monitoring and backups | done |
| 10 control panel | done for every screen the brief lists; screens the design does not draw follow its recipes |
| 11 installer: kiosk, LAN, headless, setup generation | done; the headless path is verified through the same phase scripts, not a full kexec run |
| 12.1 server host page | done (TOTP; no passkeys, see ARCHITECTURE D3) |
| 12.2 desktop | done; overview is the shell's window panel (D29); change request: the full rice, Lua config, runtime finish and wallpaper switching, network, device, volume and screenshot menus, system readouts, keep-awake, wallpaper-derived accent, site and HyDE themes ([VERIFICATION.md#slice-r-desktop-rice](VERIFICATION.md#slice-r-desktop-rice)) |
| 13 extension points | done |
| 14 docs, examples | done; the gallery above is regenerated by `nix run .#media` |
| console slice | done |
| showcase slice | done: the gallery comes from media runs, this README is checked |

## Roadmap

- Cluster mode: several hosts in one site sharing guests and storage.
- A native host agent, which would also enable Declare from the panel and
  passkeys for the host page.

## Contributing

`nix flake check -L` must be green before a commit; every VM test has to have
run here. Add a `VERIFICATION.md` entry with what you ran. Comments say why,
never what; nothing hardware- or user-specific goes into the platform.

## License

MIT. Bundled fonts: Archivo and JetBrains Mono under the SIL Open Font License.
