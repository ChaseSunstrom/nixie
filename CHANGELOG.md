# Changelog

## 0.1.0 (unreleased)

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

The control panel has a Settings button: the finish, header figures, the
starting time range, the Overview panels' order, width and visibility, the
navigation and extra links, kept on the host for every browser.

First build of the platform against nixpkgs 26.05: option tree, `mkSite`,
security stack, network and egress policy, Incus with declared guests, data
manifest and backups, monitoring, control panel, installer (kiosk, LAN,
headless), desktop profile, host page, console front panel and kiosk.
See `VERIFICATION.md` for what has been proven in VMs.
