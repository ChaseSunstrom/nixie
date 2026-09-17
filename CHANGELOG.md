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
