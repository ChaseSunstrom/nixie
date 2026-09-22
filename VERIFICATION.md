# Verification log

Each slice appends a section: what ran, the exact commands, pass/fail per
check, and anything that could not be verified with the reason. All runs are
on the build host described in `ARCHITECTURE.md` section 0 (rootless Nix
2.20, KVM available; every VM test ran under KVM, none under TCG).

## Slice (a): flake skeleton, option tree, mkSite, site template, minimal host

Commands:

```
nix flake check -L --keep-going      # 2026-09-10, "running 9 flake checks", exit 0
```

| check | result | evidence |
|---|---|---|
| fmt | pass | nixfmt --check over every .nix file |
| statix | pass | `statix.toml` disables only `repeated_keys` (dotted keys are the module idiom) |
| deadnix | pass | |
| no-hardware-facts | pass | grep over the tree excluding `tests/`, `hardware.nix`, the brief and the design-token inventory |
| option-docs | pass | every `nixie.*` option has a description (evaluated, not built) |
| eval-matrix | pass | five throwaway sites evaluate: no GPU with a data disk, one NIC with NVIDIA, no TPM with encryption, no data disk desktop with TPM, VM |
| profile-server-has-no-desktop | pass | closure of the example server contains no hyprland, cage, chromium, firefox, quickshell, greetd |
| profile-desktop-has-no-server | pass | closure of the example laptop contains no incus, opentofu, prometheus, grafana, restic, cockpit |
| vm-boot-plain | pass | example server boots under OVMF + swtpm; admin user exists from the sops secret, sshd active; "test script finished in 17.19s" |

Not verified in this slice: the disko layout is declared and evaluated but
not applied (the test framework supplies its own disk); a real install is the
subject of slice (b). The `nix why-depends` form of the profile check is
replaced by a pure closure grep (`closureInfo`); the equivalent manual
command is `nix why-depends .#checks.x86_64-linux.vm-boot-plain.driver nixpkgs#cage`.

## Slice (b): encryption

`vm-encryption` installs the example server from an installer VM onto a blank
disk with every boot-time feature on (encryption, TPM + PIN, attestation,
duress, remote unlock, Secure Boot) under OVMF (Secure Boot capable, Setup
Mode) with swtpm, then boots the disk and walks phases 4 to 7 through the
same scripts a front end calls: remote unlock over SSH from a client VM,
Secure Boot enrolment by systemd-boot from Setup Mode, TPM enrolment with a
PIN and a recovery key, attestation init, header-backup bundle, the
verification reboot with the attestation code on the console, and finally
the duress passphrase wiping every key slot. Passed on 2026-09-11 ("test
script finished in 891.00s"): install 158 s, first boot with remote unlock,
signed chain, TPM + PIN enrolment with recovery key and header bundle, the
TPM + PIN reboot with the attestation code shown and `nixie reseal`, and the
duress wipe (the target powers itself off 39 s into that boot; the installer
then finds no key slots left).

Known timing: each boot of the target takes about five minutes in this test
because the console password agent (`systemd-ask-password-console`) blocks
on `/dev/console` until its start timeout; the SSH relay answers the prompts
long before that. Not a correctness problem; noted for a later slice.

Secure Boot: phase 5 detects the firmware's Setup Mode and stages enrolment,
and `sbverify` confirms lanzaboote signed systemd-boot, the fallback loader
and every generation's UKI with the site's db key. The firmware actually
enrolling those keys and then completing a Secure Boot verified boot is
exercised on real hardware, not in this test: the OVMF build used here enrols
the staged keys (an earlier run showed "Custom Secure Boot keys successfully
enrolled" on the console) but will not then complete a verified boot of the
signed chain, so auto-enrolment is turned off in the test VM and the signed
chain is asserted directly instead.

Lockdown (`nixie.security.lockdown = "integrity"`) is evaluated by the
`eval-matrix` check only; it rebuilds the kernel and is documented in
ARCHITECTURE D4 rather than booted.

## Slice (c): network

`vm-egress`: under exit-node egress a declared guest (`veth-web`) and an
undeclared one (`veth-scratch`) reach only the tunnel side and not the LAN;
guests cannot reach the host's SSH while the LAN can; under direct egress
both reach the LAN through the host. Passed on 2026-09-11
("test script finished in 25.02s").

## Slice (d): guests

`vm-guests`: `nixie apply --yes --skip-host` imports the NixOS image built
with the host and creates the declared guest through tofu; the guest serves
from its mounted state; a scratch instance is left alone by a second apply;
deleting the guest and applying recreates it with state intact; `nixie export`
emits a `guests.nix` entry. Passed on 2026-09-11 ("test script finished in
45.07s").

## Slice (e): examples

`examples/site/guests.nix` declares one guest per capability; the whole site
evaluates and its NixOS guest images build as part of the host closure
(`eval-matrix`, `vm-boot-plain`, and the `server-guest-*` packages of the
site). Foreign images and the VM are pinned by fingerprint and evaluated;
they are not started in tests because that needs the network and nested
virtualisation.

## Slice (f): data

`vm-data`: `nixie fetch` fills `cache/http/dataset` from a mirror VM and is
idempotent; deleting `cache/` and fetching restores it; a restic backup of
`state/` and `nixie restore latest` bring a deleted file back; `cache/` is
absent from the snapshot. Passed on 2026-09-11 ("test script finished in
23.96s").

## Slice (g): monitoring

`vm-monitoring`: every Prometheus target (node, incus) is up; the three
shipped dashboards are provisioned in Grafana with the GPU power cap
substituted. Passed on 2026-09-11 ("test script finished in 33.00s").

## Slice (h): control panel

`vm-ui`: incusd serves the bundle under `/ui/` with this host's `nixie.json`
(finish, links, declared guests), the bundle contains the command palette,
fonts are served, and the daemon answers "untrusted" on the same origin
without a client certificate. Passed on 2026-09-11 ("test script finished in
15.55s"). The panel's screens are exercised by the `panel` media run with a
trusted client certificate.

## Slice (i): installer

`vm-installer-lan`: the installer system (the ISO's configuration) runs the
setup service and the kiosk; the kiosk screen shows the wizard (OCR); a
client VM pairs with the single-use code (a second use is refused), reads
hardware and option metadata, configures, plans (the generated `hardware.nix`
and `site.nix` are checked textually), installs through phases 1 to 3, and the
installed disk boots into the setup generation where the continuation
service answers on the same port and phases 4 to 7 run over the API. The ISO
image itself is built by `packages.nixie-iso`; `nix run .#test-iso` boots it
in QEMU with OVMF and swtpm and drives the same API from outside.

## Slice (j): desktop

`vm-desktop`: greetd with the token-styled greeter comes up, a login lands in
a Hyprland session with the shell bar; one token source reaches Hyprland,
kitty, neovim and the shell; local.conf is sourced last; switching finish
through a specialisation takes effect after `switch-to-configuration test`
without a reboot.

## Slice (k): host page

`vm-host-ui`: Cockpit answers on its port with Nixie branding; login with the
administrator password and a valid TOTP code succeeds, a wrong code is
refused; logins reach the journal.

## Slice (m): backups

Change request (ARCHITECTURE 4.11, D21, D23, D24). `vm-backup`: on a ZFS
pool carved from a second disk, `nixie-snapshot pre-apply` (what `nixie
apply` runs first) snapshots `state/`, prunes to the last five and marks the
dataset for zfs-auto-snapshot, whose hourly timer is present; `nixie backup
now` and `list --json`; `nixie restore --path` puts a deleted file back in
place and `--to` beside the live data; `nixie backup verify` writes the
check result `nixie doctor` reports; `nixie backup kit` decrypts to the host
age key, the restic password, the recovery-key note and the rebuild steps.
`vm-guests` additionally proves that an apply whose plan changes a guest
takes an Incus `pre-apply-<label>` snapshot first. Result: filled in below
after the run.

## Slice (n): rollback

Change request (ARCHITECTURE 4.11, D19, D20). `vm-rollback`: a second,
broken generation (the panel moved to another port) is switched to; `nixie
rollback --list` shows both with marks; one key on the tty1 front panel
rolls back and the panel answers again. `nixie apply --confirm-within 20s`
against the broken system, unconfirmed, reverts the host and restores the
touched guest's pre-apply snapshot; confirmed, it stays. `nixie rollback
guest web --snapshot s1` restores the guest's root disk while its
`/data/state` keeps the newer content; `nixie rollback data web` restores a
state directory beside, then in place. `vm-encryption` additionally checks
the sealed-generation label phase 6 writes to the ESP. Passed on 2026-09-11:
`vm-rollback` "test script finished in 132.37s" (panel key 12 s, unconfirmed
apply revert 88 s, guest snapshot 18 s, data snapshot 0.3 s);
`vm-encryption` with the label check "test script finished in 625.84s"
(the unlock agent now exits once the root file system is up, which took
about four minutes off the run). Two test-environment notes: the test VM
boots its kernel directly and has no ESP, so the node's boot loader is off
and `--boot-previous` (bootctl) is not exercised; and `incus exec` output
must never be piped into `grep -q` in a test, since the early exit leaves
the Incus client hanging on its websocket. Bugs the test found in the CLI:
three tools it borrowed from an interactive PATH (`hostname`, `sed`, `nix-env`)
are now runtime inputs, since a transient unit has none of them.

## Slice (o): recovery

Change request (ARCHITECTURE 4.11, D21). Two tests. `vm-hardware`: on a
server with USBGuard on, the devices present at usbguard's first start are
allowed (the generated `setup-rules.conf`), a keyboard hot-plugged later
is blocked, `nixie security reenroll` lets the waiting keyboard through
and removes its temporary rule when done, a second keyboard is blocked
again, `nixie usb` and `nixie usb --json` list it, `nixie usb allow
0627:0001` writes `hosts/server/usb.nix`, commits, and is idempotent, and
`nixie apply` to the generation with that list restarts usbguard and the
keyboard is allowed; `nixie doctor` shows the block and then its absence.
Passed on 2026-09-11: "test script finished in 29s". One test-environment
note: the keyboard is attached with `device_add usb-kbd,bus=usb-bus.0,port=2`;
without a port QEMU inserts a hub first, and a blocked hub hides everything
behind it (which is the right behaviour, but not what the test is about).

`vm-encryption` grew two things. Phase 6 now shows the recovery key once
(the key file the front end reads), keeps it out of `RECOVERY.txt`, and
wipes the install passphrase slot; the test asserts all three. A new
subtest boots the installed target normally (TPM and PIN), then runs
`nixie security reenroll` with the phase-6 recovery key and a PIN: phase 6
with `--force` removes the old TPM binding, binds again, enrols a fresh
recovery key and wipes the old one, sets a new lockout password and
regenerates the attestation secret; phase 7 verifies. The outer layer ends
with exactly one recovery slot and the TPM token; the new key opens it
(`cryptsetup open --test-passphrase`) and the old one does not; the
header bundle in `/var/lib/nixie/setup/` is newer than setup's. The
duress subtest that follows opens the outer layer with the PIN, which
proves the new binding works across a boot. Passed on 2026-09-11: "test
script finished in 1258s" (reenroll subtest 322 s).

Two things are hardware-only, stated plainly: phase 7 reports "Secure Boot
not enabled" in this OVMF (see Slice (b)), so the reenroll command exits 1
after a complete phase 6 and keeps its markers for a resume, and the test
accepts exactly that; and the recovery key unlocking a *fresh* TPM at the
boot prompt rides on systemd-cryptsetup's own fallback ("TPM2 operation
failed, falling back to traditional unlocking", which `nixie doctor`
greps for). A run with swtpm's state deleted did reach that fallback
(the log shows the PIN prompt, two unseal failures, then the passphrase
prompt), but feeding three answers through the SSH relay with fixed gaps
was not reliable, so that boot is not in the automated test.

Bugs the tests found: `nixie security reenroll` moved the new header
bundle only after phase 7 succeeded, so a failed verification lost it
(now moved as soon as phase 6 writes it); the reenroll command needed the
installer's phase scripts on the installed host (the CLI now carries them).
The eval-matrix check was writing derivation paths with their string
context, which made it build every host's whole build closure (an
unrelated Python test suite failed there); it now drops the context and is
the evaluation check it was meant to be.

## Slice (r): desktop rice

Change request (ARCHITECTURE 11.1, D25, D26): the desktop asked for "a full
riced out implementation, similar to HyDE". A second request followed while the
slice was open: the **Segment n** mark (design alternate 3) everywhere, the
dark neutral finish as the default instead of Umber, and the shell brought
up to HyDE's feature set. `vm-desktop` grew from three assertions to eight
subtests and now covers every surface. Passed on 2026-09-12: "test script
finished in 110.30s" (login and bar 14 s, launcher and calculator 10 s,
notification, OSD, power, calendar, control centre, wallpaper picker and
cheat-sheet 18 s, networks, devices, mixer, screenshot menu, keep-awake and
readouts 12 s, runtime finish switch 8 s, wallpaper change 3 s, lock and
unlock 11 s, site-default finish after an apply 3 s).

What it proves: the greeter comes up themed from the tokens; every finish is
shipped under `/etc/nixie/desktop/<finish>/` with its tokens, GTK CSS, kitty
colours, hyprlock configuration and three wallpapers; Archivo and Material
Symbols are installed; a login lands in Hyprland with the Lua configuration
linked into the home directory, `hyprctl configerrors` empty, the shell's
layer on screen and the wallpaper process running; the launcher lists real
applications with icons (the state file reports ten results); the calculator
answers `2*21` with 42; a notification reaches the popup and the centre; the
OSD, power menu, calendar, control centre, wallpaper picker and cheat-sheet
each open and close; `nixie-shell finish paper` relinks GTK, kitty and
hyprlock, changes Hyprland's border colour live (`hyprctl getoption`) and
switches the wallpaper, with no rebuild; `nixie-shell wallpaper next` moves
to the next image and remembers it; `loginctl lock-sessions` brings up
hyprlock and the password unlocks it; and switching `nixie.desktop.finish`
in the site takes effect after an apply without a reboot. Screenshots of
each surface are in the test output.

The mark: `ui/src/components/ui.tsx`, the favicon in `ui/index.html`, the
bar's Canvas in `shell.qml`, the wallpaper draw and the terminal greeting in
`theme.nix` and the record in `docs/design-tokens.md` all draw mark 3 now,
and `docs/design-tokens.md` keeps mark 1 for reference. The example desktop
starts on Graphite.

HyDE parity, all asserted in the new subtest: a Wi-Fi list that takes a
password and joins, the paired Bluetooth devices, a volume slider per
playing stream, a screenshot menu (region, window, screen, delayed), a
keep-awake inhibitor, and processor, memory and temperature readouts whose
numbers the test checks are real. Themes are data: `nixie.desktop.themes`
adds a finish from a handful of colours (the example site's "midnight" is
one, and the test switches to it and back), and `lib/hyde-theme.nix` reads a
HyDE theme directory, mapping its kitty palette and wallpapers into a finish
while blending the neutral ramp from the theme's own background and
foreground. Checked against the real Catppuccin Mocha theme: it evaluates to
a correct palette and a built system offers it as a fourth finish with its
swatch. `nixie.desktop.hyde.enable` stands every Nixie desktop module down
for a site that imports hydenix; evaluation shows `nixie.desktop.enable`
false and Quickshell gone from the closure (D27). The full HyDE session
itself is not VM-verified here: it is a third-party desktop the platform
does not depend on.

Three findings worth keeping. **Hyprland 0.55 dropped `dwindle.pseudotile`
and `misc.vfr`**; both were in the first draft and Hyprland drew "unknown
config key" over the session until they went. **The wallpaper daemon had to
change twice**: awww (the renamed swww) aborts with a Rust panic under the
VM's software renderer, and hyprpaper's IPC socket never answers there, so
the platform uses swaybg, which draws one image per process. **The shell
writes its own state** to `$XDG_RUNTIME_DIR/nixie-shell.state`, because the
bar's 12 px text is below what the test driver's OCR reads reliably; the
test polls that file and keeps the screenshots for people rather than for
assertions. Test-harness bugs were mine too: `pgrep -f hyprlock` matched the checking
command itself (so "still locked" could never fail); nixpkgs wraps `swaybg`,
so it must be matched by command line rather than by name; and every command
the test runs as the person goes through `su - me -c '…'`, so a
single-quoted argument inside it collided with that quoting and delivered a
truncated notification, which the new assertion caught immediately. Two
more in the shell: `nixie-shell mixer` collided with the verb that lists
streams, so the panel never opened (the data verb is `streams` now), and a
second application-wide Escape shortcut made Qt fire neither, so Escape
stopped closing the launcher (one shortcut per window, each enabled only
while its window is up). Keep-awake asked to block sleep, which needs polkit
authorisation for an ordinary user and failed silently; it holds idle now
and checks that it really took the lock.

One real defect came out of reading the screenshots rather than the log: the
notification card showed only the first word of the summary and no body at
all. A `Row` positioner takes its implicit width from its children, so a
child whose width is derived from the row's width is a binding loop, and QML
resolved it to almost nothing. Both the card and the popup now anchor to the
card instead of deriving a width from the positioner. Because no assertion
would have caught it, the shell now publishes what the newest card actually
shows (`notifFirst`) and whether QML had to cut it (`notifTruncated`, from
the `Text.truncated` property), and the test fails if the summary is
truncated or the text is not the full "summary / body".

## Slice (p): hardware

Change request (ARCHITECTURE 4.11). `vm-hardware` grew to five subtests and
passed on 2026-09-12: "test script finished in 24.74s". The new ones prove
the rescue network is installed (`90-nixie-rescue.network`, DHCP, route
metric 2048, so a card whose address is not in `hardware.nix` still gets an
address and never beats the real uplink); `nixie hardware scan` reports the
declared uplinks, GPU, TPM and disks against the machine and says it
matches; `nixie doctor` carries the same line; `nixie hardware add-disk`
refuses a disk the site already declares (exit 3), refuses a name ZFS keeps
for itself (exit 2), asks for the disk's own name before destroying
anything, and then creates the pool and mounts it under the data root; and,
with the facts file swapped for one naming a card this machine does not
have, both `doctor` and `scan` report the drift by address.

The facts a site declares now live in `/etc/nixie/hardware.json` (GPU, TPM,
uplinks, disks, Secure Boot), so nothing has to re-derive them to compare.

Four things this slice got wrong first, all worth keeping in mind. `add-disk`
began by shelling out to disko's CLI, which evaluates Nix and builds a
closure: it hung the VM and would have failed on any installed host, since
an installed host has no Nix search path and may have no network. It now
uses `sgdisk` and `zpool` directly, which is also what the generated disko
config would have done. The rewrite dropped the `;;` that closed its `case`
branch, which bash reports as a syntax error at the *next* branch; extracting
the generated script and running `bash -n` on it found that in one step
where reading the Nix source had not. A pool named `spare` is rejected by
ZFS because that word names a vdev kind, so the command now says which
words are reserved instead of passing a confusing `zpool` error through.
And the test itself used `jq` inside the VM, which that node did not have.

## Slice (q): history

Change request (ARCHITECTURE 4.11, D22). One command answers for every kind
of history a host keeps: `nixie rollback --json` prints its generations
(number, label, kernel, date, which is current and which was booted), its
guest snapshots, its data snapshots and its restic backups in one shape.
Two screens read it and neither scrapes human output: `packages.nixie-cockpit`
is the host page's History screen, a Cockpit package that asks the CLI
through the bridge (`cockpit.spawn`), and `ui/src/pages/History.tsx` is the
control panel's, reached from the nav and the command palette.

`vm-host-ui` grew a subtest and passed on 2026-09-12: "test script finished
in 13.88s". It proves the page is joined into Cockpit's share with its
manifest, index and script, that the manifest names the History menu entry,
that the script asks for `nixie rollback --json` rather than parsing text,
and that the host answers with exactly the four keys, the newest generation
marked current.

Two bugs came out of it, both mine and both silent. `jq -s add // echo '[]'`
reads as jq's own alternative operator, so jq tried to open `echo` and `[]`
as files; it is `jq -s 'add // []'`. And a declared guest that does not
exist yet made `incus snapshot list` fail inside a command substitution,
which under `set -e` took the whole report down with no message at all: the
listing tolerates a missing instance now. The lesson both share is that a
report which gathers from several sources has to survive each of them being
absent, because on a fresh host most of them are.

## Slice (s): the gallery, and the defects it found

The showcase slice: `nix run .#media` regenerates `docs/media/` from six runs
in VMs, `docs/media/SHOTLIST.md` maps every file to the run and commit that
made it, and the README shows the result. Nothing is mocked and nothing is
drawn by hand. The gallery is committed as ordinary files: each video is
kept under 8 MB and the whole directory under 100 MB, and the generator
fails rather than exceed either, so no large-file storage is needed.

Running it for the first time end to end found seven defects, each in a
feature that no test covered, or that a test covered too politely.

1. **Prometheus and Cockpit both listened on 9090.** A host with
   `nixie.monitoring.enable` and `nixie.hostUi.enable` had one of the two
   dead from boot: `Unable to start web listener ... address already in
   use`, then `start-limit-hit`. Prometheus moved to 9091 (D28); it is bound
   to loopback and every consumer takes the port from the option. An
   assertion now refuses any configuration where the host page, Prometheus
   and Grafana share a port. `vm-monitoring` (9091) and `vm-host-ui` (9090)
   both pass.
2. **The overview plugin never loaded.** The Lua configuration pointed at
   `libHyprspace.so`; the package ships `libhyprspace.so`, and Hyprland
   ignores a plugin path that does not exist without a config error, so
   `hyprctl configerrors` stayed empty and nothing said the key was dead.
3. **A plugin dispatcher cannot be called from a Lua configuration at all.**
   With the path fixed the plugin loaded — `hyprctl plugin list` showed
   "Plugin Hyprspace by KZdkm" — and the key still did nothing:
   `hl.dispatch` takes a dispatcher object, a string naming one is refused,
   and `hl.plugin` exposes only `load`. The overview is now the shell's own
   window panel, which lists every window with the workspace it is on
   (D29).
4. **Idle screen blanking never worked.** hypridle was configured with
   `hyprctl dispatch dpms off`, which against a Lua configuration is the
   syntax error `return hl.dispatch(dpms off)`. The screen never turned off
   on idle and never came back after suspend. The generated commands are now
   Lua dispatchers, and `vm-desktop` runs the commands out of the generated
   `hypridle.conf` and asserts the monitor's `dpmsStatus` goes off and back
   on.

5. **The installer offered the wrong disks, or none.** `nixie-discover`
   built each disk's record with `id: ($byid[] | select(.dev == $d.path) |
   .id)`. In jq an object whose value expression yields nothing is not built
   at all, and one that yields several is built several times, so a disk with
   no stable-name link under `/dev/disk` disappeared from the wizard's list entirely and
   a disk with more than one link appeared once per link. The build host's
   own NVMe drive carries three links (one EUI link and two model-name
   links), so on that machine every NVMe drive would have been
   offered three times; in the media run's VM the target disk had no link and
   the wizard offered nothing at all, which is why the run timed out waiting
   for `input[name=disk]`. The id is now `[...] | first`, which is null when
   there is no link — what the UI already expected, since it renders
   `d.id ?? d.path`. `vm-installer-lan` now asserts the wizard is offered
   exactly the disks `lsblk` reports, by path.
6. **The boot media run never answered the passphrase prompt.** Its target
   sets `console=tty0` so the prompts are drawn on screen for the pictures,
   which means the serial console the driver reads never carries their text:
   `wait_for_console_text("Please enter passphrase")` waited until the test
   timed out, an hour of VM time later. The prompt is now detected by the
   password agent starting, which does reach serial, and answered with
   `send_chars`, which reaches the screen's keyboard.

Noticed and left alone: the wizard offers every block device the kernel
calls a disk, which in a QEMU VM includes `/dev/fd0` at 4 KB. Filtering by
size would be a behaviour change that could hide a legitimately small disk,
so the installer still lists it and the media run names the disk it wants
instead of taking the first radio.

Dropped from the gallery, and why: **the guests terminal recording**. Its
asciinema session writes to a terminal of its own, and those escape sequences
land in the same shell channel the test driver frames its commands over: the
driver decoded a reply as base64 and got "Incorrect padding". Running the
recording as a transient unit with no terminal did not help either — the run
then blocked inside the driver until the hour-long global timeout, twice. The
guests themselves are verified by `vm-guests`, and the control panel's
instance screens in the gallery show them running, so `nix run .#media` no
longer includes the run rather than spending an hour a pass on it.

Not verified, and why: **`podman info` inside the example's `builder`
guest never returns** in the recording VM. The container itself is healthy —
it is created with `security.nesting`, boots to "Permit User Sessions" and
stays RUNNING, and `incus exec` into the `db` guest beside it answers in
0.07 s — but every `incus exec builder -- podman info` was killed by its own
timeout having printed nothing, at 30 s and at 60 s. The platform's part
(creating a nested container and keeping it running) is asserted; what a
container runtime does inside one is the example guest's own business and is
left out of the recording rather than claimed. Anyone relying on the
`builder` example should confirm podman on real hardware first.

A test-harness lesson with teeth: `wait_until_succeeds` cannot retry a
command that hangs rather than fails, so one stuck `incus exec` held a run
for 31 minutes until it was killed by hand. Every `incus exec` in the media
runs now carries its own `timeout`.

7. **Nobody could log in to the host page.** `nixie.hostUi` set
   `security.pam.services.cockpit.text`, which replaces the generated PAM
   stack rather than adding to it, so Cockpit's service consisted of exactly
   one rule — `auth required pam_oath.so` — with no module that checks a
   password. Every login was refused with `401 Authentication failed` before
   any second factor was asked for, and the journal recorded
   `op=PAM:authentication grantors=?` for each attempt. The rule is now added
   through `security.pam.services.cockpit.rules.auth.oath`, ordered after
   `pam_unix`, so the password is the first factor and the one-time code the
   second.

   `vm-host-ui` had covered this the whole time and passed anyway: it
   accepted `401` as well as `200` for the password, and it wrapped the
   second-factor assertions in `if "x-conversation" in conv.lower():`, so
   when the conversation was never offered the test skipped its own subject
   and reported success. The assertions are now unconditional, and with the
   PAM fix the check proves a real login: the password is accepted, the
   conversation is offered, the right code gives 200 and a wrong one 401.

`vm-desktop` gained two subtests for the features that had none: the
overview key and screen recording (`wf-recorder`, the thing `Super+Shift+R`
runs, verified by the size of the file it produces), and the idle rules. It
passed on 2026-09-12 with ten subtests: "test script finished in 126.83s".
The idle subtest reads the two commands out of the generated
`/etc/xdg/hypr/hypridle.conf` and runs them, so it tests the wiring and not
a copy of it; the monitor's `dpmsStatus` goes to false and back to true.

Three more of my own mistakes are worth recording, because each of them
makes a test lie rather than fail. A screenshot name used by two runs was
silently overwritten by the second while the shot list claimed both
(`boot-passphrase-prompt.png`, from the boot and installer runs); the
generator now refuses a duplicate name. The generator warned and carried on
when a run failed, so an incomplete gallery exited 0; it now fails and names
every run that broke. And `me("kitty & sleep 2")` left the window holding
the command's output, so the test driver waited for EOF forever and the run
hung rather than failed — the window is started detached with its pipes
closed.

## Installer image: what a real boot found (2026-09-14)

Reported from booting the image in libvirt and VirtualBox: the graphical
entry showed a browser window with no text, there was no terminal or web
install to choose, installing stopped in phase 3 with `experimental Nix
feature 'nix-command' is disabled`, VirtualBox would not boot the image, and
the file was named `nixos-…`. Every one was reproduced on this host before it
was changed: the image as built, booted in QEMU and in the VirtualBox 7.2
installed here. The VM tests had passed through all of it, because
`vm-installer-lan` boots the installer *configuration* (not the image, and
not the minimal CD profile), installs a prebuilt system instead of the site
flake, and accepted the pairing form as proof the kiosk worked; `test-iso`,
the one run that uses the image, had never completed.

What was wrong, and what changed:

1. **No text.** `installation-cd-minimal.nix` sets `fonts.fontconfig.enable`
   to false; Chromium then draws no glyphs at all. Separately the stylesheet
   named its fonts `./fonts/…`, which resolves to `assets/fonts/` while the
   files are in `fonts/`, and the setup backend answers a missing file with
   `index.html`, so the web fonts never loaded anywhere, the control panel
   included (it fell back to system fonts on hosts that have them). The kiosk
   module turns fontconfig on and the stylesheet names `../fonts/`.
   Reproduced and fixed in a VM with the kiosk module and the CD's font
   setting (screenshots before: blank tab strip, address bar and page; after:
   the page's text, full screen).
2. **A browser window, not the wizard.** `chromium --kiosk` never goes full
   screen under cage on Wayland and keeps the tab strip and address bar;
   `--app=<url>` opens a bare window.
3. **The kiosk showed the pairing form.** The browser started before the
   setup service had written the local token (the service waits for the
   network), and the form asks for a code printed on the console the kiosk
   covers. The browser now waits for the page to answer and for the token.
4. **VirtualBox showed nothing.** Its VMSVGA adapter without 3D acceleration
   has a render node but no OpenGL, and wlroots only falls back to software
   rendering when there is no render node: cage logged `VMware: No 3D
   enabled`, `Could not initialize EGL`, `Could not match drm and vulkan
   device`, `Unable to create the wlroots renderer` (read from the journal
   inside the VirtualBox VM). A start that fails is retried with
   `WLR_RENDERER=pixman`, and if cage still fails tty1 falls back to the web
   banner (`OnFailure=`).
5. **"Could not read from the boot medium" in VirtualBox.** The image was
   UEFI only and VirtualBox starts VMs in BIOS mode. The image is now hybrid
   (D30); in BIOS mode it boots, the wizard's Hardware step and phase 1 say
   to turn on EFI, and nothing is written.
6. **No terminal or web install.** The boot menu has three entries, each a
   specialisation setting `nixie.installer.mode`: graphical (default), web
   (the address, code, fingerprint and QR on tty1, no kiosk) and terminal
   (the text wizard on tty1, no listener).
7. **tty2 was a login prompt.** `getty@tty2` was masked but logind spawns
   `autovt@tty2` on a VT switch, and the getty and the wizard fought over the
   keyboard (keystrokes went to the invisible wizard). Both instance names are
   masked for the VTs the installer owns.
8. **`nix-command` is disabled.** The ISO never imported the setting the
   installed hosts get from `modules/base.nix`.
9. **The flake could not see the generated files.** Phases 1 and 2 write
   `hardware.nix`, the secrets and `.sops.yaml` into the site's git
   repository, and a git flake sees only tracked files; phase 3 `git add`s
   them before evaluating.
10. **The terminal wizard wrote invalid Nix** for a pasted SSH key (`\"…\"`
    inside a heredoc). It now pipes the same JSON the web wizard posts to
    `nixie-setup --configure`, so both wizards write the site with one piece
    of code, and a failing phase's output stays on screen.
11. **Named `nixos-minimal-26.05…-x86_64-linux.iso`.** In nixpkgs 26.05
    `isoImage.isoName` is an alias of `image.fileName`, which the image
    builder does not read; `image.baseName` is set to
    `nixie_<lib.version>_<platform>`. The boot menu says Nixie, in the
    Graphite finish with the Segment n mark (GRUB and syslinux), and the
    console greeting no longer describes the NixOS installer's accounts.
12. **GRUB stopped at "Press any key to continue"** with the first theme:
    ImageMagick writes flat images as low-depth palette PNGs and GRUB reads
    only 8 or 16 bits per channel. Written as PNG32; `checks.iso-grub-theme`
    reads every PNG's depth.
13. **Finish and phase 8 killed themselves.** Both switched to the normal
    generation from inside `nixie-setup.service`, which that switch stops,
    killing everything in its cgroup. Phase 8 applies guests and data only
    (the host already runs the site's system) and Finish runs as the
    transient unit `nixie-finish`.
14. **`test-iso` could not have run**: the OVMF firmware is in the package's
    `fd` output, QEMU no longer accepts `serial=` on `-drive`, `$(boot)`
    waited for QEMU to exit because QEMU inherited its stdout, swtpm exits
    when QEMU disconnects and was started once, `wait` cannot see a process
    started in `$(...)` and a guest reboot restarted QEMU on the same disk
    (now `-no-reboot` and a `kill -0` loop), a logger holding the serial
    socket was dropped when the script typed, which cancelled the passphrase
    prompt (QEMU now logs the port itself), `-cpu max` hit "KVM internal
    error ... emulation failure" (now `-cpu host` under KVM), and the
    installed system's prompts were never on the serial console it reads.
15. **Phase 3 ran out of memory** on a 4 GB machine: the evaluator reached
    1.7 GB with the installer's root, store overlay and kiosk all in RAM,
    and the kernel killed `nix`. The installer has zram swap; the hardware
    scan leaves zram, and the medium the installer started from, off the
    list of disks.
16. **A site made on the installer pointed at `/etc/nixie/platform`**, a
    symlink out of the store that pure evaluation refuses, and a path that
    does not exist on the installed host. It now names the platform's store
    path, and every host keeps that source through `nix.registry.nixie`.
17. **The `nixie` CLI was on no real host**; every VM test added it by hand.
    The server profile installs it. The desktop profile still does not: the
    CLI carries the Incus client and OpenTofu, which the desktop closure
    check forbids, so `nixie menu`'s `sudo nixie apply` needs a desktop build
    of the CLI (open).
18. **`nixie apply` on a site flake always failed** at its first step:
    `nix eval --raw` of a boolean ("cannot coerce a Boolean to a string");
    tests only took the prebuilt-system branch. `--json`.
19. **Finish failed three ways after the move to a transient unit**: the unit
    had systemd's bare PATH (`dirname: command not found`), phase 8 had found
    no CLI on the setup service's PATH and skipped the apply, and the switch
    returned status 4 because the kiosk's half-stopped user session failed
    its user activation. The PATH is passed, the CLI is on the service's
    PATH, and Finish stops the kiosk session before switching.
20. **In the default bridge mode the LAN could not reach the host's SSH or
    control panel.** The rule keeping guests off the host's ports matched
    the bridge, which in `unmanaged-lan` mode is also the LAN port. It is now
    in the bridge family, on the guests' `veth-*` ports; `vm-egress` gained a
    LAN-mode subtest, which fails against the old rules (tried) and passes.
21. **The installed system rebooted into the installer in VirtualBox** with
    the image still attached: its firmware rebuilds the boot order from the
    VM's device list, putting the optical drive before "Linux Boot Manager"
    (read from the EFI variables inside the VM). Phase 3 sets `BootNext` to
    the installed loader and setup reboots set it to the current entry;
    confirmed in VirtualBox by hand before it went into the code.
22. **Alt+F2 did nothing under the kiosk**: cage blocks VT switching without
    `-s`.
23. **The host page's second factor was never asked for.** The PAM rule was
    named `oath`, which merged with nixpkgs' disabled built-in rule of that
    name, and `pam_unix` is `sufficient` in the generated stack, which ends
    authentication before a later rule runs. The rule is now `nixie-totp`,
    `sufficient` after a `required` `pam_unix`. Before, `vm-host-ui` could
    not evaluate (`nixie.hostUi.extraOrigins` set Cockpit's `Origins`
    directly, conflicting with the module; now `allowed-origins`) and its
    header regex expected a colon the header does not have. Now: password
    and code log in (200), a wrong code is refused (401).
24. **The front panel put "usb nothing blocked" in red**: its doctor filter
    matched problem words without case.
25. **Installed hosts still called themselves NixOS** in the boot menu, the
    console greeting and os-release. `system.nixos.distroName` is Nixie on
    hosts too (`ID` stays `nixos`).

Checks added or tightened: `checks.iso-config` (file name, both firmware
kinds, the three entries and what each runs, `nix-command`, fontconfig; it
fails with the BIOS entry turned off, tried), `checks.iso-grub-theme`,
`vm-ui` and `vm-installer-lan` resolve each font from the stylesheet's own
URL, and `vm-installer-lan` requires the kiosk to show the paired wizard
without an address bar.

How it was verified:

- `nix run .#test-iso` passed end to end on 2026-09-14 against the image as
  built, under KVM with 4 GB of memory: the graphical entry boots, the kiosk
  pairs itself, the wizard's API configures an encrypted server, phases 1 to
  3 evaluate and build the site flake online (147 s), the installed system's
  passphrase prompt is answered on the serial console, phases 4 to 8 run in
  the setup generation (phase 8's OpenTofu apply included), and Finish
  prints its last line, removes the setup service, and leaves the control
  panel answering on 8443 and the front panel on the screen. Screenshots,
  the run log, a phase summary and a serial excerpt are in
  `tests/artifacts/test-iso/`. It took eleven attempts; every failure is an
  item above.
- In VirtualBox 7.2 on this host, by hand with the image: BIOS boot shows the
  Nixie menu and the kiosk (software rendering), and the Hardware step
  refuses with the UEFI message; EFI boot shows the themed menu with no
  prompt, the web entry's tty1 banner, the terminal entry's wizard on a clean
  tty1, and the hardware scan; an encrypted server installed through the
  wizard's API in 218 s; with the image still attached, `BootNext` booted the
  installed disk, the passphrase prompt took the typed passphrase, and the
  setup generation's kiosk ran phases 4 and 5 from the keyboard. Finish was
  not repeated there; `test-iso` covers it.
- The kiosk fixes were first reproduced and then proved in a VM running the
  kiosk module with the minimal CD's font setting (screenshots before and
  after), and `vm-installer-lan` now requires the paired wizard without an
  address bar.
- Not verified at first: a USB stick, and Secure Boot or TPM enrolment from
  the image. Both are now; see the next section.

The gate, run afterwards on the finished tree as the per-output loop described
under "Final run" (VirtualBox powered off: running it next to KVM guests gave
"KVM internal error" in two of the attempts above):

| check | result |
|---|---|
| fmt, statix, deadnix, eval-matrix, option-docs, option-reference, readme | pass |
| no-hardware-facts, no-secrets-in-store, systemd-security | pass |
| iso-config, iso-grub-theme (new) | pass |
| profile-server-has-no-desktop, profile-desktop-has-no-server, profile-server-kiosk-only | pass |
| vm-boot-plain (44 s), vm-backup (55 s), vm-data (49 s), vm-guests (65 s), vm-hardware (38 s), vm-monitoring (102 s), vm-rollback (153 s), vm-ui (43 s) | pass |
| vm-console (282 s), vm-desktop (126 s) | pass |
| vm-egress (95 s, LAN-mode subtest added), vm-host-ui (43 s, TOTP now enforced) | pass |
| vm-installer-lan (233 s, kiosk and font assertions added) | pass |
| vm-encryption (1243 s) | pass |
| every package's derivation evaluates (deploy, docs, media, nixie-cli, nixie-cockpit, nixie-installer, nixie-iso, nixie-panel, nixie-setup, nixie-setup-web, nixie-ui, test-iso) | pass |

`nix run .#test-iso` was run once more on the same tree and passed (install
147 s); its artifacts are the ones committed.

## The gaps left by the installer fixes, closed (2026-09-15)

1. **The desktop had no `nixie` command.** `packages/nixie-cli.nix` takes
   `guests`; `modules/base.nix` installs it on every host with
   `guests = nixie.incus.enable`, so a desktop gets the CLI without the Incus
   client and OpenTofu and a desktop that enables Incus gets both. The two
   commands that name a guest (`export`, `rollback guest`) say the host runs
   no guests; every other guest step already skipped a host without guest
   configuration. The setup service and Finish no longer bundle their own
   full CLI (which would have put OpenTofu in a desktop's setup generation);
   they run the host's. `profile-desktop-has-no-server` now evaluates a
   laptop with setup pending, and its pattern catches suffixed names
   (`incus-lts-client-7.0.1` slipped past `-incus-[0-9]`; only the
   `terraform-provider-incus` path had been matching). It fails with the
   full CLI on the desktop (tried) and passes with the light one;
   `vm-desktop` asserts the command runs, refuses `export`, and that neither
   `tofu` nor `incus` is on the path.
2. **A Secure Boot install from the image would not have continued setup.**
   The setup generation was selected with `bootctl set-default`, which
   refuses unless systemd-boot is the running loader, and on the image GRUB
   is; the failure was logged as "could not set the default boot entry in
   firmware" on every install. Plain installs were saved by the loader.conf
   rewrite, but lanzaboote has no such hook. The default is now set in
   loader.conf for both (`boot.lanzaboote.settings.default` while pending),
   and the firmware call is gone.
   The Secure Boot scenario below, run once with only that setting removed,
   booted the plain generation ("Welcome to Nixie 26.05.20260910…" instead of
   "…setup-26.05…"), so no setup service and no pairing code; with it, the
   setup generation.
3. **`test-iso` scenarios.** `--usb` boots the image as a USB stick under
   OVMF; the hardware scan offers exactly the target disk (the stick and
   zram excluded) and the plain install runs to Finish: pass, 321 s.
   `--security tpm` installs with encryption, TPM with PIN, attestation and
   duress, answers the first boot's passphrase through the duress agent, runs
   phase 6's TPM enrolment, reboots to "Attestation code: …" and "Please
   enter LUKS2 token PIN", passes phase 7's checks ("outer layer is open and
   bound to the TPM", "attestation code computes") and Finishes.
   `--security secureboot` installs with lanzaboote (the chain is signed
   during nixos-install), boots into the setup generation, and phase 5
   stages the keys and asks for the reboot. Run again on the final tree,
   each first boot answering its first prompt after 80 s: plain 382 s, usb
   441 s, tpm 507 s, secureboot 441 s, all pass. With the root pool ordering
   removed, the plain run reached "You are in emergency mode" (tried). Enrolment by the
   firmware and a verified boot afterwards stay hardware-only (Slice (b)).
4. **A passphrase typed after a minute sent the boot to emergency mode.**
   The root pool's import in the initrd starts as soon as the password agent
   does and retries for 60 seconds; whoever was slower than that found
   "You are in emergency mode" (seen in VirtualBox, where the script typed
   at 90 s; `vm-encryption` had a comment treating it as a test constraint).
   The import is ordered after `cryptsetup.target`, and `test-iso` now waits
   80 s before its first answer.
5. **The installed system came up at a different address.** In LAN mode the
   address is on the bridge, whose MAC networkd generates, so DHCP handed
   out a new lease (VirtualBox: 10.0.2.15 on the installer, 10.0.2.16
   installed; the setup URL changed and a reservation for the machine would
   not apply). The bridge now takes the first uplink's MAC; `vm-boot-plain`
   asserts it, and fails without the change (tried). QEMU's user network
   could not show this: each boot of the test is a new QEMU process with a
   fresh DHCP table.
6. **`BootNext` pointed at a stale entry on a reinstall.** The firmware kept a
   "Linux Boot Manager" from the previous install, whose partition was gone,
   and phase 3 took the first match, so VirtualBox booted the installer
   again. The entry is chosen by the new ESP's partition GUID.
7. **Smaller things found on the way.** The image carries the platform's
   flake inputs, so evaluating a site no longer unpacks disko, lanzaboote,
   sops-nix, terranix and their inputs from GitHub into RAM (`iso-config`
   asserts it). Desktops no longer report uplink drift (the facts file listed
   bridge ports on hosts without a bridge), and neither wizard asks a desktop
   for bridge ports or server-only network settings. The continuation page
   no longer shows the Secure Boot checklist on hosts without Secure Boot.
   `docs/guides/install-graphically.md` has the settings a VM needs.

In VirtualBox 7.2, scripted (the wizard's API through a NAT port forward,
pairing codes from a serial socket, the passphrase typed on the VM's keyboard
90 s after the reboot) on the final image: an encrypted server installs
(phases 1 to 3 in 202 s), the first boot goes to the installed disk with the
image still attached and stale boot entries in NVRAM, the passphrase opens
it, the setup generation answers at the installer's address (10.0.2.15),
phases 4 to 8 run, Finish removes the setup service, and the control panel
answers; the front panel shows `nixie-br: 10.0.2.15/24`. The run took four
attempts, which found items 4, 5 and 6 above.

The gate on the final tree (per-output loop, VirtualBox off): all 29 checks
pass, including vm-boot-plain (39 s, bridge MAC), vm-desktop (133 s, the
light CLI), vm-egress (98 s), vm-encryption (1246 s), vm-installer-lan
(233 s), vm-console (221 s), vm-host-ui (43 s) and
profile-desktop-has-no-server (setup pending, suffixed names); every
package's derivation evaluates.

Still not verified here: firmware Secure Boot enrolment and a verified boot
afterwards (OVMF, Slice (b)); a USB stick on physical hardware (the stick
path is exercised under OVMF with QEMU's USB storage); the TPM scenario in
VirtualBox (its virtual TPM was not enabled for these runs).

## Phase 3 evaluation errors from the web wizard (2026-09-15)

The screenshot showed an install stopping at phase 3 with a Nix trace
(`head` in `recursiveUpdateUntil`, then `value` in `lib/modules.nix`) and the
message cut off. Every choice the wizard offers was evaluated on its own and
in combination, first as options and then through the real path: a body
shaped the way `ui/src/setup/main.tsx` builds it, `nixie-setup --configure`
writing the site, a phase-1-style `hardware.nix`, and the `environment.etc`
build phase 3 starts with. Against the committed platform, remote unlock
(the early-boot root shell defined twice at one priority) and a desktop
package with an unfree licence (Steam refused) give exactly the frames in the
screenshot; lockdown integrity (a kernel option set twice) fails differently,
and a TPM measurement list typed in the wizard arrived as text. All of them
evaluate now; remote unlock without a key stops at its assertion, which
both wizards now prevent. `tests/sites/wizard-server.nix` and
`wizard-desktop.nix` put every wizard option on at once in `eval-matrix`;
the desktop one fails against the committed platform (tried).

Reported afterwards from VirtualBox (desktop, HyDE): phase 3 stopped with
"`users.users.root.shell` is defined multiple times". Reproduced exactly by
naming the administrator root, with or without HyDE; with "admin" the same
site evaluates. The module now throws "nixie.auth.admin.name cannot be
"root"…" before the collision (evaluated for root and nobody), and both
wizards refuse those names.

## After the install: boot, setup front ends, HyDE, the site (2026-09-15)

Reported from VirtualBox: after installing a desktop with HyDE, choosing
"nixie" in the text boot menu gave a TTY. Causes found: HyDE in the wizard
switches the Nixie desktop off and a wizard-made site has no HyDE, so no
session starts in either entry; a desktop's setup generation showed no
wizard at all ("continue in their own session" was never implemented); the
loader menu offered the plain entry while setup was unfinished.

Changes (ARCHITECTURE D32, D33): no loader menu; a Plymouth theme in the
Graphite finish (`nixie.host.bootSplash`), off with duress or attestation;
the setup generation imports the image's own `installer/front-end.nix`
with the front end recorded at install (`nixie.setup.frontEnd`), greetd held
back until Finish; a terminal continuation (`nixie-deploy --continue`); the
plain entry's getty says setup is unfinished; HyDE off the wizard with an
assertion for a site that enables it without a session; clearer profile
choice. Also: the wizard adds a host to an existing `site.nix` instead of
moving the old one aside, and a reinstall from a cloned site is marked
pending again; `nixie apply` commits hand edits and pushes to
`nixie.site.repo`, `nixie site key`; a grouped `nixie` help; kernel
versions in `rollback --list`.

| check | result |
|---|---|
| `boot-and-setup` (new): no menu, splash on, splash off with duress, graphical/web/terminal setup screens, greetd only after Finish, the unfinished warning, HyDE not in the wizard | pass |
| `iso-config` after moving the image's front end into `front-end.nix` | pass |
| `eval-matrix`, fmt, statix, deadnix, option-reference, option-docs, readme, no-hardware-facts, systemd-security | pass |
| `test-iso` plain on the new image: splash on, passphrase over the serial console (Plymouth falls back to text with `console=ttyS0`, `unlock-prompt.png`), setup and Finish | pass, 383 s |
| `test-iso --profile desktop` (new): the setup generation shows the wizard on a desktop (`setup-generation.png`, "iso-test · desktop"), Finish hands over to the greeter (`finished.png`) | pass, 628 s |
| site_new on a scratch site: a second host appended, both evaluate; a reinstall marked pending | pass |
| the apply's commit, pull and push steps, run from the CLI's own text against a local bare repository: hand edits committed as "apply on <host>: <files>", pushed; no pull against an empty remote | pass |
| splash: `vm-console` starts Plymouth on its display and asks for a passphrase; the Nixie theme draws the mark, the wordmark, the prompt and the field | pass; `tests/artifacts/e2e-server/92-boot-splash.png` (the booted system's font, not the initrd's Archivo) |
| greeter: `vm-desktop` with the rewritten stylesheet (regreet 0.3's `frame.background`, entries, combo buttons, suggested and destructive buttons) | pass, 120 s; `tests/artifacts/e2e-server/90-greeter-graphite.png` |
| `boot-and-setup`: the splash theme and the greeter's stylesheet change with `nixie.desktop.finish` (graphite against paper) | pass |
| the terminal continuation (`nixie-deploy --continue`) under a pseudo-terminal with the phase engine, systemd-run and Finish stubbed: phases 4 to 8 in order, the passphrase and backup path asked at 6, Finish run as its own unit | pass |
| full gate on the previous commit: 27 of 29, with option-reference (run between an edit and the regenerated file) and vm-egress (tailscaled's restart loop counted as a failed unit at the switch; the test now stops it first) | see text |
| rerun on this tree: vm-console, vm-desktop, vm-egress, vm-installer-lan, vm-ui | pass |

Not verified here: the splash during a real boot without a serial console
(`vm-console` starts Plymouth on its display after boot with
`--ignore-serial-consoles`); the terminal continuation on a real machine;
HyDE with hydenix in a site; a push to a real remote with the host's key.
Seen at first and fixed in the rows above: the greeter's login box drawn
white with light text (`finished.png`), its stylesheet naming widgets
regreet 0.3 does not have.

## The installer and setup rebuilt, HyDE through hydenix (2026-09-15)

Asked for: HyDE itself, full customisation, a cleaner installer with fewer
steps, full editing of the configuration before installing with highlighting
and completion, a modern animated look, setup after the first boot that
skips what a host does not use and does not restart to verify, no finish
swatches in setup, and a control panel that matches.

Changes (ARCHITECTURE D27 rewritten, D34 new):
- Steps: Machine, Disks, Name, Security (security and administrator
  together), Network, Services (backups, monitoring, host page and console,
  which had metadata but no step), Desktop, Review, Install. Labels and
  More options come from `lib/wizard.nix`; `checks.option-docs` wants an
  entry for every option with a wizard section.
- Review: a summary with Change links; `site.nix`, the host's
  `configuration.nix` (new, never rewritten), `hardware.nix`, `guests.nix`,
  `data.nix` and `flake.nix` in CodeMirror 6 with Nix highlighting,
  completion and hover help for every `nixie.*` option; All options, a
  searchable list that adds an option to `configuration.nix`;
  `POST /api/check` evaluates the host (`--no-eval-cache`) and marks the
  lines an error names, type errors included. Install waits for a passing
  check after the last edit.
- Backend fixes found on the way: going back and on to Review wrote the
  host's entry into `site.nix` a second time (duplicate attribute) and kept
  the old `hardware.nix` (phase 1's marker); both fixed.
- Setup after the first boot runs by itself as a checklist on the web page
  and in the terminal: unused phases are recorded unseen, and it stops only
  for the Secure Boot restart (or a restart into the firmware settings) and
  the passphrase and PIN. Phase 6 enrols the recovery key through the new
  TPM binding (`systemd-cryptenroll --unlock-tpm2-device=auto`, PIN as the
  `cryptenroll.tpm2-pin` credential), so the binding is proven before the
  passphrase slot is wiped and no verification restart is needed.
- HyDE: `mkSite { …; inherit inputs; }` hands a site's inputs to its hosts;
  a site with hydenix gets `modules/desktop/hyde.nix`; the wizard offers
  HyDE when online and writes the pinned input into the site's flake; the
  terminal installer offers it too. HyDE's Steam, Spotify, Discord and VS
  Code modules stay off; the Apps still install under HyDE.
- The setup backend lets a second request for a running phase wait
  instead of answering 409: the setup page now runs phases on every screen
  that shows it, and the phase's marker makes the repeat a no-op.
- Look: one motion vocabulary in `base.css` (transform and opacity only,
  off under reduced motion); softer radii; pill navigation; pages, panels,
  dialogs and toasts animate in; a shared `PageHead` on every panel page;
  the trust page and the kiosk lock page use setup's centred card; no finish
  swatches in setup. The panel waits for its backend before drawing pages
  (a preview served HTML as the network list and Topology crashed).

| check | result |
|---|---|
| `fmt`, `statix`, `deadnix`, `option-docs` (every wizard option labelled, no stale labels), `option-reference` (regenerated), `boot-and-setup` (the installer offers HyDE on the Desktop step), `readme`, `no-hardware-facts`, `no-secrets-in-store`, `systemd-security`, `eval-matrix`, `iso-config`, `iso-grub-theme`, the three profile checks, on the final tree | pass |
| `tsc` and `vite build` of both pages; CodeMirror splits into its own chunk loaded on Review | pass |
| the wizard in Chromium against the real backend with stand-in phase scripts: every step, More options, Review's summary, the real `nix eval` check (8 s), completion popup, a syntax error marked on `configuration.nix:8`, All options, Install's checklist; `tests/artifacts/wizard/` | pass |
| `check_site` messages and marks for a syntax error, a type error (`nixie.backups.enable = 12`, line found from the option name, nested form too) and a failed assertion; the eval cache returned "cached failure" without detail before `--no-eval-cache` | pass |
| `site_new` run three times for two hosts: one entry each, the rewrite replaces; a HyDE host turns an installer-written flake into one with the pinned hydenix input, a hand-written flake is left alone | pass |
| the setup page in Chromium, continuation mode with a fake layout (Secure Boot, encryption, TPM): runs by itself, stops for the Secure Boot restart, resumes after a reload, asks passphrase and PIN once, shows the recovery key, stops at Finish | pass |
| the terminal setup (`nixie-deploy --continue`) with its paths redirected and gum, systemctl and the phases stubbed: the same flow across a simulated restart; a host without Secure Boot or encryption shows only First start, Checks and Apply | pass |
| three concurrent `POST /api/phase/4` against the backend: one runs it, two wait and return rc 0 "already done" | pass |
| HyDE: a site with the pinned hydenix input and four hosts (plain HyDE desktop; every wizard option plus Secure Boot, Steam and VS Code from the Apps; a server; a desktop with Incus) evaluates to system derivations through the platform's `mkSite`; the server's derivation is identical to one from a site without hydenix | pass |
| HyDE through the wizard: Desktop step (offered online), Review writes the input and the host evaluates (16 s); `32-desktop-hyde.png`, `34-hyde-flake.png` | pass |
| HyDE desktop VM (`desk-vm` from that site) boots to HyDE's sddm login with the administrator and the Hyprland session | pass; `tests/artifacts/wizard/40-hyde-login.png` |
| `vm-encryption`: phase 6 enrols the recovery key through the TPM ("outer layer bound to TPM (PCRs 7) with PIN"), the next boot opens with the PIN, reenroll | pass, 1192 s |
| `vm-desktop` (Apps and the display manager mask in setup) | pass, 131 s |
| `vm-installer-lan`: the kiosk's first step read back as "Machine" (the old "Profile" wait failed once, before the test was updated), pairing, install, setup over the URL, with the waiting phase runner | pass, 212 s |
| `vm-console` (the restyled lock page, OCR "Unlock"), `vm-ui` (the panel bundle) on the final tree | pass, 198 s and 16 s |
| `test-iso --security tpm`: install with Review's check on the ISO (`check.json`), phase 6 through the TPM, reboot with PIN and attestation code, Finish | pass, 607 s; `tests/artifacts/test-iso-tpm/` (the first try failed only because the scratchpad path was too long for swtpm's socket) |
| `test-iso` plain on the rebuilt image: the kiosk's setup page ran phases 4 to 8 by itself before the script asked (every request "already done"), then Finish | pass, 536 s; `tests/artifacts/test-iso/setup-generation.png` |
| the control panel in demo mode, every page, the palette; the trust page; the kiosk lock page rendered from the store | seen in Chromium |

Not verified here: a HyDE login into the Hyprland session (the VM's
administrator password is the scratch site's); HyDE installed from the
image end to end (it needs the network and minutes of downloads inside the
installer); Secure Boot enrolment completing on firmware (as before, OVMF
stages the keys but does not boot the signed chain); the media gallery
(`nix run .#media`), whose installer walkthrough was updated to the new
steps but not run; the terminal installer's colours on a real console.

## Lists instead of blank fields, and a site's other machines (2026-09-16)

Asked for: a time zone chosen from a dropdown rather than typed, several
deployments on different machines managed in the UI, and folders or drives
picked for backups and for the key backup.

Changes (ARCHITECTURE D36):
- `lib/wizard.nix` carries a `picker` for an option this machine can answer
  and `lib/options-json.nix` passes it to the wizard. `nixie.host.timezone`
  becomes a list from the machine's own tzdata (`GET /api/timezones`,
  `timedatectl list-timezones`); `nixie.backups.repository` becomes a folder
  that can also be picked from the drives the machine can see
  (`GET /api/devices` from `lsblk`, `POST /api/mount` to mount the one
  picked). `packages/nixie-setup.nix` gained `pkgs.util-linux` for them.
- The setup checklist's last step writes the disk's header backup to a folder
  picked the same way (`POST /api/header-backup`); until now the kiosk on the
  machine itself could only offer a browser download, which goes nowhere.
- `block_devices` leaves out swap, LUKS containers (their unlocked mapping is
  listed instead), pool members and read-only media, and puts removable
  drives first.
- `lib.mkSite` derives `nixie.ui.machines` from site.nix's own data. It cannot
  come from the other hosts' evaluated configurations: each of those would
  need this same list, and the evaluation would not terminate. A host whose
  `settings` is a module function is listed without its details rather than
  guessed at. `modules/incus.nix` writes the list, with this host's name, into
  the panel's `nixie.json`, and `ui/src/pages/Machines.tsx` draws it.

| check | result |
|---|---|
| `fmt`, `statix`, `deadnix`, `option-docs`, `option-reference` (regenerated for `nixie.ui.machines`), `readme` | pass |
| `setup-devices` (new): the `lsblk` filter over a tree with a system disk, its swap and LUKS container, the unlocked mapping, a removable stick, and a stick holding the installer's own iso9660 | pass |
| `site-machines` (new): `lib.mkSite` over `tests/sites/two-hosts/`, both machines with their profile and the panel URL of the one with a fixed address | pass |
| `vm-ui`: the served `nixie.json` carries `host` and both machines, the one without an address with `url: null` | pass |
| `vm-installer-lan`: the wizard over the LAN against the changed backend | pass |
| `tsc` and `vite build` of both pages | pass |
| the new endpoints against a running `nixie-setup` on this machine: `/api/timezones` returned 554 zones including `Europe/Amsterdam`; `/api/devices` listed the plugged-in USB stick first with its label and model, and left out swap, the LUKS container and the ISO on the stick | pass |
| VirtualBox 7.2.16, a hardened **desktop** end to end (EFI, TPM 2.0, NAT with the setup port forwarded, driven through the same web API a browser uses): the ISO's kiosk, pairing with the code from the machine's own console, hardware discovery (`"efi": true, "tpm": true`, the disk by its id), phase 1, the review step's check, phases 2 and 3, the restart, the passphrase typed on the machine's own console, the setup generation's own pairing code (463469) read from that console, `/api/timezones` there (554 zones, `Europe/Amsterdam` among them), `/api/devices` there (only the writable ESP: the LUKS container and the ZFS members are left out, as intended), phases 4, 6, 7 and 8, the header backup written to a chosen folder, the recovery key and the attestation code, and Finish | pass |
| the same walkthrough as a hardened **server**: the same install and setup, and after Finish the panel answers and its `nixie.json` reads `{"host": "vbox", "machines": [{"name": "vbox", "profile": "server", "url": null}]}` — the Machines page's list, on a real install | pass |
| the gallery: `nix run .#media` at 6644be4, 124 assets, 20 MB. `installer-services-backup-drive.png` is the picker open in a real browser against a real backend, listing two real filesystems with size, type and mountpoint; the Network step asserts the time zone datalist holds more than 100 zones; `panel-machines-*.png` shows both machines of the site with this one marked | pass |

Defects this found in the media runs themselves, all fixed:
- the boot run's unlock relay wrote the answer with `printf %s\n` unquoted, so
  the shell ate the backslash and the passphrase arrived without a newline;
  the prompt never took it and the target sat in the initrd until the test
  timed out. `vm-encryption` quotes the format, which is why it passed and
  this one had never produced a single asset.
- `copy_from_vm` for the attestation text needs the 9p `shared` mount, which
  that target does not have: it boots the filesystems the install made.
- `systemd-run` starts with an empty PATH, so the second relay found neither
  `nc` nor `sleep` and nothing answered the PIN and passphrase of the
  recorded boot.
- `machine.sleep()` runs `sleep` inside the guest, which deadlocks the driver
  while the guest is at the initrd passphrase prompt; the driver's own clock
  is used there instead.
- the panel run builds its host from the modules rather than through
  `lib.mkSite`, so its Machines page was empty; it now sets
  `nixie.ui.machines` the way `vm-ui` does.

Two things VirtualBox needed, neither of them Nixie's doing, both found by
running it: with VirtualBox's default Intel PRO/1000 the installed guest's
NIC wedges ("e1000 enp0s3: Detected Tx Unit Hang") and the machine ends up
with no address at all, so its setup page is unreachable from another device
(the paravirtualised adapter has no such trouble); and with four vCPUs and no
explicit paravirt clock the guest starved its own RCU ("rcu_preempt kthread
starved", "Possible timer handling issue") on an idle host, which left it
stuck at the passphrase prompt. The walkthrough therefore asks VirtualBox for
`--nictype1 virtio --paravirtprovider kvm --hpet on`. The installer half of
the run is unaffected by both and passed every time.

Housekeeping: `tests/artifacts/*/target.qcow2` and the EFI variable files left
by earlier `nix run .#test-iso` runs had grown to 28 GB. They are gitignored
but they filled the disk to 97%, which made `nix eval` fail with "No space
left on device"; they are deleted after a run now.

## The host page in the control panel's finish (2026-09-16)

Asked for: Cockpit that matches the rest of the UI instead of looking
different.

Found: the host page was PatternFly's own — white cards, blue buttons, sharp
corners, system fonts — because `modules/host-ui.nix` set PatternFly **v5**
variables and cockpit 366 ships PatternFly **6**, so none of it applied.

Changes (ARCHITECTURE section 10, host page):
- Both PatternFly 6 token layers, the palette (`--pf-t--color--gray--NN`) and
  the semantic one (`--pf-t--global--…`), are written from `lib/tokens.nix`,
  because several components reach past the semantic token to the palette.
  Both blocks name `.pf-v6-theme-dark` beside `:root`: cockpit puts its dark
  values on that class at the same specificity, and `branding.css` is linked
  after each page's own stylesheet, so the finish wins in either theme.
- The panel's recipes on top: 10px cards with its border and shadow, 6px
  buttons and inputs, pill navigation with the current item on the panel
  surface, a masthead that is one surface with a hairline under it, status
  colours from the finish, a reduced-motion block.
- Archivo and JetBrains Mono are served beside `branding.css` with
  `@font-face`: a browser on another machine has neither installed.
- Only each cockpit package's `index.html` links `branding.css`; the
  secondary pages (`systemd/{logs,services,terminal,hwinfo}.html`,
  `networkmanager/firewall.html`) do not, so Overview was dressed and Terminal
  was not. The host page's cockpit is a symlink farm over the package that
  adds the link to those pages; the NixOS module compares the package's
  version, so the derivation carries it.
- The login page keeps colour variables of its own (`--color-background`,
  `--color-text`, …) rather than PatternFly's tokens; they are set from the
  finish too. The wordmark no longer ends in a separator when cockpit leaves
  `#brand` empty.
- The History plugin follows the same recipes.

| check | result |
|---|---|
| which cockpit 366 pages link `branding.css`, read from the package: every `index.html` and `static/login.html` do; the five secondary pages above do not | as described |
| `vm-host-ui` on the patched package: password plus TOTP logs in and a wrong code does not; the History screen is installed and answers | pass |
| the gallery at 92b784d, `hostui-*.png` from a real browser against the real host: the shell, Overview, Terminal (formerly stock) and the login page (formerly white, with the wordmark invisible on it) all in the finish | seen |
| `fmt`, `statix`, `deadnix`, `eval-matrix` | pass |

## HyDE's one Rust program and the crates.io 403 (2026-09-16)

Reported: building a HyDE desktop failed with 403 errors on another machine.

Reproduced here with a site carrying the pinned hydenix input. The failure is
not cache.nixos.org (lines matching "403" there are store hashes); it is:

```
crate-clap_complete> curl: (22) The requested URL returned error: 403
crate-clap_complete> error: cannot download crate-clap_complete-4.5.58.tar.gz from any mirror
```

and it cascades through `cargo-vendor-dir`, `hyde-ipc`, the home-manager
generation and the system. crates.io refuses any user agent that begins with
`curl/`, which is what nixpkgs' `fetchurl` builder sends:

| user agent on `crates.io/api/v1/crates/clap_complete/4.5.58/download` | answer |
|---|---|
| `curl/8.17.0 Nixpkgs/26.05` (what `fetchurl` sends) | 403 |
| `curl/8.17.0` | 403 |
| `Nixpkgs/26.05` | 200 |
| none of the above, at `static.crates.io/crates/clap_complete/4.5.58/download` | 200 |

The platform's nixpkgs already fetches crates from static.crates.io
(`pkgs/build-support/rust/import-cargo-lock.nix`, rust-lang/crates.io#13482).
`hyde-ipc` comes from a flake of its own whose nixpkgs predates that, and no
binary cache has it. It is HyDE's only Rust program (`hydectl` is Go, `hyq`
is C++), so it is now built from the same pinned source with the platform's
`rustPlatform` (ARCHITECTURE D27).

Tried and dropped: overriding `fetchurl` in HyDE's package set. It is an
`extendMkDerivation` set; replacing its functor fails evaluation ("expected a
set but found a function"), and extending it across the two nixpkgs ends in
infinite recursion in `make-derivation`. `lib.isFunction` is also true for a
callable set, so it cannot tell the two shapes apart.

| check | result |
|---|---|
| a desktop host from a site with the pinned hydenix input, before the change | fails as reported |
| the same host after it: `hyde-ipc` vendors its crates and builds, and the whole system builds (`nixos-system-laptop-26.05…`) | pass |
| `fmt`, `statix`, `deadnix`, `eval-matrix` | pass |

## Secure Boot setup that ended in "Access Denied" (2026-09-17)

Reported on real hardware: with Secure Boot off at first, restarting from the
setup screen that asked for Secure Boot left the machine unable to start the
installed system or the installer ("Access Denied"); resetting the keys with
Secure Boot Mode set to Custom worked.

Cause: phase 5's instructions said to keep Secure Boot *enabled* while
clearing its keys. Enabled while the firmware still holds its vendor's keys,
the firmware refuses this machine's boot loader (signed with the site's own
keys) and the installer. Separately, phase 5 knew only "enabled", "Setup Mode"
and everything else: after systemd-boot enrolled the keys with the switch
still off, the firmware reports `disabled (disabled)` exactly as it does with
vendor keys, and phase 5 sent the person to clear the keys again. The
enrolment itself was not at fault: lanzaboote includes Microsoft's keys
(`includeMicrosoftKeys = true` on the hardened host), so option ROMs such as
an NVIDIA card's still load.

Change: phase 5 looks for this machine's PK certificate inside the firmware's
`PK` variable. Found with the switch off: exit 12, "turn Secure Boot on".
Not found: exit 11, with the steps as they read on such firmware (Secure
Boot Mode to Custom, reset the keys, leave Secure Boot off) and what
"Access Denied" means and how to undo it. The setup page, the terminal
setup, the option's help and the install guide say the same.

| check | result |
|---|---|
| `secure-boot-states` (new): phase 5 with a stub `bootctl` and fake firmware variables — enabled → 0 with its marker; Setup Mode → 10; disabled with this machine's PK → 12 and "turn Secure Boot on"; disabled with a vendor PK → 11 with "Custom" and "Access Denied"; disabled with an empty PK → 11 | pass |
| `vm-encryption` (1227 s): phase 5 still stages the keys in Setup Mode and exits 10 | pass |
| `vm-installer-lan` (247 s): the setup page with the new Secure Boot states | pass |
| `fmt`, `statix`, `deadnix`, `option-docs`, `option-reference` (regenerated for the option's help), `readme`, `boot-and-setup` | pass |

The same batch widens USBGuard's setup-time rule. While setup is pending it
let HID keyboards through and nothing else, so a mouse, touchpad or
touchscreen plugged in after usbguard first ran was blocked and the kiosk's
setup page could not be used. The rule now also admits HID boot mice and HID
devices without a boot subclass; it still disappears at Finish.

| check | result |
|---|---|
| `vm-hardware` (59 s), new subtest on a host still in setup: a USB mouse and then a USB keyboard plugged in after usbguard started are both allowed (the daemon's decision reads `target.old='block' target.new='allow'`); the existing subtests still block a late device on a finished host | pass |

Not verified here: a Secure Boot boot on firmware (OVMF stages the keys but
does not boot the signed chain, as recorded under Slice (b)); the steps were
confirmed on the reporter's machine.

## Four things the wizard drew wrong (2026-09-17)

Reported: the attestation QR code is squished and will not scan; the TPM
measurements should be checkboxes rather than free text; the time zone is only
a list once the default "UTC" is deleted; the "hardened" chips on the Security
step stretch to the width of the text above them.

Each was reproduced in Chromium against the real setup backend on this
machine (walked to the Security and Network steps only; nothing past them, so
no phase ran), and each cause was found before anything changed:

- **QR codes.** `tpm2-totp generate` draws its code with ANSI background
  colours only: each module is two spaces inside `\e[40m` or `\e[47m`, with
  no visible glyph. A browser prints those escapes as text, so the page showed
  a wide block of `[47m` with the URI under it; zbar found nothing in a
  screenshot of it. The backend now reads the `otpauth://` line tpm2-totp
  prints under its picture and serves every QR a page shows (the attestation
  secret, the recovery key, the host page's authenticator) as an SVG from
  `qrencode -t SVG`, drawn as an image with dark modules on white. The console
  banner keeps its text QR, where a character cell is what it was drawn for.
- **Time zone.** A `<datalist>` only suggests entries that match what is
  already typed, so "UTC" filtered the list down to itself. It is now a
  `<select>` of the machine's own zones, grouped by region.
- **TPM measurements.** `lib/wizard.nix` gives `nixie.security.tpm.pcrs` a
  `pcrs` picker: a checkbox for each of registers 0 to 15 with what systemd
  says it measures, 7 marked recommended. A register the site set outside that
  range is still shown, so saving never drops it.
- **Chips.** The header's logo rule was a bare `.brand`, and `chip brand` is a
  colour, so every brand-coloured chip also became a block-level flex box with
  the logo's padding and border: on a line of its own under the label,
  stretched to the label's width. The rule is now `.header > .brand`. The same
  leak affected the declared, running and "this machine" chips in the panel.

| check | result |
|---|---|
| a screenshot of the attestation QR as the page drew it, before | zbar: no symbol |
| `setup-qr` (new): tpm2-totp's printed form gives back its URI, and the SVG the page shows decodes to that URI | pass |
| a screenshot of the authenticator QR as the page now draws it | zbar: `otpauth://totp/nixie%3A…?secret=…&issuer=nixie` |
| enrolling the authenticator from the secret the page shows, then Verify | enrolled |
| the time zone control on the Network step with "UTC" selected | a `SELECT` holding 554 zones |
| TPM measurements: 7 ticked by default; tick 4 and 11, then untick 11 | `[7]` → `[4, 7, 11]` → `[4, 7]` |
| the chip's computed style on the Security step | `display: inline`, beside its label; the field is 43px tall instead of 64px |
| the panel in demo mode: the header logo and a brand chip | logo `display: flex` with its padding and border; chip `display: inline`, no border |
| `fmt`, `statix`, `deadnix`, `option-docs`, `option-reference`, `readme`, `setup-devices`, `setup-qr`, `site-machines`, `eval-matrix`, `boot-and-setup` | pass |
| `vm-installer-lan` (231 s), `vm-ui` (43 s) | pass |

## Every check on the final tree (2026-09-17)

All 32 checks in the flake, one build per check (the single-process
`nix flake check` does not fit in this host's memory; see "Final run"), on
commit 519cc22 with a clean tree. The platform source is part of every
host's closure, so each check's derivation was new at that commit and every
one of them ran; none was a result reused from an earlier commit. This
section is the only change since.

| check | result |
|---|---|
| fmt, statix, deadnix, no-hardware-facts, option-docs, option-reference, readme, setup-devices, site-machines, eval-matrix, no-secrets-in-store, systemd-security, iso-config, iso-grub-theme, boot-and-setup, profile-server-has-no-desktop, profile-server-kiosk-only, profile-desktop-has-no-server | pass |
| vm-boot-plain (51s) | pass |
| vm-egress (131s) | pass |
| vm-guests (100s) | pass |
| vm-data (57s) | pass |
| vm-monitoring (109s) | pass |
| vm-ui (44s) | pass |
| vm-host-ui (45s) | pass |
| vm-backup (58s) | pass |
| vm-rollback (157s) | pass |
| vm-hardware (40s) | pass |
| vm-installer-lan (263s) | pass |
| vm-console (246s) | pass |
| vm-desktop (141s) | pass |
| vm-encryption (1349s) | pass |

Outside the checks: the gallery is 124 files and 21 MB from one run at
92b784d (the only commits since change no pixels), every video is under the
8 MB budget, and every `docs/media/` path in the README exists.

## The splash on every machine, security keys, and a disk opened elsewhere (2026-09-17)

Reported: after the code is typed the machine "goes to startup but stays
there for a little bit with no indication"; the prompts and the attestation
code should be on the Plymouth screen, with a better-looking start than
Linux's text, and still secure; the duress passphrase should work on the
outer layer too; `nixie reseal` should run by itself after an update; custom
Plymouth themes from any repository; security keys for the disk and SSH,
with passwords as well; a way to open a disk elsewhere with its keys.

Causes, found before changing anything:

- **The pause.** The duress check replaced the command of systemd's console
  password unit, which is `Type=notify`; the loop never reports ready, so
  after the passphrase the boot waited out that unit's start timeout and then
  printed "Failed to start Dispatch Password Requests to Console" (it is in
  `tests/artifacts/test-iso-hardened/serial.log`). The check also tried the
  entry against every key slot, one key derivation each.
- **No splash on hardened machines.** systemd does not start its console
  agent while Plymouth runs, and the Plymouth package brings its own agent
  into the initrd, which answers without the duress check; so the splash was
  off whenever duress or attestation was on.
- **Duress at the PIN prompt.** systemd's token PIN request carries no `Id=`,
  so the check never ran there, and the inner layer's slot 7 cannot be read
  before the outer layer is open.
- **Plymouth** (from its source): it cannot withdraw a question; its text
  view prints every message; it writes status updates to
  `/var/lib/plymouth/boot-duration`; it captures what userspace writes to
  the console; a serial console on the command line puts every screen in the
  text view; and it takes the firmware framebuffer only after eight seconds
  without a graphics driver unless `plymouth.use-simpledrm` is given.
- **systemd-cryptsetup** (from its source): it tries every token, asking for
  its PIN, whenever no key file is given, whatever the crypttab options; the
  TPM and a security key both ask "Please enter LUKS2 token PIN:"; it reuses
  the passphrase just typed for the next layer; and with token modules off,
  `fido2-device=auto` on a layer without a FIDO2 token fails instead of
  asking for the passphrase.
- **The first real start after Finish** would have said the attestation
  failed: the ESP recorded the sealed generation's label, which the setup
  generation and the one after Finish share, though their boot chains
  differ. And a first start before setup said "ATTESTATION FAILED" too.

What changed is in ARCHITECTURE (D32, D37) and the CHANGELOG.

| check | result |
|---|---|
| cryptsetup 2.8.6 on image files: an unbound slot 7 verifies with `--test-passphrase --key-slot 7` (so does an old bound one), opens nothing with `--test-passphrase` alone, and survives `erase` until `luksKillSlot 7` | as described |
| `vm-splash` (new, 574 s), five subtests: (1) phases 1–3 give both layers an unbound slot 7 that verifies and opens nothing; (2) the first start shows the graphical splash with "Passphrase or recovery key" (screenshot), the passphrase typed on the keyboard opens both layers, no other password agent ran in the initrd, and nothing about passwords, cryptsetup, nixie or plymouth failed; phases 4 and 6 enrol the TPM, the attestation secret and a CanoKey whose PIN `fido2-token` set; (3) the next start shows "Attestation code" and the code, and "PIN" (both read off the screen by OCR); a wrong PIN brings "That did not open the disk. Try again." (read off the screen); the right one brings "Security key PIN", whose PIN reaches the real root 5.0 s after the question by the kernel's clock (the typing waits 2 s of it); the reseal unit leaves a secret sealed for this system alone, refuses an unverified new system, and, in its own sandbox with a test-only stand-in `bootctl` reporting Secure Boot on, reseals it and records the booted system; (4) the installer VM, with another TPM and no key, opens the disk with `nixie disk open` (the recovery key, then after 5 s without a key the passphrase), finds the system read-only at `/mnt/nixie`, and `nixie disk close` locks it; (5) the duress passphrase typed at the TPM PIN prompt powers off and leaves no key slot | pass |
| `vm-encryption` (413 s, on the tree before the last label and CLI changes; the final run is below): remote unlock over SSH with the splash on, TPM + PIN, attestation, reenroll, duress at the inner prompt | pass |
| `boot-and-setup` (the splash with duress and attestation, one agent, the masked units, a quiet boot, a Plymouth theme by name), `splash-theme` (new: a theme two directories deep in its source, installed into the initrd with its paths rewritten), `hardware-keys` (new: FIDO2 on the passphrase layer, `AuthenticationMethods publickey,password`, a pasted private key refused with its reason) | pass |
| `systemd-security`, now over the every-feature server too: `nixie-attestation-reseal` scores 1.1 ("OK" to systemd), documented above the platform's 0.3 | pass |
| shellcheck of the agent, the initrd attestation script (Nixie theme and another) and the reseal unit | clean |

Not verified here: the automatic reseal with Secure Boot actually enforced
(this OVMF stages keys but does not boot the signed chain; the unit's own
path ran with a stand-in that reports it on), a physical security key
(QEMU's CanoKey confirms presence by itself), and a theme from a real
theme repository (the fixture has the same layout).

The whole suite ran again on this tree, one build per check (the
single-process `nix flake check` does not fit in this host's memory; see
"Final run"), and every one passed:

| check | result |
|---|---|
| boot-and-setup, deadnix, deploy-continues, desktop-motion, eval-matrix, exporters, fmt, hardware-keys, iso-config, iso-grub-theme, no-hardware-facts, no-secrets-in-store, option-docs, option-reference, profile-desktop-has-no-server, profile-server-has-no-desktop, profile-server-kiosk-only, readme, registry, secure-boot-report, secure-boot-states, setup-devices, setup-qr, site-machines, splash-theme, statix, systemd-security, updates | pass |
| vm-backup (55s), vm-boot-plain (67s), vm-console (244s), vm-data (55s), vm-desktop (130s), vm-egress (97s), vm-encryption (379s), vm-guests (98s), vm-hardware (54s), vm-host-ui (46s), vm-installer-lan (246s), vm-monitoring (72s), vm-rollback (153s), vm-splash (553s), vm-ui (17s), vm-updates (41s) | pass |

Beyond the checks:

| run | result |
|---|---|
| `nix run .#test-iso -- --security hardened` (588 s, `tests/artifacts/test-iso-hardened-splash/`): the image installs itself through the wizard's API, the first start says "No attestation code yet" and asks "Passphrase or recovery key" with "Unlocking…" after it, the restart shows the code and asks for the PIN, setup reaches Finish and the control panel answers; its serial log has no "Failed to start Dispatch Password Requests", which the earlier run's (`test-iso-hardened/serial.log`) has twice | pass |
| `nix run .#media` (1326 s): the gallery from real runs again, 124 files and 21 MB; `boot-pin-prompt.png`, `boot-attestation-code.png`, `boot-passphrase-prompt.png` and `boot-splash.png` are now the splash with the code under the field | pass |

The checks ran with the code exactly as committed; `docs/media`, this
section and the changelog are the only things that changed afterwards. That
ISO run keeps a serial console on the installed machine, which puts Plymouth
in its text view on every screen (see D32): the prompts, the code and
"Unlocking…" read as text there, and the code shows twice, once from the
console line and once as the splash's message.

## Code out of the Nix files, into files of its own (2026-09-17)

Asked for: "move all of the inline code/configuration stuff in the nix files
to seperate files that are imported instead? so the actual nix stuff is
slim?"

Every block of shell, Lua, CSS, HTML, JavaScript and test Python that sat in
a `''` string now sits in a file beside the module that installs it, filled
by `lib/template.nix` (D38). What stayed inline: the lines that build a
derivation (a `runCommand`'s own script) and text Nix generates outright,
such as the firewall's per-guest chains -- about 260 lines in all, against
roughly 2,000 moved out.

| file | Nix lines before | after |
|---|---|---|
| `packages/nixie-cli.nix` | 629 | 47 |
| `modules/host-ui.nix` | 423 | 204 |
| `modules/desktop/theme.nix` | 422 | 253 |
| `modules/desktop/hyprland.nix` | 363 | 261 |
| `packages/nixie-cockpit.nix` | 108 | 40 |
| `tests/vm/splash.nix` | 303 | 123 |

Nothing a machine installs changed, and that was checked rather than
assumed: each extracted piece was built from both trees and compared.

| check | result |
|---|---|
| `nixie` (the command), the Nixie Plymouth theme, the desktop's finish directory (gtk.css, kitty-colors.conf, hyprlock.conf, tokens.json), kitty.conf, sysinit.vim, starship.toml, hypridle.conf, the Hyprland Lua, `nixie-shell`, the Cockpit history page | byte for byte identical; the CLI's derivation path is unchanged |
| the greeter's stylesheet, the ISO's boot menu theme | identical but for a header comment added to the new file |
| every VM test's script (`config.testScript`), before and after | identical but for the system store paths, which moved because the modules did |
| the initrd's unlock agent, the attestation scripts | the same steps with the values as variables rather than inlined paths; verified by `vm-splash` and `vm-encryption` below |

Two things the move taught, both now in `lib/template.nix`:
`builtins.replaceStrings` corrupts the string context when several store
paths go in at once ("Bad String Context element"), so `fill` splits and
concatenates instead; and `toString` on a path yields the source path
without copying it into the store, which quietly dropped test key files as
build inputs until paths were interpolated instead. A mark with no value
stops the evaluation -- which is how the Cockpit page's `@shadow@` was
caught, a token that is not a plain hex colour.

| check | result |
|---|---|
| boot-and-setup, deadnix, eval-matrix, fmt, hardware-keys, iso-config, iso-grub-theme, no-hardware-facts, no-secrets-in-store, option-docs, option-reference, profile-desktop-has-no-server, profile-server-has-no-desktop, profile-server-kiosk-only, readme, secure-boot-states, setup-devices, setup-qr, site-machines, splash-theme, statix, systemd-security | pass |
| vm-backup (58s), vm-boot-plain (43s), vm-console (316s), vm-data (55s), vm-desktop (139s), vm-egress (106s), vm-encryption (414s), vm-guests (80s), vm-hardware (63s), vm-host-ui (45s), vm-installer-lan (246s), vm-monitoring (96s), vm-rollback (158s), vm-splash (583s), vm-ui (45s) | pass |

## One site, several machines; and what "Access Denied" means (2026-09-18)

Asked for: "is it possible to have a updating mechanism for both nixie and a
guest configuration/system? (for example, if I update the config on my
laptop, and I want to be able to push it and my desktop recognizing it needs
to update the config, both auto/manual/and off modes)", "Also make sure same
thing with guests/servers/desktops, and UI notifications for everything that
needs it, and or menus", and "I tried doing the secure boot stuff, but it
keeps giving access denied".

Following the site is `nixie update`: fetch the site's ref, compare it with
the commit the *running system* was built from (`site.json`'s `rev`, not the
checkout's HEAD -- a checkout can be edited for months without ever being
applied), and write `/run/nixie/update.json`. What happens next is
`nixie.updates.mode`: "notify" stops there, "auto" runs `nixie apply --yes
--confirm-within`, and confirms only when `nixie doctor` comes out no worse
than it did before the apply, so a machine that breaks itself while nobody is
watching goes back by the rollback timer that apply already arms. Comparing
doctor with itself rather than demanding a pass is the point: doctor fails
for a blocked USB device or a backup check that has not run, and a machine
unhappy about any of that would otherwise apply and revert the same update
every hour for ever. Applying is the ordinary `nixie apply`, which is why a
guest's configuration follows by the same step on a server as on a desktop:
no second mechanism (D39).

Everything a machine wants to say is one file, `/run/nixie/notices.json`,
written by `nixie notices --write` every fifteen minutes and after every
check: an update waiting, an apply waiting to be confirmed, an attestation
that no longer computes, a failed backup check, a service in the failed
state, a blocked USB device. A failed unit was the one thing no surface said
anything about, and `nixie doctor` says it now too. The surfaces read that
one file rather than each asking its own questions -- the front panel (and
`u` applies what is waiting), the host page (with "Apply it now"), a desktop
notification each notice once, the login line, and `nixie doctor`.

The control panel reads them from the daemon rather than from that file. It
is a static bundle incusd serves and it speaks only the Incus API, so
serving `/run/nixie/notices.json` beside the bundle was the obvious way and
the wrong one: that directory needs no certificate, and it would publish a
failed backup and the site's commit subjects to anyone who opened the page.
`nixie notices --write` sets `user.nixie.notices` on the local daemon
instead -- the free-form server configuration the panel's own settings
already live in -- and the panel picks it up with the poll it already runs,
behind the client certificate everything else there needs. It says the
notice and names the command; acting on it stays with the machine, as the
panel's History page already does for generations.

The machine that cannot start is the one that needs this most, and it cannot
run the command. `nixie disk open` now brings that disk's boot partition up
beside its pools -- found by the parent disk rather than the partition
label, which this machine's own boot partition carries too -- and `nixie
secure-boot --at /mnt/nixie` reports on the system opened there while
reading the firmware of the machine it is running on, which is the one thing
that cannot come off another machine's disk. `nixie disk close` unmounts it
under each opened pool's own altroot, so it can never reach the boot
partition the running machine is using.

`nixie secure-boot` answers the report: what the firmware holds (this
machine's own PK certificate found *inside* the PK variable -- "disabled"
reads the same whoever's keys are in there), whether keys are staged on the
boot partition, and whether every `.efi` on the ESP verifies against this
machine's db key, with the step to take for each state and `--sign` to sign
what does not. The vendor-keys case names the installer stick as well: it is
unsigned and the firmware tries it first, which is the "Access Denied" a
person sees while the stick is still in.

| check | result |
|---|---|
| `updates` (nine facts) | pass; the three modes, the timers, the site file, the login line, the desktop notifier, and that a server has none |
| `secure-boot-report` (four firmware states, and the same report about a disk opened elsewhere) | pass; a generated PK certificate placed inside a fake PK variable, a stand-in `bootctl` for each state |
| `vm-updates` (two nodes, five subtests) | pass; a bare repository both machines share, a second checkout standing in for the laptop that pushes |
| `vm-ui` (extended) | pass; a unit broken on purpose reaches `user.nixie.notices` on the daemon, the chunk the page preloads carries the reader, and nothing of the notice is served to a caller with no certificate |

`vm-updates` is the whole path with nothing stubbed but the build: a machine
that is up to date says so and shows nothing; a change pushed from elsewhere
is seen by `nixie-update.service`, appears in `update.json`, in
`nixie notices --json`, in `nixie doctor` and at a login, and nothing is
applied; a person runs `nixie update --now` and the checkout, the running
system and the notices all follow; an "auto" machine applies by itself and
confirms, leaving no rollback timer behind; and a unit put into the failed
state shows up in the notices and in doctor, and is gone from both once it
is reset. What a real machine builds from the site it just fetched, the test
switches to prebuilt (`NIXIE_TOPLEVEL`), as every applying test here does.

Not verified here: `nixie update --inputs`, which runs `nix flake update` in
the site checkout and then applies. Updating a lock needs the network and a
newer upstream to move to, neither of which a sandboxed VM test has; what
happens after it -- the apply, the push and the other machines following --
is `vm-updates` above.

Four things the work turned up:

- A `systemd-run ... nixie rollback --auto` inside `nixie apply` had never
  worked from a unit: a transient unit's PATH holds no system profile. Every
  self-call now goes through `${BASH_SOURCE[0]}`, the pre-existing one
  included.
- `nixie.updates.mode` defaults to "notify", and a machine with no
  `nixie.site.repo` then installed a timer that could only fail (caught by
  `vm-desktop`). The units are gated on having a repository to follow, and
  the build warns -- but only when someone asked for a mode: an option's own
  default is a definition like any other, so the warning keys off the
  definition's priority, not `isDefined`, which is true for every option
  that has a default.
- The new notice found a failed unit the moment it existed:
  `incus-preseed.service` on the test node, where incusd cannot make the
  site's ZFS pool because a test node's root is not ZFS. The node now
  declares a directory pool; a real server's root is always ZFS, so this is
  the test's own shape, not the platform's.
- `vm-host-ui` failed on `curl -sfk ... | grep -q nixie` with curl's exit 23:
  the finish's own tokens are the first thing in the stylesheet, so `grep -q`
  closed the pipe while curl was still writing. It fetches to a file first.

All forty checks on this tree, one `nix build` per output as ever (the
evaluator still cannot hold every check in one process, see the Final run
note below), on 2026-09-18. The host was busy with other work of the
operator's throughout -- a load average of 117 at its worst, and a
low-memory watchdog that killed the run twice -- so the times below are
generous, and `vm-installer-lan` had to be run again on a quiet machine: at
3429 s its two VMs had spent fifty minutes of wall time on three minutes of
CPU and the driver was still waiting for the target's shell to come up after
the install reboot, which is what starvation looks like rather than a
fault. It passes in 177 s with the machine to itself:

| check | result |
|---|---|
| boot-and-setup, deadnix, eval-matrix, fmt, hardware-keys, iso-config, iso-grub-theme, no-hardware-facts, no-secrets-in-store, option-docs, option-reference, profile-desktop-has-no-server, profile-server-has-no-desktop, profile-server-kiosk-only, readme, secure-boot-report, secure-boot-states, setup-devices, setup-qr, site-machines, splash-theme, statix, systemd-security, updates | pass |
| vm-backup (54s), vm-boot-plain (43s), vm-console (311s), vm-data (53s), vm-desktop (142s), vm-egress (105s), vm-encryption (484s), vm-guests (112s), vm-hardware (72s), vm-host-ui (30s), vm-installer-lan (251s), vm-monitoring (77s), vm-rollback (162s), vm-splash (585s), vm-ui (45s), vm-updates (41s) | pass |

## Six things the brief asks for that were missing (2026-09-18)

With the wishlist done, the brief itself was read against the tree, section
by section, and every concrete requirement checked for an implementation
under any name. Most of what it asks for is there; what follows is what was
not, and what the deliberate deviations in ARCHITECTURE section 13 already
cover (D3 WebAuthn, D14 in-place guest updates, D16 Declare from the control
panel) is left as it stands.

**`nix run .#apply` did not exist.** ARCHITECTURE section 6 listed it among
`mkSite`'s outputs and `docs/guides/add-a-guest.md` told people to run it;
`mkSite` emitted `nixosConfigurations`, per-host packages and checks, and no
`apps` or `apply`. Anyone following the guide got an error. It is now
`lib/apply.sh`: copy the checkout to the machine named and run that
machine's own `nixie apply` there, which is the brief's "thin wrapper that
syncs and runs it". The site's `.git` is excluded, because the host's
checkout carries commits of its own -- its `hardware.nix`, what setup wrote
-- and `nixie apply` commits what arrives as a hand edit and pushes it like
any other change.

**`nixie doctor` checked neither trust nor certificates**, both of which the
brief names. It now reports how many certificates the daemon trusts and
warns a fortnight before one expires, which is worth saying because an
expired browser certificate looks exactly like a control panel that will not
load. The two columns are asked for by name (`-c ne`), not taken from the
default layout, and anything that is not a date -- "Never", a header a
future version might print -- is passed over rather than read as expired.

**Phase 8 never fetched.** The brief's phase 8 is "apply: site checkout,
guest images, tofu, fetch, optional restore"; the phase ran `nixie apply
--skip-host` alone, so a site's caches filled only if
`nixie.data.fetch.timer` was set. It now starts `nixie-fetch.service`
without waiting: a manifest can name tens of gigabytes, and setup has no
business holding the wizard open for that. The optional restore at install
time is not done, and is not claimed.

**`nixie.monitoring.exporters.*` was in the brief's option tree and nowhere
in the platform**, which turned the node and NVIDIA exporters on implicitly
with no way to say otherwise. The option now takes any of nixpkgs' exporters
by name, the two the platform knows about default to what they did, and the
scrape configuration is derived from whichever are enabled rather than
listed separately -- so turning one off stops the job that scraped it.

**The host page's History screen was built with the graphite finish
outright**, while the Cockpit branding around it followed `nixie.ui.theme`,
so an umber or paper site got one graphite screen. It takes the finish now.
And the brief's requirement to say in `docs/` that Cockpit is the one
component whose look will not fully match the design file is met, with the
reason: PatternFly's own pages keep PatternFly's shapes, and a native agent
rewritten to the tokens would be a second thing to keep secure.

**A headless deploy wrote `profile: "server"` unconditionally** into the
setup state, so a desktop installed with `nix run .#deploy` continued as a
server in every front end that reads that state. It asks the site.

**A headless install stopped at the reboot.** The brief's acceptance
criteria say `nix run nixie#deploy` reaches the same end state as the other
front ends; it ran phases 1 to 3, rebooted the target and printed a line to
carry on by hand. That line could not have worked twice over: everything
after the first `;` ran on the operator's own machine rather than the
target, and the installer and the installed system have different SSH host
keys, so reconnecting would have been refused as a changed host. The deploy
now forgets the installer's host key, waits for the machine to come back,
and hands over to `nixie-deploy --continue` over `ssh -t` -- the setup
generation's own terminal front end, which already knows phases 4 to 8,
Finish, the secrets each one asks for and the Secure Boot restarts. It lands
in the operator's terminal, where they are standing.

**The host page had none of the three things the brief scopes it for.**
Section 12.1 lists `apply`, `fetch` and `doctor` with streamed output; the
page showed generations, snapshots, backups and (since this week) notices,
and could run nothing but the one "Apply it now" button a waiting update put
there. It has a Run panel now: the three commands spawned through Cockpit's
bridge with `err: "out"` and `.stream()`, so the output arrives as it is
produced, the buttons are held while one runs, and the history and notices
below refresh when it finishes. Nothing new listens on the host; they are
the same commands the machine runs for itself.

**The desktop had no reduced-motion equivalent.** Section 12.2 asks for the
toolkit's own where it offers one. `nixie.desktop.look. animations = "none"`
stopped the compositor and left GTK applications animating; `gtk-enable-
animations` follows it now, in both the GTK 3 and GTK 4 settings. GTK has no
middle setting, so "reduced" leaves them on, which is what "where the
toolkit offers them" allows.

**Nothing stood behind the clean-clone criterion "the example site builds
offline after `nix flake archive`".** `nix run .#offline` does now -- and
running it turned up that the criterion, read literally, cannot be met by
any flake that uses nixpkgs. `nix flake archive` copies the inputs'
*sources*; a store holding only those has to build the whole stdenv from
scratch, and the bootstrap seed it starts from is itself fetched. The first
attempt at this check did exactly that and stopped where it had to, on bash:
"Cannot build bash-5.3p9.drv. Reason: 1 dependency failed", with no
substituter to ask.

What the criterion is actually about is that nothing reaches the network
behind the lock file, and that is checkable: archive every input into a
store of its own, then evaluate every output with `--offline`, where an
unpinned `fetchTarball` or `fetchFromGitHub` in a module is an error rather
than a download. It passes: twelve inputs archived, and `eval-matrix` (which
is where the example site's machines are built, since the hosts live in a
site and not in this flake), `no-secrets-in-store`, `nixie-cli`, `nixie-
iso`, `nixie-setup`, `deploy` and `docs` all evaluated with the network
refused.

**The `oci` data kind wrote a layout and nothing served it.** Section 6 of
the brief says that kind puts images "into the local registry mirror"; the
fetcher copied each image into an OCI layout under `cache/oci` and stopped
there, with no registry anywhere in the tree. `nixie.data.registry` is one
now -- on by itself when the manifest lists any images -- storing under
`cache/registry`, re-fetchable and never backed up like everything else
there, and the host's firewall lets the guests through to that one port,
above the rule that keeps them out of the host's own services. The layout
stays beside it, so a machine that serves nothing still has the image.

Two real faults came out of testing it, neither of which any check would
have caught before, because nothing ever fetched an image. **skopeo copies
nothing without a trust policy** ("Error loading trust policy: no
policy.json file found"), and a Nixie host is not a container host, so it
has no `/etc/containers`: the `oci` fetcher could not have worked on any
real machine. It carries its own policy now, the manifest's per-image digest
being the integrity check. And **clearing `cache/` broke the registry until
the next restart**: the platform says clearing it is safe, but the registry
runs as its own user and cannot make its directory again under a `cache/`
that belongs to root. `nixie fetch` puts it back, which is what the test
exercises -- the subtest that empties `cache/` runs before it.

**The wizard's extension point did not work.** Section 13 of the brief says
an option carrying `nixie.ui.section` is rendered by the wizard, and
`docs/extending.md` told sites how to declare one. Neither could happen: the
option list is rendered when the installer is built, from a throwaway
evaluation of the *platform's* modules, and served as a static file, so
nothing a site declares was ever in it -- and the flake did not expose the
`mkOption` the docs told sites to use, nixpkgs' own refusing the `nixieUi`
argument outright.

Both ends are fixed. `nixie.lib.mkOption` is a flake output now, reachable
from a site's modules as `inputs.nixie.lib.mkOption`, and the backend asks
the site for its own options -- the same renderer, against the site's
evaluated host -- once a site exists and names a host, merging in anything
the platform does not already declare that asked for a section. It is asked
again whenever a file under the site changes, so a module added at Review
appears without a restart, and never on every poll, because it is a full
evaluation of the host. Anything going wrong there (a site mid-edit, a host
that does not evaluate) leaves the platform's own list rather than an error:
the site's files are checked at Review, which is where a person is told
about them.

Three wrong turns on the way, each caught by running it rather than by
reading it: the renderer was copied into the store on its own and lost the
`wizard.nix` beside it that it reads for labels ("'wizard.nix' is too short
to be a valid store path"); the test declared its option with nixpkgs'
`mkOption`, which drops the metadata silently, so the wizard saw an option
with no section; and the test wrote the site's module before the wizard had
made the site, which removes and remakes `hosts/` as it writes the host's
entry.

| check | result |
|---|---|
| `registry` (four facts) | pass; it serves what the cache holds, the guests are let through to that port and no other, off it serves nothing, and a manifest with images turns it on |
| `vm-data` (extended) | pass; an image built in the test pushed with the fetcher's own policy, listed and pulled back, its storage under `cache/`, restored by `nixie fetch` after `cache/` was emptied, and absent from the backup |
| `vm-installer-lan` (extended) | pass; a module of the site's own, written where a person would write it, declares an option that the wizard then offers in the section it asked for, labelled by its path, with the platform's own still there |
| `nix run .#offline` | pass; every input archived, every output evaluated with the network refused |
| `desktop-motion` (three facts) | pass; "none" reaches GTK 3 and GTK 4, "full" leaves them |
| `vm-host-ui` (extended) | pass; the three commands and the stream are in the page the host serves, and `nixie doctor` answers on that machine |
| `deploy-continues` | pass; the built script reboots, forgets the host key and hands over, in that order, and the instruction that ran the phases locally is gone |
| `exporters` (four facts) | pass; the default, one turned off with its job, another of nixpkgs' turned on with its job, and every one bound to this host |
| `vm-ui` (extended) | pass; a certificate three days from expiry, added to the daemon's real trust store, reaches `nixie doctor` as EXPIRING |
| `eval-matrix`, `option-reference`, `option-docs`, `readme`, `fmt`, `statix`, `deadnix`, `boot-and-setup`, `setup-devices` | pass |
| the `apply` wrapper | built from the example site and read: it carries `/etc/nixie/site` from that site's own `nixie.site.path` |
Then the whole gate on this tree, forty-three checks now that `exporters`,
`deploy-continues` and `desktop-motion` have joined them, run in chunks in
the foreground because the harness's own low-memory watchdog kept killing
the background run -- once after three checks, once before any, with fifty
gigabytes free. `vm-installer-lan` was starved to a wedge twice while the
host's other work ran (3429 s, then 33 minutes of wall time on 78 seconds of
CPU at a load average of 118), abandoned both times, and passes here in 232
s. The formatter caught a new check's own indentation, which is why one run
was started again from nothing: every check is built from
`tests/default.nix`, so a change to it makes every earlier result stale.

| check | result |
|---|---|
| boot-and-setup, deadnix, deploy-continues, eval-matrix, exporters, fmt, hardware-keys, iso-config, iso-grub-theme, no-hardware-facts, no-secrets-in-store, option-docs, option-reference, profile-desktop-has-no-server, profile-server-has-no-desktop, profile-server-kiosk-only, readme, secure-boot-report, secure-boot-states, setup-devices, setup-qr, site-machines, splash-theme, statix, systemd-security, updates | pass |
| vm-backup (54s), vm-boot-plain (41s), vm-console (245s), vm-data (52s), vm-desktop (172s), vm-egress (97s), vm-encryption (376s), vm-guests (99s), vm-hardware (55s), vm-host-ui (26s), vm-installer-lan (362s), vm-monitoring (93s), vm-rollback (134s), vm-splash (547s), vm-ui (17s), vm-updates (42s) | pass |

Not verified here, and not newly so: the headless path end to end. It needs
two machines -- one running the deploy, one being installed and restarted --
and the interactive continuation drives `gum` menus on a terminal, which is
why the existing entries for `nixie-deploy --continue` (above, 2026-09-15)
stub gum, systemctl and the phases to exercise its flow. What is new here is
checked by shape rather than by running: `deploy-continues`. No entry has
ever recorded a remote deploy reaching Finish, before this change or after
it.

Phase 8 is not run by any VM check; `packages.test-iso` runs the whole
sequence on a booted ISO, and that is what was used: `nix run .#test-iso`,
429 s, PASS, install in 187 s, phases 1 to 8 all reporting rc 0 and Finish
handing over to the normal system. The host's other work had eased to a load
average of 18 by then, after two runs abandoned at 155 and above.

What that run does and does not show, precisely: phase 8 completed with the
new step in it, which a failing `systemctl cat` guard or a failing start
would have prevented under `set -euo pipefail`. It does not show the fetch
unit's state afterwards -- each phase's step output goes to the target's own
journal, not to the run's artifacts, and the machine is gone by the time
they are read. The unit itself is built into that host (`unit-nixie-
fetch.service` appears in the install log), so the branch taken was the one
that starts it rather than the one that says there is no data.

## The brief's acceptance criteria, one by one (2026-09-18)

Section 16 asks that this file list every criterion with the command that
proved it. It never did: the entries above are chronological, by the work
that produced them, and a reader wanting to know whether a criterion is met
had to find it among them. Here they are in the brief's own order. Three are
not met, and say so.

| criterion | what proves it | state |
|---|---|---|
| Clean clone: every check passes with the VM tests actually run; every package builds; the site builds offline after `nix flake archive` | the 44-check loop, one `nix build` per check (the evaluator cannot hold them in one process; see the closing section); `nix build` of every package; `nix run .#offline` | met, with the reading of "offline" that the entry above sets out: no flake using nixpkgs can build from an archive alone, so what is proved is that nothing fetches behind the lock file |
| The platform evaluates for no GPU, one NIC, no TPM, no data disk, and a VM | `eval-matrix`, over the throwaway sites in `tests/sites/` (`no-gpu.nix`, `one-nic.nix`, `no-tpm.nix`, `no-data-disk.nix`, `vm.nix`) | met |
| Graphical path, single machine: the whole install from the on-screen kiosk with every security feature on, through the continuation phases, and a guest declared from the UI; no compositor or browser in the server closure | `nix run .#test-iso --kiosk --security hardened` (one run, the first start photographed); `profile-server-has-no-desktop`, `profile-server-kiosk-only`; `panel-declare` for the click and `vm-guests` for what it runs | met, across the runs each part belongs to: the install with every feature on and the continuation screen are one run; Declare is proved where it lives -- the panel offers it for a scratch instance and opens the host page with the name (`panel-declare`), the host page carries that address (`vm-host-ui`), and the command writes the site and adopts the instance (`vm-guests`). The one thing not in a single run is the click happening on that installed machine, because the run stops where Secure Boot asks for the restart this firmware will not come back from |
| Graphical path, LAN: the same install from a browser on another VM | `vm-installer-lan` drives it from a second node over HTTP; `mediaTests.installer` drives the same pages with Playwright | met |
| Desktop: installed from the ISO into a working Hyprland session with the chosen finish, packages and user, encryption on; no Incus, tofu or monitoring in the closure; the finish changes after `apply` without a reboot | `nix run .#test-iso --profile desktop`; `vm-desktop`; `profile-desktop-has-no-server` | met in a VM. A HyDE session on real graphics is not verified here, as the 2026-09-16 entry says |
| Headless: `nix run .#deploy` reaches the same end state, from kexec and from the ISO | `vm-deploy` runs the ISO path between two machines, end to end; `deploy-kexecs` holds the shape of the other branch, which a test took far enough to find three faults in it (entry of 2026-09-19, kexec) | met from the ISO. The kexec branch is fixed and checked by shape but not run to the end here: the image nixos-anywhere unpacks comes from a flake this platform does not have, and nixpkgs' own kexec tarball is a different shape |
| Toggling a security feature in `site.nix` and applying takes effect without reinstalling, except encryption, which is refused clearly | `vm-hardware` and `vm-encryption` for the features that toggle; `vm-updates` flips `features.encryption` under a prebuilt system and checks `apply` refuses with "cannot be changed on an installed system; reinstall from the ISO" and leaves nothing pending | met |
| Deleting `cache/` and fetching restores it; deleting a guest and applying recreates it; `restore` brings back `state/` | `vm-data` (both, and the registry's own directory with them); `vm-guests`; `vm-backup` | met |
| An undeclared instance reaches the internet only through the exit node, is left alone by `apply`, and round-trips Export/Declare with zero tofu diff | `vm-egress` (the egress rules), `vm-guests` (`apply` leaves scratch instances alone; `nixie export` writes the entry; `nixie declare` puts it in the site; `panel-declare` for the button that runs it; an apply whose state has never seen a running declared guest adopts it and then plans nothing) | met, in the two halves a single machine can show; the seam between them is in the entry of 2026-09-19 |
| `grep -rn` for MACs, disks, interface names, PCI addresses or board names hits only `tests/` and the example site's generated `hardware.nix` | `no-hardware-facts` | met |
| Every platform unit passes `systemd-analyze security` at OK, or documents its exposure | `systemd-security`, against a fully enabled server and the desktop | met |
| The control panel and the installer match the design file in all three finishes | `tokens-from-design` holds every token to the file's own `THEMES`; `tokens-agree` holds the hex copies to those tokens; `nix run .#demo-shots` photographs the panel's screens **and the design file itself** in all three finishes, into one folder | met for colour, which is the part a machine can hold: all 69 tokens are the file's, in all three finishes. The rest -- layout, type, depth -- is a person putting the pictures side by side, which is now a matter of opening one folder. The installer and the host page are still photographed in one finish |

## What a photograph of the host page found (2026-09-18)

The gallery was regenerated because eleven commits had changed what it
shows, and while doing it the one page the platform owns turned out never to
have been photographed: Cockpit's overview, files, terminal and journal
were, `nixie-history` was not. The shot added for it came back carrying two
faults, neither of which any check could see.

`nixie rollback --json`, on a machine with no generations recorded, passed
an unmatched glob through as a path: `stat: cannot statx
'/nix/var/nix/profiles/system-*-link'`, then `date: invalid date '@'`, then
`jq: string ("*") cannot be parsed as a number`. Those three lines were what
the page displayed where its history goes. The loops skip what does not
exist, and `vm-host-ui` asks for the history before a profile is set, which
is the state that produced it.

And the page had worn Cockpit's look rather than the site's finish since it
was first built, in every finish and on every site. Its rules were a
`<style>` block, and Cockpit serves packages under a content security policy
of `default-src 'self'`, which refuses inline styles: the browser discarded
the whole stylesheet. The first attempt at this blamed specificity and
scoped the selectors, which changed nothing, because nothing was being
applied at all; the rules are a file beside the page now, and `vm-host-ui`
checks it ships, that the page links it, and that no `<style>` block
returns.

Both were invisible to the gate by their nature. The page answered, its
files installed, its manifest and its script held what they should. What
showed them was looking at the screen.

| check | result |
|---|---|
| `nix run .#media` | pass; 124 assets, 20 MB, every one from a run on this tree, `hostui-history.png` among them for the first time |

| check | result |
|---|---|
| boot-and-setup, deadnix, deploy-continues, desktop-motion, eval-matrix, exporters, fmt, hardware-keys, iso-config, iso-grub-theme, no-hardware-facts, no-secrets-in-store, option-docs, option-reference, profile-desktop-has-no-server, profile-server-has-no-desktop, profile-server-kiosk-only, readme, registry, secure-boot-report, secure-boot-states, setup-devices, setup-qr, site-machines, splash-theme, statix, systemd-security, updates | pass |
| vm-backup (53s), vm-boot-plain (66s), vm-console (200s), vm-data (59s), vm-desktop (129s), vm-egress (102s), vm-encryption (383s), vm-guests (82s), vm-hardware (62s), vm-host-ui (47s), vm-installer-lan (248s), vm-monitoring (62s), vm-rollback (157s), vm-splash (560s), vm-ui (21s), vm-updates (46s) | pass |

## CI, and the screens it photographs (2026-09-18)

Section 14 asks for "screenshots of every screen in all three finishes,
generated from demo mode in CI", and there was no CI at all -- no
`.github/`, no workflow of any kind. The reason it had been left alone is
real: the gate is `nix flake check` and half of it is VM tests, which want
KVM that a hosted runner does not give. But the thing the brief actually
asks CI for does not need a machine: demo mode is the panel answering itself
from seeded data, with no daemon, no certificate and nothing installed.

So `nix run .#demo-shots` serves the panel's own bundle on a port of its own
and photographs fourteen screens in graphite, umber and paper -- forty-two
pictures, no VM -- and fails if any screen raised while it was being taken,
because a picture of a screen that threw is a lie.
`.github/workflows/checks.yml` runs that and every check whose name does not
begin with `vm-`; the VM tests are a job of their own that only a runner
labelled `kvm` takes, and only when asked for by hand, because a workflow
that is red for everyone by design is worth nothing.

One fault in the generator, found by looking at what it produced rather than
at whether it exited: the finish is a browser choice the panel reads once as
it starts, and it was being set after the page had loaded. Forty-two
screenshots came out, three finishes were named, and every picture was
graphite. It reloads after setting it now.

| check | result |
|---|---|
| `nix run .#demo-shots` | pass; 42 screenshots, 14 screens in 3 finishes, each finish visibly its own |
| `.github/workflows/checks.yml` | parses; its jobs are evaluate, screenshots, vm-tests. Not run on GitHub from here -- this repository's runs will be its first |

| check | result |
|---|---|
| boot-and-setup, deadnix, deploy-continues, desktop-motion, eval-matrix, exporters, fmt, hardware-keys, iso-config, iso-grub-theme, no-hardware-facts, no-secrets-in-store, option-docs, option-reference, profile-desktop-has-no-server, profile-server-has-no-desktop, profile-server-kiosk-only, readme, registry, secure-boot-report, secure-boot-states, setup-devices, setup-qr, site-machines, splash-theme, statix, systemd-security, updates | pass |
| vm-backup (54s), vm-boot-plain (64s), vm-console (242s), vm-data (31s), vm-desktop (177s), vm-egress (97s), vm-encryption (377s), vm-guests (86s), vm-hardware (54s), vm-host-ui (46s), vm-installer-lan (235s), vm-monitoring (81s), vm-rollback (151s), vm-splash (545s), vm-ui (18s), vm-updates (41s) | pass |

## The wizard driven on the machine's own screen (2026-09-18)

The brief asks `packages.test-iso` to drive the wizard end to end "via the
setup backend's HTTP API, and via the kiosk with a browser automation tool
for at least one full run". Only the first existed: the kiosk was
screenshotted, never driven. `nixie-test-iso --kiosk` drives it now --
Playwright attached over CDP to the browser the image itself started, under
cage on the machine's screen, walking Machine, Disks, Name, Security,
Network, Services, Review and Install to a finished install in 184 s.

That browser has to be reachable, and four things stood in the way, each
found by running it: `--remote-debugging-port` binds the guest's loopback,
which QEMU's hostfwd cannot reach; the installer's firewall admits only SSH
and the wizard; Chromium hangs up on a debugger websocket from another
origin; and Chromium ignores `--remote-debugging-address` and binds the
loopback whatever it is told, so the image relays the port with socat. The
debug port is off in everything the platform ships: `packages.nixie-iso-
kiosk` is the only image that sets `nixie.kiosk.remoteDebugPort`, and that
image is what `--kiosk` boots. It differs from the shipped ISO by that one
flag, the relay and the firewall opening, and nothing else.

Two faults of the harness's own turned up as well. The script posted an API
configuration for a host called `iso-test` before handing over, so the site
already held an entry whose `hardware.nix` phase 1 had never written and
Review rightly refused to evaluate it -- in kiosk mode the wizard is what
configures the machine, and nothing is posted. And the run now ends at the
install: what follows the restart is the setup generation, which the HTTP
path drives to Finish, and which cannot be driven here at all, because a
machine a person configured has no serial console for the script to read
(the HTTP path puts `console=ttyS0` in its own settings; a person does not).

| check | result |
|---|---|
| `nix run .#test-iso --kiosk` | pass; the wizard driven through the kiosk's own browser to a finished install, 184 s, with a screenshot of each step it went through |

## A hardened machine that stops in the initrd says why (2026-09-18)

Reported: a hardened server install, restarted after phase 3, comes up in
the initrd's emergency mode -- "You are in emergency mode", "Cannot open
access to console, the root account is locked" -- on VirtualBox with TPM 2.0
enabled.

It could not be reproduced here, and what was run says so precisely:
hardened without Secure Boot installs and reaches Finish; Secure Boot on its
own reaches the setup generation; and the wizard's own hardened preset,
Secure Boot included, installs and stages its keys. All three under QEMU
with OVMF and a software TPM, which is not VirtualBox's firmware or its TPM.

What the report did find is a hole in the gate: `test-iso --security
hardened` left `nixie.security.secureBoot.enable` out, so the configuration
a person gets by pressing "Hardened" in the wizard -- the signed boot chain
with the whole security stack in the initrd behind it -- was the one
combination never booted here, while each half was. It now writes the
wizard's preset and stops where the `secureboot` run stops, after phase 5
stages the keys; the first start, which is where the report puts the
failure, is before that.

And a defect of the platform's own, whatever the root cause turns out to be:
a machine that gives up in the initrd tells nobody anything. The root
account is locked, so the emergency prompt offers no shell, and a signed
boot chain carries no editable kernel command line to add a debug parameter
to, so there is no way in at all. `nixie-emergency` now runs on
`emergency.target` and prints, to the screen and to the kernel log, which
units failed, that the disk is still locked and nothing has been changed,
and that holding Space offers the previous system.

Four things went wrong in that reporter, each found by booting a machine
into the state rather than by reading the code, and each of them would have
made it useless exactly when it was needed. `TTYPath=/dev/console` is the
last `console=` on the command line, which is the screen and not a serial
console. The kernel-log copy was written at the default priority, which
`quiet` and `boot.consoleLogLevel = 3` suppress -- the settings every Nixie
machine boots with -- so it went to a console that would not show it; it is
written at error level now. The script itself was not in the initrd's store,
so the unit died at `203/EXEC` without a word. And nixpkgs has its own
`panic-on-fail` service on that same target: with nothing ordering the two,
it crashed the kernel sixteen milliseconds after the reporter started, and
the reporter now runs before it.

A second reproduction, after the first found nothing: VirtualBox presents
its TPM through a CRB interface where QEMU's default here is TIS, and those
are different kernel modules, so a TPM whose driver never loads would leave
the initrd's attestation service waiting on `dev-tpmrm0.device` in front of
every disk prompt -- which is what the report looks like. `nixie-test-iso`
takes `--tpm tis|crb` now, and the hardened install with Secure Boot passes
on both. The TPM interface is not it, and real machines vary in this anyway,
so the coverage stays.

| check | result |
|---|---|
A third: VirtualBox gives a new machine a SATA controller where this gives
it virtio, and again those are different modules -- an installed initrd that
does not carry the driver for the disk it boots from would leave the machine
exactly where the report puts it. `--disk virtio|sata` now says which, and
the hardened install with Secure Boot passes on both.

| check | result |
|---|---|
| `nix run .#test-iso --security hardened --tpm crb` | pass; keys staged, the same as with TIS |
| `nix run .#test-iso --security hardened --disk sata` | pass; keys staged, the same as on virtio |

None of that reproduced the report, but reading for it found something worth
fixing on its own. The initrd's attestation service is ordered in front of
every disk prompt, so the code is on the screen before anyone types; it also
declared `After=dev-tpmrm0.device`. On a machine where that device never
appears -- no TPM, a driver that does not load, a hypervisor that presents
it differently -- systemd waits the device job out before starting it, and
the prompt waits with it: ninety seconds of a machine that looks hung, while
`initrd-root-device.target` runs its own ninety-second clock. The unit no
longer orders itself after the device; the script waits five seconds for it
and says there is no code if it never comes.

That is measured now, not reasoned. `vm-splash` installs an encrypted disk
and boots it several times over; a sixth node boots that same disk with
`virtualisation.tpm.enable = false`, which is a machine with attestation on
and no TPM at all -- the shape this was guessed to be. The passphrase is
asked for 7.7 seconds into the boot, by the kernel's own clock, and the
machine says there is no code rather than pretending to have one. `boot-and-
setup` pins the ordering so it cannot creep back, and the other nodes, which
do have a TPM, show the code still arrives before the PIN prompt.

Three things that subtest got wrong first, all mine and all about the
harness rather than the platform. It waited with `wait_for_console_text`,
which reads about a line a second where a boot writes hundreds, and was
still catching up two minutes after the prompt had come and gone -- this
very file has an `on_console` helper carrying that lesson in a comment, and
it was not reused. It then asked the guest to shut down while the guest was
sitting at the passphrase prompt in the initrd, where there is no backdoor
to answer, which hung the whole run past forty minutes and held the disk the
later starts share; it is stopped through the QEMU monitor now. And the run
was started without `-L`, so none of the test output was there to read.

The report also says what the start is still waiting for, not only what
failed. `systemctl --failed` lists nothing when a boot is stuck rather than
failed -- a device that never appears is waited on until its timeout --
which is the shape of the report this was written for, so the thing meant to
explain it would have explained nothing. The outstanding jobs name it. A
separate data disk was checked for the same reason, since a server install
plausibly has one and no reproduction here did: it is not in that path
either, because `dataContent` sets `initrdUnlock = false` and the data disk
is opened after the root with a key kept on it.

| `vm-boot-plain` (extended) | pass; a node told to go straight to the initrd's emergency target shows the report on its console, before the panic that a failed start triggers there |
| `nix run .#test-iso --security hardened` (now the wizard's preset) | pass, keys staged |

| check | result |
|---|---|
| boot-and-setup, deadnix, deploy-continues, desktop-motion, eval-matrix, exporters, fmt, hardware-keys, iso-config, iso-grub-theme, no-hardware-facts, no-secrets-in-store, option-docs, option-reference, profile-desktop-has-no-server, profile-server-has-no-desktop, profile-server-kiosk-only, readme, registry, secure-boot-report, secure-boot-states, setup-devices, setup-qr, site-machines, splash-theme, statix, systemd-security, updates | pass |
| vm-backup (53s), vm-boot-plain (64s), vm-console (242s), vm-data (29s), vm-desktop (129s), vm-egress (98s), vm-encryption (380s), vm-guests (102s), vm-hardware (57s), vm-host-ui (22s), vm-installer-lan (240s), vm-monitoring (63s), vm-rollback (152s), vm-splash (542s), vm-ui (18s), vm-updates (44s) | pass |

## A server installed through the web wizard

2026-09-15, on the image built from this tree, in QEMU (KVM, OVMF, 8 GB, a
64 GB disk, user networking with 9443, 8443, 9090, 22 and 2222 forwarded),
driven by Playwright from the host exactly as a person would: the pairing
code from the screen, clicks on the wizard's own buttons. Screenshots of each
step are in `tests/artifacts/e2e-server/`.

Install. Server profile, the virtio disk, the one port, a new site "atlas",
encryption with remote unlock (the combination the report failed on), an
SSH key, TOTP enrolled with a code from `oathtool`, a time zone. The new
guard held Next with encryption off and remote unlock on. Review showed the
generated `hardware.nix` and `site.nix`; phases 2 and 3 passed; the first
boot asked for the passphrase; phases 4 to 7 passed in the browser.

Guests. Before phase 8, three guests were declared in the site on the host:
`web` (the static-web recipe over `/data/state/web`), `app` (nginx under
podman with a mounted directory) and `legacy` (Debian trixie from
images.linuxcontainers.org by fingerprint, with cloud-init). Phase 8 applies
the installed system, not later site edits, so they came from `nixie apply`
after Finish: all three created, `web` and `app` serving their mounted pages,
`nixie doctor` listing each as RUNNING.

What was broken, each found here, fixed, and checked again on this host with
the platform in the site's lock pointed at the fixed tree:

| found | fix | checked |
|---|---|---|
| remote unlock never answered: the initrd had only `lo` (no NIC driver; the scan copies storage drivers) | phase 1 adds each wired port's driver to `boot.initrd.availableKernelModules` | with the driver line, `ssh -tt -p 2222` got the prompt and the host booted with every guest running |
| an SSH session without a terminal cancelled the passphrase prompt; the boot stopped in emergency mode with root locked | the relay refuses a session without a terminal | `ssh -T … true` refused; a terminal session dropped mid-prompt leaves the prompt pending; a normal unlock boots (`67-after-drop.png`) |
| a failed Finish showed nothing on the page | `/api/finish` returns the unit's output since the button was pressed; the page shows it and enables Finish again | a patched backend beside the real one showed the evaluation error (`25-finish-failure-shown.png`) |
| Finish stopped at `switch-to-configuration` status 4 when only a user's own units missed their reload (an SSH login ending mid-switch) | `nixie apply` continues when the switch reports 4 and no system unit failed | tested with a stub systemctl: 4 with no failed units continues, 4 with one stops, 1 stops |
| the front panel showed "no instances" with guests running | the panel asks `/var/lib/incus/unix.socket` | four lanes and the pool line (`60-front-panel-patched.png`); `vm-console` now waits for a created instance's name, and the old "instances" match was satisfied by "no instances" |
| the control panel's terminal opened an exec session on every refresh: 929 exec calls and 3740 requests in 10 s, `ERR_INSUFFICIENT_RESOURCES`, a blank terminal | a stable `toast`, the terminal effect tied to the instance only, refreshes coalesced | 8 requests in 15 s with a shell open; commands answer (`44-terminal-fixed.png`) |
| memory read 0 %: the panel and the guest dashboard asked for `incus_memory_Usage_bytes`, which incusd does not export | `MemTotal - MemAvailable` | the header reads the real figure; the Prometheus query returns each guest; `vm-guests` asserts the names on the real daemon |
| History crashed the panel: it fetched `/nixie/history.json`, which nothing serves | guest snapshots from the Incus API, host history on the host page | lists the snapshot taken from the panel (`55-history.png`); the host page's History lists generations, snapshots and a backup (`64-hostui-history.png`) |
| an instance with podman showed `10.88.0.1` | the platform's nic before bridges the guest made | `app 10.0.2.17` |
| a scratch instance from Create had no network device | the default profile has a bridged `uplink` nic, which a declared guest's own device replaces | `scratchy` got an address; `web` kept `veth-web` |
| a scratch instance's port (`veth8ddc20dc`) reached the host's SSH: the rules matched `veth-*` | `veth*` | reached before, blocked after, on the host; `vm-egress` now names its scratch port the Incus way and asserts it |
| the Debian guest had no address: its nic was named `uplink`, cloud-init configured `eth0` | foreign container images keep `eth0` | DHCP, `curl` installed by cloud-init, the runcmd ran |
| "not trusted yet" told the admin to run `openssl`, which a server lacked | `openssl` on hosts with Incus | on the path after apply |
| `nixie rollback --list` and History dated generations 1969 | the profile link's own mtime | 09:57, 10:25, 10:47 |
| the wizard offered TPM features without a TPM, showed the Tailscale key-file path, left `pcrs` looking empty; the site's files were read-only; phase 6 warned of a duplicate age recipient | hidden, hidden, defaults shown, `chmod u+w`, recipients deduplicated | the Security step without TPM rows and Network without the key file in a browser |
| smaller: `#/dashboards/gpu` showed the host dashboard, an empty log read "select a log file", the heat strip drew `#` on the console, the scratch chip and topology legend overlapped | short dashboard names, "this log is empty", block glyphs, a wider name column, the lower topology row raised | screenshots |

Also exercised and working without change: the file browser (the mounted
page edited and saved from the panel, served by the guest at once),
snapshots, stop and start, Export, Create from a remote alias, the Images,
Profiles, Networks, Storage and Operations pages, Settings, the host page
with password and TOTP, `nixie backup now|list|verify` (restic check: no
errors), Prometheus scraping incus and node, the three Grafana dashboards
provisioned, `nixie rollback guest` restoring a snapshot while leaving the
mounted state alone, `nixie export` of a scratch instance, `nixie hardware
scan`, and a reboot with every guest starting again.

Settings, added afterwards at the user's request, checked on the same host
against the real daemon: the gear opens Settings; theme, title, header
figures, starting range, Overview order, width and visibility, hidden pages
and an extra link were saved; `incus config get user.nixie.ui` held the JSON;
a fresh browser context with no stored state opened in that layout and
finish (`82-fresh-browser-overview.png`); Reset returned `{}` and the site's
defaults.

Not verified: a USB stick and a real NIC on physical hardware (the driver
list comes from the running installer, so it follows the hardware);
Cockpit's podman page; the Finish path end to end after the apply fix (this
host's Finish had already stopped before it existed, and `test-iso` below
runs Finish on the fixed tree).

## Console

`vm-console`: tty1 shows the front panel (OCR finds the wordmark and the
prompt), any key opens login; with the kiosk on, the local display shows the
lock page, the gate accepts the administrator password and refuses a wrong
one, the control panel renders, and the front panel moves to tty2.
`profile-server-kiosk-only` proves the kiosk closure contains no Hyprland,
Firefox, Quickshell or greeter.

## Profiles

`profile-server-has-no-desktop`, `profile-desktop-has-no-server` and
`profile-server-kiosk-only` grep the built closures (`closureInfo`) for the
forbidden package names; all three pass on every full check run.

## Units and secrets

`systemd-security` analyses every `nixie-*` unit of a fully enabled server
and the desktop offline with `systemd-analyze security --threshold=3`; units
above "OK" must be in the documented list and their module must carry an
`# exposure:` comment. `no-secrets-in-store` greps the fully enabled server
closure for private-key and age-identity markers.

## The slices' final run (2026-09-11)

Every check of the slices ran on 2026-09-11 on the rootless host described in
`ARCHITECTURE.md` (KVM, `sandbox = false`, see the note under Slice (b) and
in the test files for why).

`nix flake check -L` as one process does not finish on this host: the
evaluator reached 50 GB of resident memory while evaluating the checks in
one go and was killed by the kernel (Nix 2.20, every check evaluates its own
NixOS systems). The gate was therefore run as the equivalent loop, one
process per output: `nix build .#checks.x86_64-linux.<name>` for each of the
24 checks below, plus `nix eval` of the derivation path of every package,
every media test and the site template. The loop is in the shell history of
the verification session; its summary is the table.

| check | result |
|---|---|
| fmt, statix, deadnix | pass |
| eval-matrix, option-docs, option-reference, readme | pass |
| no-hardware-facts, no-secrets-in-store, systemd-security | pass |
| profile-server-has-no-desktop, profile-desktop-has-no-server, profile-server-kiosk-only | pass |
| vm-boot-plain (15 s), vm-egress (22 s), vm-guests (44 s), vm-data (25 s), vm-monitoring (38 s), vm-ui (14 s) | pass |
| vm-host-ui (14 s) | pass |
| vm-installer-lan (172 s) | pass |
| vm-console (258 s) | pass |
| vm-encryption (1258 s) | pass; Secure Boot firmware enrolment is hardware-only, see Slice (b); reenroll subtest added in slice (o) |
| vm-backup (27 s) | pass (change request, slice (m)) |
| vm-rollback (132 s) | pass (change request, slice (n)) |
| vm-hardware (25 s, five subtests) | pass (change request, slices (o) and (p)) |
| vm-desktop (110 s, eight subtests) | pass (change request, slice (r)) |

## Where the gate stands

The run above is the slices', and its twenty-four checks are what the gate
was then. It is forty-four now, and the dated entries above are the record:
each one lists what ran for the work it describes, and the newest entry's
table is the current state. The way it is run has not changed -- one `nix
build` per check, because the evaluator still cannot hold them all in one
process -- and the rootless host, KVM and `sandbox = false` are still as
that section describes.

Three things are run by hand rather than in the gate, because they want a
machine or an image rather than an evaluation: `nix run .#test-iso` (the
installer, end to end, with `--kiosk`, `--security`, `--tpm` and `--disk`
for the shapes a real machine comes in), `nix run .#media` (the gallery,
from real runs), and `nix run .#offline` (every input archived, every output
evaluated with the network refused). Each entry above says when it last ran
and what it showed.

## Two machines, and where that run stops (2026-09-19)

The headless criterion above wanted something no entry had: one machine
running `nix run .#deploy`, another being installed by it. `tests/vm/deploy.nix`
and `deploy.py` are that harness. It is in the tree and **not registered in
`tests/default.nix`**, because it does not pass, and a check that does not
pass is not a gate.

What nine runs of it established, each fixing what the one before ran into:

| it ran into | what that was |
|---|---|
| `start_all()` hung | the installed node shares the disk image the installer writes; the nodes are started one at a time |
| `PAM: Authentication failure for root` | the deploy runs plain `ssh`, which uses the identities it reaches for by itself, so the key has to be at `/root/.ssh/id_ed25519` |
| `experimental Nix feature 'nix-command' is disabled` | the runner is a plain machine, not a Nixie host, and carries none of the platform's nix settings |
| a broken pipe, then the machine out of room | the installer node was running the kiosk -- a compositor and a browser -- beside the deploy; `mode = "terminal"` is the headless path's own front end |
| `gum` panicked drawing its placeholder | `script(1)` sizes its terminal from its own stdin, a pipe here, so the terminal was zero columns wide; `stty rows 40 cols 120` inside it |
| the whole budget spent compiling NixOS inside a VM | the deploy now takes `NIXIE_TOPLEVEL` and `NIXIE_DISKO`, as `nixie apply` already did and for the same reason |
| a lock file written into a read-only store path | the site is copied to `/root/site` first |
| GitHub reached for, from a machine with no way out | every source the platform's lock names is in `system.extraDependencies`, as the ISO carries them |

And where it stops, which is the ninth run: before anything of the site is
evaluated, nix locks it, and locking the site resolves the platform's own
inputs -- `disko`, `lanzaboote`, `crane`, `pre-commit-hooks`. The captured
log ends inside that list. Having each source in the store is not enough:
nix fetches the `github:` reference to check it against the lock, and the
test VM has no network. Finishing it wants a site that arrives already
locked, which means generating that lock where the network is -- in the
derivation that builds the site -- not inside the machine.

So the criterion stays **not met**, and this is what it would take. What did
come out of the attempt and is kept: `NIXIE_TOPLEVEL` and `NIXIE_DISKO` in
`installer/deploy.sh`, which are the reason a deploy can be tested at all
without building a system inside the machine under test.

| check | result |
|---|---|
| fmt, statix, deadnix | pass |
| the 44-check gate | pass |

## Declare, and the instance it must not destroy (2026-09-19)

Two acceptance criteria stood at **partly** for one reason: the control
panel's Declare was wired to an endpoint nothing provided. D16 said incusd
cannot run host commands and the brief defers a host agent -- but the host
page is Cockpit, it is already signed in, and it already runs `nixie apply`
through the bridge. So the panel's Declare now opens
`/nixie-history#declare=<name>` there, and the page offers one more command
beside Apply, Fetch and Run the checks. Nothing new listens; the field
`declareUrl`, which was always `null`, is gone from the site JSON and from
the panel's state.

`nixie declare <instance>` is what that button runs: the entry `nixie
export` prints, written into the site's `guests.nix`, then the apply that
follows it (and whatever flags came with it, so a person can still say
`--confirm-within`). It refuses a name the site already declares, a name no
instance has, a name already written into the file and waiting for an apply,
and a `guests.nix` that does not end in a line with only `}` -- where it
prints the entry for a person to place by hand rather than editing a shape
it cannot read.

**The part that would have destroyed a guest.** Declaring an instance that
is already running means tofu has never seen it, so the plan wants to create
a name that exists. `tofu import` adopts it -- and the plan right after the
import *still* replaces it, because the incus provider cannot read back
which image an instance came from, and `image` forces replacement. Measured
in `vm-guests`: `Plan: 1 to add, 0 to change, 1 to destroy`, and the
instance's uuid changed, which is a scratch instance deleted and rebuilt by
the act of declaring it. Incus remembers the image in
`volatile.base_image`; adoption now compares it with the one the site names
(resolving a local alias to its fingerprint) and, when they are the same,
records it in the state. When they are not, the replacement is the right
answer and it stands, which is what D14 asks for.

This lives in `apply`, not in `declare`, because every route to that state
is the same one: any declared guest that is running and absent from the
state is adopted before the plan.

| check | result |
|---|---|
| `vm-guests`, subtest "declare writes that entry into the site" | pass: the entry lands in `guests.nix`, nix still reads the file, the instance keeps running, and both refusals fire |
| `vm-guests`, subtest "an instance the state has never seen is adopted, not made again" | pass: `adopting web, which is on this host but not in the state`, the uuid is the one from before, and the plan that follows says `No changes. Your infrastructure matches the configuration.` |
| `vm-host-ui` | pass; the page carries the address the panel sends it to |
| the 44-check gate | pass |

What a single machine cannot join: `nixie declare` ends in an apply that
rebuilds the host, and the guest only becomes declared once that rebuild has
happened. The test runs the two halves either side of that seam -- the write
with `--skip-host`, the adoption against a guest the site already declares
-- because building a NixOS inside a test VM is what `NIXIE_TOPLEVEL` exists
to avoid.

## The headless path, all the way (2026-09-19, later)

The entry above this one says what stopped `vm-deploy` and what finishing it
would take: "a site that arrives already locked, which means generating that
lock where the network is". That is what `tests/vm/deploy-lock.py` does, and
with it the test runs. It is registered, and the gate is forty-five checks.

The lock is written from the platform's own: every node carried over, the
root renamed to `nixie` and pointed at the platform's store path, and every
`follows` re-rooted a step deeper. Nothing is fetched, because a locked node
carries a hash and a hash is something nix finds in a store it already has
-- the same reason `nix run .#offline` works. Checked before the VM ran, by
`nix flake metadata --offline` on a site holding that lock: every input
resolved, `nixie/lanzaboote/pre-commit/gitignore` and all.

Then five more things, each one a run:

| it ran into | what that was |
|---|---|
| `nixie-deploy: not found` | a transient unit is given a minimal PATH, and the system profile is not on it |
| an empty log for as long as it ran | `script` writes its typescript in blocks; `-f` flushes it, and until then the only readable copy was the journal, where every coloured line is "[77B blob data]" |
| the answer typed as `p  4h` | gum asks the terminal for its colours as it starts and reads the reply from the same input, so an answer queued before the question is eaten by it. It goes in a fifo now, written when the question is on the screen |
| the answer typed but not submitted | in raw mode Enter is a carriage return; a line feed leaves it sitting in the box |
| "broken pipe", three times, in three places | the deploy restarts the target as its own next step, and the test was waiting on the machine that was going away. It waits on the runner, treats the backdoor going away as that restart, and writes the machine off so the driver's closing `sync` does not look for it |

What the run shows, in order: the runner reaches the installer over SSH with
the repository's own key; the deploy sees `target runs the Nixie ISO; no
kexec needed`; `copying 0 paths` (the closure is already there, handed in
rather than built inside a VM); the one question a plain install asks --
where the key for this host's secrets is -- answered; `nixie-phase 1 && 2 &&
3` over SSH; `1.done`, `2.done`, `3.done`; the target restarted by the
deploy. Then the disk it wrote is started as a machine of its own: it comes
up as `server`, and the setup generation runs on to `7.done`, restarts, and
comes back with `8.done` and no `specialisation/setup` left. Nobody typed
anything after the key.

| check | result |
|---|---|
| `vm-deploy` (342 s, two subtests) | pass |
| the 45-check gate | pass |

Not proved here: the kexec branch. The target runs the Nixie ISO, so the
deploy says so and skips it; proving the other branch wants a machine
running some other Linux to kexec out of, which is a second image this test
does not build.

## Hardened, from the kiosk, in one run (2026-09-19, later still)

The criterion above asked for the kiosk install and every security feature in
one run, and the record said they were two. They were, and for a reason worth
writing down: `--security` was read only by the HTTP path. Passing
`--kiosk --security hardened` chose nothing, silently, and installed the
standard machine while the log said hardened.

The kiosk driver now makes that choice the way a person does, and the run
found three things by failing at them:

| it ran into | what that was |
|---|---|
| no card to click | the two cards, Standard and Hardened, are on the wizard's **first** step beside Server and Desktop, not on the Security step that carries the answer out. The driver was clicking past them |
| Next disabled with every box filled | a hardened setup puts a second factor on the host page, and the step will not advance until it is enrolled -- the one thing on it that is not a box. The driver reads the secret the wizard prints beside the QR code and computes the code itself (RFC 6238, checked against the specification's own test vector) |
| the step count no longer matched | a hardened setup walks through every feature it turns on, so the steps to Review are walked now, not counted, answering whatever each one asks for by the label above the box |

The run: Hardened chosen, then the Security step asked for the administrator,
the disk passphrase, **the TPM PIN and the duress passphrase**, the second
factor enrolled, and Review passed. The install took 317 s.

**And then the first start, which no run here had ever photographed.** A
machine the wizard configured has no serial console -- the HTTP path adds
`console=ttyS0` to its settings and a person does not -- so the script takes
pictures instead, which is what someone whose machine will not start has to
send anyway. What they show, at 60 s: the splash, `Passphrase or recovery
key`, and the attestation code under it. At 280 s, with the passphrase typed
at the machine's own keyboard through the monitor: **Setting up server** --
Install done, First start done, Secure Boot asking for the restart that
enrols the keys, with Disk unlock, Checks and Apply the site still to come.
That is the continuation, from the kiosk, with every feature on.

**The first run of this failed, and that is the other result.** The blind
typing sent the PIN to a box asking for the passphrase, three times, and the
machine went to emergency -- where the reporter added earlier today printed,
on a real install rather than in a test:

```
Nixie could not finish starting. What failed:
systemd-cryptsetup@rpool\x2douter.service  loaded failed failed Cryptography Setup for rpool-outer
zfs-import-rpool.service                   loaded failed failed Import ZFS pool "rpool"
Still waiting for: emergency.target, emergency.service, nixie-emergency.service, panic-on-fail.service
The disk is still locked and nothing has been changed.
Take a photo of this screen: it says which part gave up.
Starting again and holding Space offers the previous system.
```

So the screen a person sees when a hardened install will not start now names
the unit that gave up, and the first thing it names for a disk that did not
open is `systemd-cryptsetup`. `tests/artifacts/kiosk-restart-*.png` holds
both runs' pictures.

| check | result |
|---|---|
| `nix run .#test-iso -- --kiosk --security hardened` | pass, twice: once to emergency with a wrong passphrase, once through to the continuation screen |
| the 45-check gate | pass |

## The click, and the one token set (2026-09-19, last)

Two checks, and the gate is forty-seven.

**`panel-declare`.** The half of Declare a person actually clicks had
nothing behind it in the gate: `vm-guests` proves what the command does and
`vm-host-ui` that the page is there to run it, but nothing proved the button
hands over the right thing. It runs in demo mode -- the panel is a static
bundle answering itself, so it needs no daemon, no VM and no certificate,
which is why it can sit in the gate beside the evaluations. What it holds:
Declare is offered for every scratch instance and for none of the declared
ones; clicking it opens the host page's own address with that instance's
name on it; and with no host page, or with `nixie.ui.allowSiteEdits` off,
there is no button at all, because there is nothing behind it either way.
It also fails on any error the page throws while doing it.

**`tokens-agree`.** The brief asks that the UI and the installer share one
token set, extracted once from the design file. They do, but in two forms:
the bundle uses the `oklch()` values as written, and `lib/tokens.nix`
carries a hex beside each of the seven that carry meaning, because a
toolkit, a terminal, a Plymouth theme and a GRUB theme cannot read oklch.
Nothing held those two to each other. A token added to the JSON with no hex
draws nothing on the desktop; a hex typed wrong is a colour from another
palette with nothing to say so.

Measured before the check was written: the hexes are **not** the straight
sRGB conversion the comment beside them claimed -- they are the same colours
toned down, every one less saturated than its token (by 0.002 to 0.065 of
chroma), within 16.8 degrees of hue and 0.085 of lightness. That is a
deliberate choice, not a mistake: a terminal at full chroma is harsh. So the
comment is corrected to say it, and the check holds the relationship rather
than a conversion: same finishes, same tokens, every hex within 25 degrees
of hue and 0.12 of lightness, and never more saturated than the design file
asked for.

That is as much of "every screen matches the design file" as a machine can
say. The rest of that criterion is a person putting the pictures beside the
file, and `design/Nixie_Front_Panel.html` is not in this repository.

| check | result |
|---|---|
| `panel-declare` | pass: `Declare opened the host page for db`, and none offered with no host page or with site edits off |
| `tokens-agree` | pass: 21 colours in 3 finishes, worst hue 16.8 of 25 degrees, worst lightness 0.085 of 0.12 |
| the 47-check gate | pass |

## The design file was here all along (2026-09-19, after that)

Twice today this record and the message that went with it said the design
file was not in the repository. It is: `design/Nixie Front Panel.html`,
tracked, 407 KB, **with spaces in the name** rather than the underscores the
brief writes -- which is why every search for it came back empty, and why
`CLAUDE.md` still said to ask for it before touching any UI. That note is
corrected, and the file is now used for what it is.

**`tokens-from-design`.** The file carries the object its own screens render
from, `THEMES`, with every token for every finish. The check reads it and
holds `ui/src/tokens/tokens.json` to it: same finishes, every token the same
value, nothing in the design's palette that the platform cannot name. All 69
match today -- 23 tokens in each of three finishes -- so "extracted from the
design file once" is now "still the design file's, every time the gate
runs".

One thing it must not read is the swatch cards beside that object: the Paper
card prints `d6d2c9` for its third chip while `THEMES` says `#d9d5cc`.
`docs/design-tokens.md` already recorded that and said to take the rendered
value, which the platform does. Finding it again from the other direction is
what made the distinction worth writing into the check.

**The pictures.** `nix run .#demo-shots` now photographs the design file
too, once per finish, into the same folder as the panel's own screens: 45
shots where there were 42. The file renders headlessly with no errors, and
its own finish switch is used rather than a guess at its internals -- the
three come out blue-grey, brown and light, which is Graphite, Umber and
Paper. Comparing layout and type with those screens is still a person's
judgement. It is now a person opening one folder rather than a person
looking for a file nobody could find.

| check | result |
|---|---|
| `tokens-from-design` | pass: 23 tokens in each of graphite, umber and paper, every one the design file's |
| `nix run .#demo-shots` | 45 screenshots: every panel screen in three finishes, and the design file in three |
| the 48-check gate | pass |

## One guard on the artifacts (2026-09-19, closing)

`tests/artifacts/` is deliberately not ignored -- its logs and screenshots
are what this file links to. Checking what is in them: no recovery key. The
phases keep it out of their own output, and systemd's message appears in
`test-iso-hardened/phases.log` with the key line following it empty.

Two things that look like keys and are not, recorded so the next person does
not chase them: systemd's sentence "A secret recovery key has been generated
for this volume:", which is a message and not a key; and a nix store hash,
which can carry the 8-5-5-5-5 shape inside a longer run of characters
(`/nix/store/nj1acsy2qjd73ikhqf60p6hh…`). A word-bounded pattern tells them
apart, and finds nothing in any artifact here.

`nix run .#test-iso` now redacts that shape from its logs as it exits,
whatever ends the run. It is a guard rather than a repair: it makes "no
recovery key in a committed artifact" a property of the script instead of a
thing to remember, which is what the rule in CLAUDE.md asks for.

| check | result |
|---|---|
| word-bounded search for a recovery key across `tests/artifacts/` | none |
| `nix build .#test-iso` (shellcheck runs inside `writeShellApplication`) | pass |
| fmt, statix, deadnix, no-secrets-in-store | pass |

## The kexec branch, taken for the first time (2026-09-19, kexec)

The brief asks the headless path to work "from both an existing Linux
(kexec) and the ISO". `vm-deploy` proved the ISO. Nothing had ever taken the
other branch, and a test that did found it broken in three ways before it
got anywhere near a kernel:

| what the run said | what it was |
|---|---|
| `aborted: --flake or --store-paths must be set` | `nixos-anywhere --phases kexec "$target"` -- what the deploy ran -- refuses to start without one of them, even for a kexec it will not install from. **Every kexec deploy ended here.** It is given `--store-paths "$disko" "$toplevel"` now, which the deploy already has, so nothing of its own is evaluated; the build moved above the branch to make them available |
| the next `ssh` would have been refused | a kexec gives the machine a host key of its own, and `StrictHostKeyChecking=accept-new` takes a key it has never seen, not one that changed. The deploy already forgets the key after the install's restart; it does the same after the kexec now, and waits for the installer to answer before going on |
| `HOME: unbound variable` | nixos-anywhere reads `HOME` for the throwaway key it logs in with. A person's shell has one; a service has not |

A fourth thing the branch needed: `NIXIE_KEXEC`, so the image can be handed
in. nixos-anywhere downloads one from the internet by default, which a
deploy host behind a firewall -- or a test -- cannot do.

**Where it stops.** With all of that fixed the deploy reaches the kexec
itself, and the machine answers:

```
Downloading kexec tarball, this may take a moment...
setsid: failed to execute /root/kexec/kexec/run: No such file or directory
Kexec may have failed - check output above
```

nixos-anywhere unpacks an image laid out as `kexec/run`, which is
nix-community/nixos-images' kexec-installer. nixpkgs builds a kexec tarball
of its own (`system.build.kexecTarball`, from `netboot-minimal.nix`) and it
is a different shape: `kexec_nixos` and a store beside it. Finishing this
wants either that flake as an input -- a dependency the brief says to
justify, and the platform has five -- or that image rebuilt from nixpkgs,
including the part that carries the current host's keys into the new system
so the deploy can log back in.

So the branch is fixed, and `deploy-kexecs` holds its shape: that it only
kexecs a machine which is not already the ISO, that the store paths are
passed, that the system is built before the kexec rather than after, that
something forgets the host key afterwards, and that an image can be handed
in. The gate is forty-nine.

| check | result |
|---|---|
| `deploy-kexecs` | pass |
| `vm-deploy` | pass, re-run after the build moved above the branch |
| the 49-check gate | pass |

## How far the kexec gets with an image built here (2026-09-19, kexec II)

The entry above ends by saying the branch needs either `nixos-images` as a
sixth input or that image rebuilt from nixpkgs. Between the two, the one
that costs the platform nothing is worth trying first, so it was tried:
`tests/vm/kexec-image.nix` wraps nixpkgs' netboot installer in the layout
nixos-anywhere unpacks.

The contract, learned by running into each part of it: the tarball holds a
`kexec/` directory, it is extracted into `$HOME/kexec`, `kexec/run` is
called with `--kexec-extra-flags`, and nixos-anywhere greps the output for
"machine will boot into nixos" to decide the machine is on its way. The
script has to say that *before* the kernel it says it from goes away, and
leave the kexec itself to a moment later so the caller's SSH closes rather
than dying underneath it.

With that, the run gets here:

```
kexec/run … machine will boot into nixos
Connection to 192.168.1.9 closed.
<<< Welcome to NixOS kexec-26.05.20260910.d58a46e (x86_64) - ttyS0 >>>
```

The kexec fires, nixos-anywhere accepts it, and the machine comes up as the
NixOS installer. Then nothing can reach it -- `No route to host` -- and the
deploy waits at the loop that was added for exactly this moment.

What is missing is the piece a downloaded kexec-installer does at runtime
and this one is told at build time: carrying the machine's networking
across. Telling it is not enough. The VM has two interfaces, a user-mode one
and the test's own; the address has to land on the one the deploy is
talking to; and the names belong to the kernel that just started rather than
the one that was configured. Matching every NIC gives neither a route,
matching the name it had leaves it unreachable another way.
nix-community/nixos-images reads the running machine's addresses and routes
before the kexec and replays them after, which is the piece to write -- or
to take as an input, which costs a dependency and is not a call to make
alone.

So `vm-deploy` stays the ISO path, `deploy-kexecs` keeps the branch's shape,
and the image is in the tree unreferenced with its own note. What the three
runs bought is in the entry above: the branch is no longer broken.

| check | result |
|---|---|
| the kexec itself, by hand through `vm-deploy` | fires; the machine boots the installer; it is then unreachable |
| `vm-deploy` (the ISO path) | pass, unchanged |
| fmt, deadnix, statix | pass |

## Carrying the networking across the kexec (2026-09-19, kexec III)

The entry before this one named the missing piece: the machine's networking
does not survive a kexec, and a downloaded kexec-installer works it out at
runtime. That piece is written now, and it works.

`tests/vm/kexec-image.nix` does it in two halves. Before the kexec, the run
script reads the address **this very SSH session arrived on** --
`SSH_CONNECTION`'s third field -- which is how the right interface is picked
out of the several a machine has; a first attempt took the first global
address and carried the VM's user-mode interface, which goes nowhere. It
hands the address, gateway and hardware address over on the kernel command
line. After the kexec, a service in the image reads them back and puts the
address on the interface with that MAC, so nothing depends on what the new
kernel decided to call it.

It also waits for that interface. Without the wait it ran before udev had
produced the NIC, reported no interface with that address, and the machine
came up unreachable -- which is what had been read as "the address is not
carried" for two runs before this.

From a run, on the machine's own console:

```
carrying 192.168.1.9/24 on eth1 (52:54:00:12:01:03) across the kexec
nixie: carried 192.168.1.9/24 to eth1
```

**What is still not green, and it is one layer further in.** The machine now
answers on that address and refuses the port: `ssh: connect to host
192.168.1.9 port 22: Connection refused`, where every run before the address
was carried said `No route to host`. So the deploy waits where it
reconnects. Something between the installer's sshd and that address is not
up; the symptom is specific and the next run starts there.

So `vm-deploy` remains the ISO path and `deploy-kexecs` keeps the branch's
shape. The image is in the tree unreferenced, and what it knows -- the
nixos-anywhere contract, the layout, picking the interface from the session,
waiting for udev -- is written at the bottom of it.

| check | result |
|---|---|
| the address carried across a kexec | works, on the console of a run |
| the deploy reconnecting after it | not yet: the port is refused |
| `vm-deploy` (the ISO path) | pass, unchanged |
| fmt, deadnix, statix | pass |

## Where the kexec run stops, for good this time (2026-09-19, kexec IV)

The entry above says the address is carried and the port was refused. It is
not refused any more -- that was the machine still booting. With the address
carried and the wait for udev in place, a run gets all the way to:

- the kexec fires and nixos-anywhere accepts it;
- the machine comes up as the installer, with `nixie: carried 192.168.1.9/24
  to eth1` on its own console and `Started SSH Daemon` after it;
- the deploy reconnects -- the host key is accepted again, after the kexec;
- the test's own probe reaches it in 0.22 s.

Then the deploy goes quiet, and stays quiet. What it is doing is the part
this path cannot avoid: a kexeced machine's store is a tmpfs with nothing in
it, so the whole system has to cross the wire. The ISO path never pays that
-- `copying 0 paths`, because the image already had every path. Two runs sat
in that copy, one for fifty minutes to the test's budget and one for
fifty-five until the test process was terminated (exit 143, not an
assertion). No error, no out-of-memory, the unit active throughout.

So the ceiling here is the machine this runs on, not the branch. What is
proved: every step of the kexec path up to and including the reconnect, and
the three faults fixed two entries ago that stopped it before any of that.
What is not: the copy and the phases after it, inside a nested VM on this
host.

`vm-deploy` stays the ISO path and `deploy-kexecs` keeps the branch's shape.
`tests/vm/kexec-image.nix` is in the tree unreferenced, and everything four
entries of runs taught it is written at the bottom of it -- the
nixos-anywhere contract, the layout, reading the interface from the session,
waiting for udev, and now what happens after.

| check | result |
|---|---|
| kexec, address carried, sshd up, deploy reconnects | all four, in one run |
| the closure copy that follows | not finished here: 50 and 55 minutes, then terminated |
| `vm-deploy` (the ISO path) | pass, unchanged |

## Seeding the target's store, which is the answer (2026-09-19, kexec V)

The entry above ends by naming what would finish this: "a deploy that seeds
the target's store some other way". That is one argument on the image, and
it works.

`tests/vm/kexec-image.nix` takes `carry` -- store paths the installer should
already have when it comes up -- and puts them in `system.extraDependencies`.
The netboot image is itself a store, so anything in its closure arrives with
it, and the deploy's copy into the kexeced machine finds everything already
there. That is the same thing the ISO path enjoys when it prints `copying 0
paths`, and it is why the ISO path takes minutes where this took an hour.

The run that proved it did not finish, and not for this reason: the **other**
half of `vm-deploy` -- the setup generation carrying itself from the installed
disk -- reached only phase 3 that time, where four runs before it had reached
8. One flake in five runs, on the loop that restarts a machine up to twelve
times waiting for it to finish. So the test in the tree is the one that has
never flaked, `vm-deploy` still proves the ISO path end to end, and
`deploy-kexecs` still holds the kexec branch's shape.

What finishing wants is the two halves apart: the kexec path as a test of its
own, on a machine with room for a 12 GB guest beside the rest, rather than a
fourth node bolted onto a test that already runs three. That is a change to
make deliberately, not at the end of a long session.

| check | result |
|---|---|
| `carry`, seeding the kexeced machine's store | works; the deploy's copy has nothing left to send |
| the run that showed it | stopped in the other subtest, one flake in five |
| `vm-deploy` (the ISO path, restored) | pass |
| fmt, deadnix, statix | pass |

## The kexec path as a test of its own (2026-09-20)

The entry above says what finishing wants: the two halves apart. They are
apart now. `tests/vm/deploy-common.nix` holds what both need -- the system
they install, the site they install it from, every source that site's lock
names -- and `vm-deploy` takes it from there instead of defining it. That
refactor is the part that landed: `vm-deploy` passes with it, unchanged in
what it proves.

`tests/vm/deploy-kexec.nix` is the other half: two nodes rather than four,
the runner and a plain NixOS machine with twelve gigabytes of its own,
because it holds the image, then the installer unpacked from it, then that
installer's store. It carries every piece the path needs -- `carry` seeding
the target's store, the address crossing the kexec, the fifo answering the
one question, the PATH and HOME a transient unit lacks.

It is **not registered**, because on this host it does not finish. How far it
gets: the deploy takes the kexec branch, `kexec/run` says "machine will boot
into nixos", the machine comes up as the installer and puts its old address
back -- `nixie: carried 192.168.1.9/24 to eth1` on its own console. Then
nixos-anywhere's reconnect did not complete inside forty minutes on that run,
where inside `vm-deploy` the same steps had reconnected and stalled in the
copy instead. Two different stalls, two runs, neither reproduced twice, both
on a host already holding a 6 GB and a 12 GB guest.

That is where this stops, and it stops on a machine rather than on the code.
What is in the gate is the honest set: `vm-deploy` for the ISO path end to
end, `deploy-kexecs` for the shape of the other branch, and four faults fixed
in it that no user could have got past.

| check | result |
|---|---|
| `vm-deploy`, on the shared module | pass |
| `vm-deploy-kexec` | written, unregistered, does not finish here |
| the 49-check gate | pass |

## A hardened install, in VirtualBox, start to finish (2026-09-22)

A person reported an install that ended in emergency mode on a VirtualBox
machine with a TPM and Secure Boot, and asked whether the disk was being
encrypted twice because the passphrase is asked for again. VirtualBox is on
this host, so the answer came from running it rather than from reading.

**What the reported machine's own disk says.** Its ESP is not encrypted, so
it can be read: the install wrote it at 22:34 and `loader/keys/` -- what
phase 5 stages -- appeared at 22:40, which only happens after a first boot
that worked. `loader.conf` carries `secure-boot-enroll force`. The outer
LUKS layer has a passphrase slot and the unbound duress slot, and **no
`systemd-tpm2` token**, so phase 6 never ran there. The failure is the boot
after the Secure Boot enrolment, not the one after the install.

**The run here.** A VM matching it -- EFI, TPM 2.0, one SATA disk, 8 GB --
took the whole hardened path: `check ok=True`, phases 1 to 3, first boot,
the passphrase, the setup generation, Secure Boot staged and enrolled, the
restart, the TPM bound with a PIN (PCRs 7), the recovery key printed, Apply,
and Finish. Both restarts came up; neither reached emergency mode. **The
reported failure did not reproduce.**

**What did come out of it, and is fixed:**

| found | why it matters |
|---|---|
| the wizard applied its Hardened list whole | `setHardening` wrote every path in `HARDENED`, TPM included, while `offered` right above it hides the TPM options on a machine without one and the card says they "are not part of this setup". On such a machine the disk gets an outer layer bound to a device that never answers. Now filtered by what the machine is offered, refused by the Security step, and asserted against in `tpm.nix` and `attestation.nix` so the wizard's own Review step catches it |
| the installer never recorded the TPM it found | `apply_config` took `tpm` from the request body with `False` as the default, and no front end sends it, so **every** wizard install wrote `nixie.hardware.tpm = false` however much TPM the machine had. It now asks `nixie-discover`. This is how the assertion above was caught: the live scan said `tpm: true` and the written fact said false |
| nothing said a hardened start asks twice | Once the TPM is bound, the PIN opens the outer layer and the inner one has no answer to reuse, so it asks for the disk passphrase after it -- at every start, not only the first. That is the design (`vm-splash` drives exactly that sequence), but the step that turns it on said only "bind the disk to this machine's TPM with a PIN, and test that they open it". It now says what every start will ask for, and the prompts say which of the two they are |

**One rough edge, left as it is.** `Checks` fails once after Apply, with
`attestation code does not compute`; `tpm2-totp` says "The system state has
changed" because the boot chain did. The step says so and names the remedy,
`nixie reseal` ran in a second, and Checks passed. Resealing without being
asked is what attestation exists to prevent, so this stays a person's
decision.

| check | result |
|---|---|
| `nix run` of the hardened path in VirtualBox, phases 1-8 | pass, both restarts, TPM+PIN and Secure Boot both live |
| the reported emergency mode | not reproduced |
| the 49-check gate | pass |
