# Changelog

## 0.1.0 (unreleased)

The installer's wizard is rebuilt: fewer steps with plain labels (Machine,
Disks, Name, Security, Network, Services, Desktop, Review, Install), the first
sentence of each option's help with More for the rest, advanced settings
behind More options, a progress bar and transitions that respect reduced
motion, and no finish swatches. Review summarises every step and opens each
site file (`site.nix`, the host's new `configuration.nix`, `hardware.nix`,
`guests.nix`, `data.nix`, `flake.nix`) in a CodeMirror editor with Nix
highlighting, completion and hover help for every `nixie.*` option, and a
searchable list of all options; the host is evaluated before Install, with
errors marked on their lines, type errors included. Going back and on to
Review no longer writes the host into `site.nix` twice or keeps a stale
`hardware.nix`. The terminal installer offers the same editing and check.
Setup after the first boot is a checklist that runs by itself: unused steps
are skipped unseen, phase 6 proves the TPM and PIN open the disk before the
passphrase slot goes (so there is no verification reboot), and it stops only
for the Secure Boot restart, a restart into the firmware settings, and the
passphrase and PIN. The Services step shows backups, monitoring, the host
page and the console, which had option metadata but no step. HyDE is
offered on the Desktop step when the machine is online: the site gets a
pinned hydenix input, `mkSite { …; inherit inputs; }` passes a site's inputs
to its hosts, and `modules/desktop/hyde.nix` wires hydenix to the platform
(HyDE's unfree app modules stay off; the Apps still install under HyDE).
The Machine step asks Standard or Hardened; the hardened setup turns on every
security feature the installer can set by itself and walks through each one
with its secrets, in the web wizard and the terminal one. Phases report their
steps, and the install and setup checklists draw a progress bar from them. The
boot splash centres the mark and shows an indeterminate bar instead of a still
logo, and hides it while asking for the passphrase. `nixie apply` no longer
fails when two guests build the same image (the second only gains an alias).
HyDE installs and runs: its desktop, and the graphics drivers under it, come
from hydenix's own nixpkgs, because HyDE's configuration is written for the
Hyprland it pins — on the platform's newer one the session drew over a thousand
config errors, and mixing the two glibcs left the compositor unable to start at
all. The wizard takes an existing machine's age key when a cloned site already
holds its secrets.

Secure Boot setup no longer leads to "Access Denied". Setup told people to
keep Secure Boot enabled while clearing its keys, and a firmware still holding
its vendor's keys then refuses the signed boot loader and the installer alike.
Phase 5 now says to set Secure Boot Mode to Custom, reset the keys and leave
Secure Boot off, and it knows a third state: this machine's own key found in
the firmware's PK variable with the switch still off, when it says to turn
Secure Boot on. Before, that state was taken for vendor keys and the person
was sent to clear the keys again.

During setup, USBGuard lets mice, touchpads and touchscreens through as well
as keyboards, so the setup page can be used with a pointer plugged in late.

QR codes on the setup pages are images and scan: the attestation code was
tpm2-totp's ANSI-coloured terminal picture, which a browser prints as escape
codes. The time zone is a dropdown whatever it is set to, the TPM measurements
are a checkbox per register, and the "hardened" chips sit beside their labels
instead of stretching under them (a bare `.brand` rule for the header's logo
was also styling every brand-coloured chip).

The host page wears the control panel's finish instead of PatternFly's own: its
branding set PatternFly 5 variables while cockpit 366 ships PatternFly 6, so
none of it applied. Both of PatternFly 6's token layers now come from the
design tokens, with the panel's cards, controls and pill navigation, the
panel's fonts served beside the stylesheet, and the login page and the pages
behind Logs, Services, Terminal, hardware and the firewall included.

A HyDE desktop builds again: crates.io refuses any user agent that begins
with "curl/", which is what `fetchurl` sends, and HyDE's `hyde-ipc` comes
from a flake whose nixpkgs still asks `crates.io/api/v1` for its crates, so
the whole home-manager generation failed on a 403. That one program is built
from the same source with the platform's toolchain, which fetches crates from
static.crates.io.

One site, several machines: a change applied on one of them reaches the
others. `nixie.updates.mode` says what a machine does when the site
repository is ahead of it -- "notify" (the default) says so on the front
panel, the host page, a desktop notification and at login and waits for
`nixie update --now`; "auto" applies it and confirms only when `nixie doctor`
comes out no worse than it did before the apply, so a machine that breaks
itself unattended goes back on its own without one already unhappy about
something else reverting every update;
"off" does not look. Applying is the ordinary `nixie apply`, so the host and
the guests the site declares move together. Everything a machine wants to
say -- an update waiting, an apply to confirm, an attestation to reseal, a
failed backup check, a service that failed, a blocked USB device -- is
collected by `nixie notices`
into one file that each of those surfaces reads, and the front panel gained
`u` for applying what is waiting. The control panel shows them under its
navigation, read from the daemon's own configuration, so they take the
client certificate the rest of the panel does rather than being served
beside the bundle to anyone who opens the page.

`nixie secure-boot` answers what "Access Denied" means on a machine: whether
the firmware holds this machine's keys, whether they are staged on the boot
partition, and whether every boot file is signed with them, with the step to
take in each case; `--sign` signs what is not. A machine that will not start
at all is read from the installer image instead: `nixie disk open` now brings
that disk's boot partition up with its pools, and `nixie secure-boot --at`
reports on the system there while reading the firmware of the machine it is
running on.

Six things the brief asks for that the platform had not done. `nix run
.#apply` exists: ARCHITECTURE.md and the guide to adding a guest both told
people to run it from a site checkout, and `mkSite` emitted no such package,
so it failed. It copies the checkout to a machine of the site and runs that
machine's own `nixie apply` there, leaving the site's `.git` alone because
the host's checkout has commits of its own.

`nixie doctor` reports who the daemon trusts and warns a fortnight before a
certificate expires, which the brief asks of it and which looks, when it
happens, exactly like a control panel that will not load. Phase 8 of setup
starts the cache fetch the site's data manifest lists, without waiting for
it. `nixie.monitoring.exporters.<name>.enable` turns either of the two the
platform runs off, or any other of nixpkgs' exporters on, and what is
scraped follows what runs. The host page's History screen wears the site's
finish instead of always graphite. A headless deploy writes the host's real
profile into the setup state instead of always "server", which had a desktop
installed that way continuing as a server.

There is CI. `.github/workflows/checks.yml` runs every check that does not
need KVM on a hosted runner, and photographs every screen of the control
panel in all three finishes from demo mode -- which is what the brief asks
to be generated there, and what demo mode makes possible without a daemon or
a VM. The VM tests are a job of their own that only a runner labelled `kvm`
takes, asked for by hand: a hosted runner cannot run them, and a workflow
that is red for everyone by design is worth nothing.

`nix run .#test-iso --kiosk` drives the wizard through the browser on the
machine's own screen, not over the HTTP API: a whole install, in the kiosk
the image starts, which the brief asks for and which nothing did before.
Only a test image opens that browser to a debugger -- `packages.nixie-iso-
kiosk` -- and nothing the platform installs sets
`nixie.kiosk.remoteDebugPort`.

A machine that gives up in the initrd now says why. The prompt it drops to
cannot be used -- the root account is locked, and a signed boot chain has no
editable kernel command line -- so a screen that said only "emergency mode"
left nothing to act on or to report. It prints which units failed, that the
disk is still locked and nothing has been changed, and that holding Space
offers the previous system, to the screen and to the kernel log at error
level so a quiet console still shows it. It runs before the panic that
`boot.panic_on_fail` triggers on that same target.

The attestation code can no longer hold up the passphrase prompt. Its initrd
service runs in front of every prompt so the code is shown first, and it
waited on the TPM's device unit to do so: on a machine where that device
never appears the prompt waited out the device timeout with it, ninety
seconds of a machine that looks hung. It waits five seconds for the device
itself now and says there is no code if it never comes.

`nix run .#test-iso` takes `--disk virtio|sata` as well as `--tpm tis|crb`: machines and hypervisors differ
in which interface their TPM speaks, and each is a different kernel module.

`nix run .#test-iso --security hardened` now writes what the wizard's
Hardened button writes, Secure Boot included. Leaving it out meant the
configuration a person actually installs was the one combination never
booted here, while each half of it was.

The container images a site lists are served from the machine that fetched
them, which is what the brief's `oci` kind meant by "into the local registry
mirror": `nixie.data.registry` runs a registry on the host, storing under
`cache/` like the layouts beside it, and the host's firewall lets the guests
reach that one port and no other. A guest pulls from the machine it runs on,
and a machine with no way out still starts its containers. Writing it found
that the `oci` fetcher could never have worked on a Nixie host at all:
skopeo copies nothing without a trust policy, and a Nixie host is not a
container host, so it has no `/etc/containers`. The fetcher carries its own
policy now; the manifest pins every image by digest, which is the integrity
check.

An option a site declares reaches the installer, which is what the extension
point in docs/extending.md promised and could not do: the wizard's list was
rendered once when the installer was built, from the platform's modules
alone, and a site's own option was never in it. The backend asks the site
for its options once the site exists and names a host, and again whenever
the site changes, so a module added at Review shows up without a restart.
`inputs.nixie.lib.mkOption` is how a site declares one -- nixpkgs' own
refuses an argument it does not know, which is why the wizard metadata could
not be attached before.

`nix run .#offline` stands behind the promise that nothing fetches behind
the lock file: it archives every pinned input into a store of its own and
then evaluates every output with the network refused, where an unpinned
fetch in a module is an error rather than a download.

Two faults the gallery found the moment it photographed the host page's own
screen, which it had never pictured before. `nixie rollback --json` on a
machine with no generations recorded passed an unmatched glob through as a
path, and stat, date and jq each failed on it in turn, so the page showed a
line of shell errors where its history belongs. And the page wore Cockpit's
styling rather than the site's finish: Cockpit brings its own stylesheet in
after the page's, so every rule that named nothing of the page's own lost to
it.

The host page can run the three things it is for: Apply the site, Fetch the
cache and Run the checks, each printing as it goes rather than at the end.
They are the same commands the machine runs for itself, spawned through
Cockpit's bridge, so nothing new listens on the host. And
`nixie.desktop.look.animations = "none"` now turns GTK's own animations off
as well as the compositor's, so applications are as still as the windows
around them.

A headless install finishes. `nix run .#deploy` installed the machine,
rebooted it and printed a line to carry on by hand -- a line that could not
have worked, since everything after the first `;` ran on the operator's own
machine and the reconnection would have been refused as a changed host key
(the installer's and the installed system's differ). It now forgets that
key, waits for the machine, and hands over to the setup generation's own
terminal front end in the operator's terminal, which knows phases 4 to 8,
Finish and the secrets each asks for.

The code the platform installs now lives in files of its own -- shell, Lua,
CSS, HTML, JavaScript and the tests' Python -- next to the module that
installs it, instead of inside Nix strings: `lib/template.nix` puts the
values Nix knows in place of `@name@` marks, and a mark with nothing given
for it stops the evaluation. The Nix files are what is left: the CLI's is 47
lines instead of 629, the host page's 204 instead of 423, and every test is
its definition plus a `.py` beside it. Nothing a machine installs changed:
each generated script, configuration file and test script was compared with
the one before, and they match.

Hardened machines start on the splash like the rest. The duress check was a
replacement for systemd's console password agent, which does not run under
Plymouth, so the splash was off with duress or attestation; and that agent's
unit waits for a readiness signal the check never sent, so after the
passphrase the boot sat still until systemd gave up on it. One agent now
answers every prompt on every encrypted host: on the splash, on the console,
and over remote-unlock SSH, with Plymouth's own agent masked. The attestation
code is on the splash, refreshed every 30 seconds, and the Nixie theme says
when a PIN or passphrase was wrong and while the disk is opening. The boot is
quiet from the loader on. The duress passphrase works at the PIN prompt too:
it is now an unbound key slot on every layer a person types at, which only
verifies it and opens nothing, where before it was a real key to the inner
layer. After an update the attestation secret is sealed to the new system
once that is unlocked, when Secure Boot verified it; the sealed system is
recorded by store path, since the setup generation and the one after Finish
share a label but not a boot chain, which showed a failed code on the first
real start. `nixie.host.splashTheme` picks any Plymouth theme, from Plymouth,
a package or any repository.

Security keys: `nixie.security.fido2.enable` opens the disk with a FIDO2 key,
its PIN and a touch, enrolled by setup (the continuation page asks for the
key's PIN) or later with `nixie security add-key`, with the passphrase still
working without the key. `nixie.auth.ssh.keyAndPassword` asks for the
password after the SSH key, and the hardened setup turns it on; security
keys (`sk-` key types) already worked as SSH keys and the option says so. A
private key pasted where the public one belongs is refused with the reason.
`nixie disk open` opens another Nixie disk, on the installer image or
another machine, with a security key, the recovery key or the passphrase, and mounts its pools read-only under temporary names; `nixie
disk close` locks it again. Secret names sent to the setup backend are now
checked before they become file names.

Fields the machine can answer are lists, not blank lines: the time zone comes
from the machine's own tzdata, and a backup folder — or where the disk's
header backup is written at the end of setup — is picked from the drives it
can see, which are mounted when picked. The control panel gains a Machines
page: every machine in `site.nix`, with a link to each one's own panel, so a
site with more than one deployment is managed from any of them.

The control panel matches: softer radii, pill navigation, a heading row with
actions on every page, pages, panels, dialogs and toasts that animate in (off
under reduced motion), a centred card for the trust page and for the kiosk's
lock page, drawn in the host's finish. The panel no longer draws pages before
it knows which backend answers.

Installer image fixes: the file is `nixie_<version>_<platform>.iso` with Nixie
branding in the boot menu; the menu has graphical, web and terminal entries;
the image boots in BIOS mode (VirtualBox's default) and explains that UEFI is
needed; the kiosk shows the wizard alone, with text (fontconfig was off on the
minimal CD and the stylesheet pointed at missing font paths, which also
affected the control panel); installs from the ISO evaluate the site flake
(`nix-command` was not enabled there) and see the files phases 1 and 2 write;
a getty no longer takes tty2 from the terminal wizard; the terminal wizard
writes the site with the web wizard's code and keeps a failed phase's output
on screen. The kiosk pairs itself instead of showing the pairing form, runs on
GPUs without OpenGL (VirtualBox) and falls back to the address banner; GRUB
no longer stops at "Press any key"; the installer has compressed swap, since
evaluating a site on a 4 GB machine ran out of memory; a site started on the
installer names the platform by its store path, which every host keeps; phase
8 and Finish no longer kill themselves by switching generations from inside
the setup service; `nixie.hostUi.extraOrigins` uses Cockpit's mergeable
`allowed-origins` (setting `Origins` directly failed to evaluate). The first
boot after installing goes to the installed system even with the image still
attached (`BootNext`; VirtualBox puts the optical drive first); Alt+F2 works
under the kiosk; the hardware scan no longer offers zram or the installer's
own medium. Beyond the installer: servers ship the `nixie` CLI, `nixie apply`
evaluates a site flake (it failed on a boolean), the LAN reaches the host's
SSH and control panel in the default bridge mode, the host page's TOTP second
factor is actually required, and the front panel no longer shows a healthy
USB line as a problem.

Every host has the `nixie` command; desktops get it without the Incus client
and OpenTofu unless they enable Incus. A Secure Boot install from the image
continues into the setup generation (the default entry is set in loader.conf;
the firmware call never worked from the image). The image carries the
platform's flake inputs. Desktops are not asked for bridge ports or server
network settings, and do not report uplink drift. `test-iso` gained `--usb`
and `--security tpm|secureboot`. An encrypted boot no longer drops to
emergency mode when the passphrase comes after a minute; the installed server
keeps the installer's DHCP address (the bridge takes the uplink's MAC); the
first boot after a reinstall goes to the new install, not a stale firmware
entry.

Choices in the web wizard no longer stop an install at phase 3 with a Nix
evaluation error: remote unlock (the early-boot root shell was defined twice
at one priority), a desktop package with an unfree licence such as Steam (a
package named in the site now accepts its licence), and a TPM measurement
list (the wizard sent the numbers as text). The wizard asks for an SSH key
when remote unlock is on and holds Next on combinations the modules refuse
(TPM, attestation, duress or remote unlock without encryption; exit-node
egress without managed-nat, Tailscale or a node name); it no longer shows the
monitor list, which it cannot fill. Kernel lockdown left the wizard (it
rebuilds the kernel during the install and stops module loading) and
evaluates again when a site sets it. Text the wizard writes into `site.nix`
is escaped for Nix (`${`, non-ASCII). `eval-matrix` gained a server and a
desktop with every wizard option on.

A server installed from the image through the web wizard, then used for real,
found more. Remote unlock never answered: the initrd had no network driver,
since the hardware scan copied only storage drivers (phase 1 now adds the
wired ports' drivers; a host installed earlier needs them added to its
`hardware.nix`), and an SSH session without a terminal cancelled the boot's
passphrase prompt into emergency mode (the relay now refuses such a session).
A failed Finish said nothing on the page; it now shows the unit's output.
Finish, or any `nixie apply`, stopped when only a user's own units missed
their reload during the switch. The front panel asked a socket path that
does not exist and always showed "no instances". The control panel's
terminal opened a new exec session on every refresh, about 90 a second
with 370 requests a second behind them; its memory figures read metric names
incusd does not export (the guest Grafana dashboard too); its History page
fetched a file nothing serves and crashed the whole panel (it now shows
guest snapshots and points to the host page); an instance's address could be
a bridge inside the guest. Scratch instances had no network device at all,
and with one their ports were outside the catch-all chain that keeps guests
away from the host's SSH and pages (`veth-*` against Incus's `veth<hex>`).
Foreign images named their interface `uplink`, which their own network
setup does not configure. The "not trusted yet" page told the administrator
to run `openssl`, which servers did not have. `nixie rollback --list` and
History dated every generation 1970. The wizard offered TPM features on
machines without one, showed the Tailscale key file path and hid list
defaults, and a new site's files kept the store's read-only modes.

After the install, the machine goes straight to setup: the loader menu is
hidden (hold Space for it), boot shows a Nixie splash that asks for the
passphrase in the installer's look (the text console stays with duress or
attestation), and setup continues in the front end chosen at the image's
boot menu, the wizard on screen, the address for a browser, or the terminal
wizard, on desktops too, where it used to start the desktop session with no
way back to setup. The plain entry says setup is unfinished. The wizard no
longer offers HyDE, which left a desktop with no session at all, and a site
that turns it on without HyDE is refused with the reason; the Profile step
shows the choice clearly and Review and setup name the profile. `nixie
apply` commits hand edits in the site checkout and pushes to
`nixie.site.repo`, whose key `nixie site key` prints.

The login screen draws in the chosen finish: its box was GTK's light frame
with the finish's light text, the stylesheet naming widgets regreet no longer
has. The greeter and the boot splash take the colours of
`nixie.desktop.finish`, which now also accepts a site's own finish or an
imported HyDE theme.

An administrator named root (or nobody) stopped the install with
"users.users.root.shell is defined multiple times": the platform makes the
administrator a normal user, which on root collides with NixOS's own
definition. Both wizards refuse those names, the web wizard checks every
pattern-restricted field before phase 3, and the module says why.

The control panel has a Settings button: the finish, header figures, the
starting time range, the Overview panels' order, width and visibility, the
navigation and extra links, kept on the host for every browser.

First build of the platform against nixpkgs 26.05: option tree, `mkSite`,
security stack, network and egress policy, Incus with declared guests, data
manifest and backups, monitoring, control panel, installer (kiosk, LAN,
headless), desktop profile, host page, console front panel and kiosk.
See `VERIFICATION.md` for what has been proven in VMs.
