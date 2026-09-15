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

## Final run

Every check ran on 2026-09-11 on the rootless host described in
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
