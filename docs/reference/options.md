# Option reference

Generated from the module tree; the installer renders the same descriptions.

## `nixie.auth.admin.name`

*string matching the pattern ^[a-z_][a-z0-9_-]{0,31}$*, required. Wizard section: auth.

The one administrator account created at install. It can use sudo, log
in over SSH and open the web pages.

## `nixie.auth.admin.passwordFile`

*absolute path*, required. Wizard section: auth.

A file holding the password hash for the administrator. The installer
writes it into the site's secrets; it never ends up in the Nix store.

## `nixie.auth.secondFactor`

*one of "none", "totp" (none, totp)*, default: `"none"`. Wizard section: auth.

An extra step for logging in to the host page. "totp" asks for a
six-digit code from an authenticator app, enrolled during setup.
Passkeys are not offered because the host page checks logins on the
server itself, where a browser passkey cannot reach.

## `nixie.auth.ssh.passwordLogin`

*boolean*, default: `false`. Wizard section: auth.

Allow SSH login with the password instead of a key. Anyone who can
reach port 22 can then try to guess the password; leave this off
unless you have no way to use a key.

## `nixie.auth.sshKeys`

*list of (optionally newline-terminated) single-line string*, default: `[]`. Wizard section: auth.

SSH public keys allowed to log in as the administrator. Any key type
works. A hardware-backed key is a good choice but is not required.
With no keys and password login off, SSH cannot be used, which is fine
for a desktop.

## `nixie.auth.totpSecretFile`

*null or absolute path*, default: `null`.

Internal: the enrolled authenticator secret when the second factor is "totp".

## `nixie.backups.check`

*null or string*, default: `"weekly"`.

How often to run `restic check` over the repository; `nixie doctor` and `nixie backup verify` show the last result. Null turns it off.

## `nixie.backups.enable`

*boolean*, default: `false`. Wizard section: services.

Back up the state directory and every guest's backup paths with restic
on a schedule. Costs storage at the repository and some disk activity.

## `nixie.backups.environmentFile`

*null or absolute path*, default: `null`.

File with credentials for the repository's storage, if it needs any.

## `nixie.backups.excludes`

*list of string*, default: `[]`.

Patterns left out of backups.

## `nixie.backups.keep.daily`

*signed integer*, default: `7`.

Daily snapshots to keep.

## `nixie.backups.keep.monthly`

*signed integer*, default: `6`.

Monthly snapshots to keep.

## `nixie.backups.keep.weekly`

*signed integer*, default: `4`.

Weekly snapshots to keep.

## `nixie.backups.passwordFile`

*null or absolute path*, default: `null`.

File holding the repository password.

## `nixie.backups.rcloneConfigFile`

*null or absolute path*, default: `null`.

An rclone configuration file for "rclone:" repositories (S3, B2 and friends).

## `nixie.backups.repository`

*string*, default: `""`. Wizard section: services.

Where backups go, as a restic repository URL.

## `nixie.backups.schedule`

*string*, default: `"daily"`. Wizard section: services.

How often to back up.

## `nixie.backups.snapshots.daily`

*signed integer*, default: `7`.

Daily ZFS snapshots of state/ to keep.

## `nixie.backups.snapshots.hourly`

*signed integer*, default: `24`.

Hourly ZFS snapshots of state/ to keep on the disk itself. They are not a backup against losing the disk.

## `nixie.backups.snapshots.weekly`

*signed integer*, default: `4`.

Weekly ZFS snapshots of state/ to keep.

## `nixie.console.frontPanel.enable`

*boolean*, default: `true`. Wizard section: services.

A status screen on the first text console instead of a bare login:
host name, addresses, the control panel address as a QR code, each
guest as a lane with its state, GPU temperature, pool usage, and
anything `nixie doctor` would flag, drawn in the chosen finish. Any
key opens the normal login. The other consoles stay ordinary logins.

## `nixie.console.kiosk.enable`

*boolean*, default: `false`. Wizard section: services.

Keep the setup kiosk permanently and point it at the control panel,
so the local display shows the full web page behind a lock page that
checks the administrator password and second factor. Costs a
compositor and a browser in the server closure.

## `nixie.console.kiosk.idleLock`

*string*, default: `"10m"`.

Re-lock the kiosk after this much inactivity.

## `nixie.data.fetch.timer`

*null or string*, default: `null`.

Also run `nixie fetch` on this schedule.

## `nixie.data.kinds`

*attribute set of absolute path*, default: `{}`.

Extra fetcher kinds provided by the site, name to file.

## `nixie.data.manifest`

*attribute set of attribute set of attribute set of anything*, default: `{}`.

What lives in cache/, by fetcher kind and name. See the data guide.

## `nixie.data.mediaBackup`

*boolean*, default: `false`.

Include media/ in backups. It can be large.

## `nixie.data.root`

*absolute path*, default: `"/data"`.

Where state/, cache/ and media/ live. state/ is irreplaceable and is
backed up. cache/ is never backed up because `nixie fetch` can rebuild
it from the manifest. They never share a directory.

## `nixie.desktop.accentFromWallpaper`

*boolean*, default: `false`.

Pick the accent colour from the wallpaper instead of the finish.

## `nixie.desktop.audioVisualiser.enable`

*boolean*, default: `false`.

Draw a spectrum of whatever is playing in the control centre. Costs a small background process.

## `nixie.desktop.autostart`

*list of string*, default: `[]`.

Commands run when the session starts.

## `nixie.desktop.clock.format`

*string*, default: `"ddd d MMM  HH:mm"`.

The bar clock, in Qt date format.

## `nixie.desktop.defaultApps.browser`

*null or string*, default: `null`.

Desktop entry name of the default browser.

## `nixie.desktop.defaultApps.editor`

*null or string*, default: `null`.

Desktop entry name of the default editor.

## `nixie.desktop.defaultApps.fileManager`

*null or string*, default: `null`.

Desktop entry name of the default fileManager.

## `nixie.desktop.defaultApps.terminal`

*null or string*, default: `null`.

Desktop entry name of the default terminal.

## `nixie.desktop.enable`

*boolean*, default: `false`.

Internal: the desktop profile is active.

## `nixie.desktop.favourites`

*list of string*, default: `[]`.

Desktop entry ids pinned at the top of the launcher.

## `nixie.desktop.finish`

*one of "graphite", "umber", "paper" (graphite, umber, paper)*, default: `"nixie.ui.theme"`. Wizard section: desktop.

The finish for the whole desktop: bar, windows, terminal, editor and
apps. This is the default; the control centre can switch it for a
person without a rebuild.

## `nixie.desktop.flatpak.enable`

*boolean*, default: `false`. Wizard section: desktop.

Also allow Flatpak apps. Off by default because they are not declared in the site.

## `nixie.desktop.fonts.mono`

*string*, default: `"JetBrains Mono"`.

The monospace font (terminal, readouts).

## `nixie.desktop.fonts.ui`

*string*, default: `"Archivo"`.

The interface font.

## `nixie.desktop.hyde.enable`

*boolean*, default: `false`. Wizard section: desktop.

Hand the desktop to HyDE itself instead of the Nixie one. Nixie stops
configuring the session, the shell, Hyprland and the theme, and your
site brings HyDE in (the hydenix flake is the packaged form). The
rest of the platform is unchanged: the same installer, the same
security options, the same `nixie` command. Off by default because
HyDE is a large third-party desktop whose theme tool downloads themes
at the moment you switch them, which the Nixie desktop never does.

## `nixie.desktop.hyde.themes`

*attribute set of absolute path*, default: `{}`.

HyDE themes to offer alongside the built-in finishes, as a name and
the theme's own directory. Its colours and wallpapers are read as
data at build time, so nothing is downloaded or run on the machine.
Pin the theme repository as a flake input and point at a directory
inside it.

## `nixie.desktop.idle.lockAfter`

*signed integer*, default: `300`.

Seconds of inactivity before the screen locks.

## `nixie.desktop.idle.screenOffAfter`

*signed integer*, default: `600`.

Seconds of inactivity before the screen turns off.

## `nixie.desktop.idle.suspendAfter`

*null or signed integer*, default: `null`.

Seconds of inactivity before suspend. Empty means never.

## `nixie.desktop.keybinds`

*attribute set of string*, default: `{}`.

Extra key bindings: a key combination to a command, added to the platform set.

## `nixie.desktop.keyboard.layout`

*string*, default: `"us"`. Wizard section: desktop.

Keyboard layout.

## `nixie.desktop.keyboard.variant`

*string*, default: `""`. Wizard section: desktop.

Keyboard layout variant, if any.

## `nixie.desktop.look.animations`

*one of "full", "reduced", "none" (full, reduced, none)*, default: `"full"`.

Window and workspace motion: the full set, faster and fewer, or none.

## `nixie.desktop.look.barPosition`

*one of "top", "bottom" (top, bottom)*, default: `"top"`.

Where the bar sits.

## `nixie.desktop.look.blur`

*boolean*, default: `true`.

Blur behind translucent windows and the shell.

## `nixie.desktop.look.borderSize`

*signed integer*, default: `2`.

Window border width, in pixels.

## `nixie.desktop.look.cursor.size`

*signed integer*, default: `24`.

Cursor size in pixels.

## `nixie.desktop.look.cursor.theme`

*string*, default: `"Bibata, light on paper"`.

Cursor theme.

## `nixie.desktop.look.gaps.inner`

*signed integer*, default: `6`.

Space between windows, in pixels.

## `nixie.desktop.look.gaps.outer`

*signed integer*, default: `14`.

Space between windows and the screen edge, in pixels.

## `nixie.desktop.look.iconTheme`

*string*, default: `"Papirus, dark on the dark finishes"`.

Icon theme for apps and the shell.

## `nixie.desktop.look.rounding`

*signed integer*, default: `12`.

Corner radius of windows, in pixels.

## `nixie.desktop.look.systemReadouts`

*boolean*, default: `true`.

Show processor, memory and temperature readouts in the bar.

## `nixie.desktop.look.terminalOpacity`

*floating point number*, default: `0.92`.

Background opacity of the terminal, 0 to 1.

## `nixie.desktop.monitors`

*list of (submodule)*, default: `[]`. Wizard section: desktop.

Per-monitor settings. Empty means every monitor at its preferred mode.

## `nixie.desktop.nightLight.enable`

*boolean*, default: `true`.

Warm the screen colours in the evening.

## `nixie.desktop.overview.enable`

*boolean*, default: `true`.

Every open window, and the workspace it is on, in one panel on Super+` as well as Super+Tab.

## `nixie.desktop.packages.categories.browsers`

*list of string*, default: `[]`. Wizard section: desktop.

Package names in the browsers category, chosen in the installer.

## `nixie.desktop.packages.categories.communication`

*list of string*, default: `[]`. Wizard section: desktop.

Package names in the communication category, chosen in the installer.

## `nixie.desktop.packages.categories.creative`

*list of string*, default: `[]`. Wizard section: desktop.

Package names in the creative category, chosen in the installer.

## `nixie.desktop.packages.categories.editors`

*list of string*, default: `[]`. Wizard section: desktop.

Package names in the editors category, chosen in the installer.

## `nixie.desktop.packages.categories.gaming`

*list of string*, default: `[]`. Wizard section: desktop.

Package names in the gaming category, chosen in the installer.

## `nixie.desktop.packages.categories.media`

*list of string*, default: `[]`. Wizard section: desktop.

Package names in the media category, chosen in the installer.

## `nixie.desktop.packages.categories.office`

*list of string*, default: `[]`. Wizard section: desktop.

Package names in the office category, chosen in the installer.

## `nixie.desktop.packages.categories.terminals`

*list of string*, default: `[]`. Wizard section: desktop.

Package names in the terminals category, chosen in the installer.

## `nixie.desktop.packages.extra`

*list of package*, default: `[]`.

Any other packages.

## `nixie.desktop.power.backend`

*one of "power-profiles-daemon", "tlp" (power-profiles-daemon, tlp)*, default: `"power-profiles-daemon"`.

Which power manager to use on a laptop.

## `nixie.desktop.power.lid`

*one of "suspend", "lock", "ignore" (suspend, lock, ignore)*, default: `"suspend"`.

What closing the lid does.

## `nixie.desktop.terminal.greeting`

*boolean*, default: `true`.

Show system facts (fastfetch) when a terminal opens.

## `nixie.desktop.themes`

*attribute set of (submodule)*, default: `{}`.

Themes of your own, on top of Graphite, Umber and Paper. Each one
appears in the control centre and in `nixie-shell finish <name>`,
and colours the whole desktop the same way the built-in finishes do.

## `nixie.desktop.user`

*string*, default: `"the administrator"`.

The account that gets the desktop session.

## `nixie.desktop.wallpaper`

*null or absolute path*, default: `null`. Wizard section: desktop.

An image for the desktop background. Empty means the generated set for the finish.

## `nixie.desktop.wallpaperCycle`

*null or signed integer*, default: `null`.

Minutes between automatic wallpaper changes. Empty means never.

## `nixie.desktop.wallpapers`

*null or absolute path*, default: `null`.

A folder of your own images for the wallpaper picker, on top of the generated ones.

## `nixie.desktop.workspaces.labels`

*list of string*, default: `[]`.

Names shown for workspaces 1, 2, 3… in the bar. Empty means numbers.

## `nixie.disks.data`

*null or string*, default: `null`. Wizard section: hardware.

An optional second disk holding the data root as its own storage pool.
Without it the data root lives on the system disk.

## `nixie.disks.layout`

*one of "single", "system+data" (single, system+data)*, default: `"\"system+data\" when a data disk is set"`.

Whether the data root shares the system disk or has its own.

## `nixie.disks.system`

*string*, required. Wizard section: hardware.

The disk the operating system is installed on. It is wiped at install. Written by the installer as a stable by-id path.

## `nixie.guests`

*attribute set of (submodule)*, default: `{}`.

The declared guests. Anything else running on the host is a scratch instance.

## `nixie.hardware.gpu`

*one of "none", "nvidia", "amd", "intel" (none, nvidia, amd, intel)*, default: `"none"`.

The kind of graphics card the installer found. Drives which driver is
installed and, on a server, whether guests may be given the GPU.

## `nixie.hardware.tpm`

*boolean*, default: `false`.

Whether the installer found a TPM 2.0 chip. TPM binding and attestation
need one.

## `nixie.host.keepGenerations`

*positive integer, meaning >0*, default: `10`.

How many earlier versions of this machine's system stay bootable. Each
`nixie apply` adds one; the boot menu, `nixie rollback --list` and the
History page show them with the site commit, date and kernel. Older
ones go with the weekly clean-up, and with Secure Boot on only these
stay signed.

## `nixie.host.name`

*string matching the pattern ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$*, required. Wizard section: network.

The machine's name on the network and in the site repo. Lowercase letters, digits and dashes.

## `nixie.host.siteRevision`

*null or string*, default: `null`.

Internal: the site repository commit this system was built from; it labels generations and snapshots.

## `nixie.host.timezone`

*string*, default: `"UTC"`. Wizard section: network.

Time zone for logs, timers and the clock.

## `nixie.hostUi.enable`

*boolean*, default: `false`. Wizard section: services.

A separate web page for the host itself: files, a root terminal, the
journal, services, disks, and the nixie commands. It is Cockpit.
Turning it on widens the attack surface of a hardened host, which is
why it is off.

## `nixie.hostUi.listen`

*one of "tailnet", "lan+tailnet" (tailnet, lan+tailnet)*, default: `"tailnet"`. Wizard section: services.

Where the host page can be opened from. Guests can never reach it.

## `nixie.hostUi.port`

*16 bit unsigned integer; between 0 and 65535 (both inclusive)*, default: `9090`.

Port the host page listens on.

## `nixie.incus.enable`

*boolean*, default: `"true on the server profile"`.

Run the Incus daemon that hosts guests. On a desktop this is off unless you want both.

## `nixie.incus.images.remotes`

*attribute set of string*, default: `{"images": "https://images.linuxcontainers.org"}`.

Image servers guests of kind "image" and "vm" may pull from.

## `nixie.incus.oidc`

*null or (submodule)*, default: `null`.

Log in to the control panel with an identity provider instead of a certificate.

## `nixie.incus.pools`

*attribute set of (submodule)*, default: `"one ZFS pool on the data disk when present, otherwise on the system disk"`.

Incus storage pools.

## `nixie.incus.ui.listen`

*one of "tailnet", "lan+tailnet" (tailnet, lan+tailnet)*, default: `"\"tailnet\" when Tailscale is on, otherwise \"lan+tailnet\""`. Wizard section: network.

Where the control panel can be opened from. "tailnet" is only over
Tailscale and is the safest; "lan+tailnet" also answers on your local
network.

## `nixie.incus.ui.package`

*null or package*, default: `null`.

Replace the control panel with another web bundle. Empty means the Nixie panel.

## `nixie.incus.ui.port`

*16 bit unsigned integer; between 0 and 65535 (both inclusive)*, default: `8443`.

Port the control panel listens on.

## `nixie.kiosk.enable`

*boolean*, default: `false`.

Internal: show one web page full screen on the local display.

## `nixie.kiosk.tokenFile`

*string*, default: `"/run/nixie-setup/local-token"`.

Internal: a file whose content is appended as ?token= so the local browser pairs itself.

## `nixie.kiosk.url`

*string*, default: `"https://127.0.0.1:9443/"`.

Internal: the page the kiosk shows.

## `nixie.monitoring.dashboards`

*attribute set of absolute path*, default: `{}`.

Extra dashboards, name to JSON file.

## `nixie.monitoring.enable`

*boolean*, default: `false`. Wizard section: services.

Collect host, guest and GPU metrics with Prometheus so the dashboards
show history. Costs some memory and disk.

## `nixie.monitoring.extraScrapeConfigs`

*list of (attribute set)*, default: `[]`.

Extra Prometheus scrape configurations.

## `nixie.monitoring.gpuPowerCap`

*null or signed integer*, default: `null`.

Reference line on the GPU dashboard, in watts. Set it to your card's limit.

## `nixie.monitoring.grafana.enable`

*boolean*, default: `false`. Wizard section: services.

Also run Grafana with the default dashboards.

## `nixie.monitoring.grafana.port`

*16 bit unsigned integer; between 0 and 65535 (both inclusive)*, default: `3000`.

Port Grafana listens on.

## `nixie.monitoring.port`

*16 bit unsigned integer; between 0 and 65535 (both inclusive)*, default: `9091`.

Port Prometheus listens on, on this host only. Not 9090: the host page uses that one.

## `nixie.monitoring.retention`

*string*, default: `"30d"`.

How long metrics are kept.

## `nixie.network.address`

*null or string*, default: `null`. Wizard section: network.

A fixed address for this host. Empty means ask the router (DHCP).

## `nixie.network.bridge.mode`

*one of "unmanaged-lan", "managed-nat" (unmanaged-lan, managed-nat)*, default: `"unmanaged-lan"`. Wizard section: network.

"unmanaged-lan": guests appear on your network like any other computer
and get addresses from your router. "managed-nat": guests live on a
private network behind this host and share its address.

## `nixie.network.bridge.natSubnet`

*string*, default: `"10.90.0.0/24"`. Wizard section: network.

The private network used in managed-nat mode.

## `nixie.network.bridge.uplinks`

*list of string matching the pattern ^([0-9a-f]{2}:){5}[0-9a-f]{2}$*, default: `[]`. Wizard section: hardware.

Which physical network ports join the guest bridge, chosen by hardware
address so cable and slot changes do not matter. Written by the
installer.

## `nixie.network.bridge.vlanAware`

*boolean*, default: `false`. Wizard section: network.

Let guests use VLAN tags on the bridge.

## `nixie.network.dns`

*list of string*, default: `[]`. Wizard section: network.

Name servers, needed only with a fixed address.

## `nixie.network.egress`

*one of "direct", "exit-node" (direct, exit-node)*, default: `"direct"`. Wizard section: network.

"direct": guests reach the internet through your network.
"exit-node": every guest, declared or not, is forced through the
Tailscale exit node named below and cannot reach the internet any
other way. Needs the managed-nat bridge mode, because the host must
route the guests' traffic to force it anywhere.

## `nixie.network.exitNode`

*string*, default: `""`. Wizard section: network.

The tailnet name of the exit node used when egress is "exit-node".

## `nixie.network.exitNodeAllowLan`

*boolean*, default: `false`. Wizard section: network.

Under exit-node egress, still let guests reach your local network directly.

## `nixie.network.firewall.extraForwardRules`

*strings concatenated with "\n"*, default: `""`.

Extra nftables rules for the forward chain, for a site's own needs.

## `nixie.network.firewall.extraInputRules`

*strings concatenated with "\n"*, default: `""`.

Extra nftables rules for the host's input chain, for a site's own needs.

## `nixie.network.gateway`

*null or string*, default: `null`. Wizard section: network.

The router's address, needed only with a fixed address.

## `nixie.network.tailscale.authKeyFile`

*null or absolute path*, default: `null`. Wizard section: network.

A file with a Tailscale auth key so the host joins without a browser login.

## `nixie.network.tailscale.enable`

*boolean*, default: `false`. Wizard section: network.

Join a Tailscale network so you can reach this host and its web pages
from anywhere without opening ports on your router.

## `nixie.network.tailscale.serve`

*attribute set of string*, default: `{}`.

Extra `tailscale serve` entries (path to target) beyond what guests declare.

## `nixie.profile`

*one of "server", "desktop" (server, desktop)*, required. Wizard section: profile.

Which kind of machine this is. A server runs services as isolated Incus
guests and has no desktop software at all. A desktop is a full Hyprland
workstation and has no Incus, monitoring or backup stack unless you turn
them on. The choice is made at install and can be changed only by
reinstalling.

## `nixie.recipes`

*attribute set of module*, default: `{}`.

Site-provided recipes: a name to a NixOS module a guest may pick with `recipe`.

## `nixie.secrets.file`

*null or absolute path*, default: `null`.

The sops file holding this host's secrets: the administrator password
hash and whatever the enabled features need. Encrypted in git,
decrypted on the host with its own key. It is read from the site
checkout on the host at activation, never copied into the Nix store.

## `nixie.security.attestation.enable`

*boolean*, default: `false`. Wizard section: security.

Before asking for the passphrase, show a six-digit code computed by the
TPM from the boot measurements. Compare it with your authenticator app:
a wrong code means the boot chain was changed. Needs a TPM; run
`nixie reseal` after kernel updates.

## `nixie.security.duress.enable`

*boolean*, default: `false`. Wizard section: security.

A second, "duress" passphrase. Typing it at the unlock prompt destroys
every key slot on every encryption layer, making the data permanently
unreadable, then powers off. There is no undo.

## `nixie.security.encryption.enable`

*boolean*, default: `false`. Wizard section: security.

Encrypt the whole system so a stolen disk is unreadable. You type a
passphrase every time the machine starts. This is the only setting that
needs a reinstall to change; `nixie apply` refuses to flip it.

## `nixie.security.hardening.memoryEncryption.enable`

*boolean*, default: `false`. Wizard section: security.

Ask the processor to encrypt memory (AMD TSME) and turn on the IOMMU so
devices cannot read memory they were not given. Only takes effect on
hardware that supports it.

## `nixie.security.hardening.remoteJournal.enable`

*boolean*, default: `false`. Wizard section: security.

Send a copy of the system log to another machine so an intruder cannot erase it here.

## `nixie.security.hardening.remoteJournal.url`

*string*, default: `""`. Wizard section: security.

Where the log copy is sent (a systemd-journal-remote endpoint).

## `nixie.security.hardening.ssh.enable`

*boolean*, default: `true`. Wizard section: security.

Key-only SSH with modern ciphers, no root login and no forwarding.

## `nixie.security.hardening.usbguard.allow`

*list of string matching the pattern ^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}(/.*)?$*, default: `[]`.

USB devices allowed on top of the ones present at setup, as
"vendor:product" or "vendor:product/serial". `nixie usb allow` adds
to this list in the site.

## `nixie.security.hardening.usbguard.enable`

*boolean*, default: `false`. Wizard section: security.

Only USB devices present at setup are allowed. Anything plugged in
later is blocked until `nixie usb allow` adds it to nixie.security.hardening.usbguard.allow.

## `nixie.security.hardening.usbguard.rules`

*strings concatenated with "\n"*, default: `""`.

Extra usbguard rules, added after the list of devices present when this host was set up.

## `nixie.security.lockdown`

*one of "none", "integrity" (none, integrity)*, default: `"none"`. Wizard section: security.

Kernel lockdown. "integrity" stops even the administrator from changing
the running kernel. The stock kernel is built without it, so choosing
it rebuilds the kernel from source, and because NixOS does not sign
kernel modules, every driver that is not built in stops loading. Leave
it at "none" unless you have checked your hardware.

## `nixie.security.remoteUnlock.enable`

*boolean*, default: `false`. Wizard section: security.

Let you type the boot passphrase over SSH from another machine, using
the SSH keys of the administrator. Needed for a server without a
keyboard.

## `nixie.security.remoteUnlock.port`

*16 bit unsigned integer; between 0 and 65535 (both inclusive)*, default: `2222`. Wizard section: security.

Port the early-boot SSH server listens on.

## `nixie.security.secureBoot.enable`

*boolean*, default: `false`. Wizard section: security.

Sign the boot chain with your own keys so the firmware refuses to start
anything else. Setup walks you through putting the firmware into Setup
Mode. The keys live in the site's secrets.

## `nixie.security.tpm.enable`

*boolean*, default: `false`. Wizard section: security.

Add a second encryption layer tied to this machine's TPM chip plus a
PIN. The disk then opens only in this machine, and only with both the
PIN and the passphrase. Needs a TPM 2.0. A firmware update or a change
to the boot chain can require running `nixie reseal`.

## `nixie.security.tpm.pcrs`

*list of signed integer*, default: `[7]`. Wizard section: security.

Which boot measurements the TPM layer is tied to. 7 tracks the Secure
Boot state. Adding more makes unlocking stricter and re-enrolment more
frequent.

## `nixie.setup.kiosk`

*boolean*, default: `true`.

Internal: show the continuation wizard on the local display (off on desktops, which continue in their own session).

## `nixie.setup.packages`

*attribute set*, default: `{"deploy": null, "docs": null, "media": null, "nixie-cli": null, "nixie-cockpit": null, "nixie-installer": null, "nixie-iso": null, "nixie-panel": null, "nixie-setup": null, "nixie-setup-web": null, "nixie-ui": null, "test-iso": null}`.

Internal: the platform packages the setup generation runs.

## `nixie.setup.pending`

*boolean*, default: `false`.

Internal: true from first boot until the wizard's Finish step. While
true the system carries an extra boot entry with the on-screen wizard.

## `nixie.site.path`

*absolute path*, default: `"/etc/nixie/site"`.

Where the site checkout lives on this host. `nixie apply` runs from here.

## `nixie.site.ref`

*string*, default: `"main"`. Wizard section: site.

Branch of the site repository to follow.

## `nixie.site.repo`

*null or string*, default: `null`. Wizard section: site.

Git URL of the site repository. When set, `nixie apply` pulls it
before building; when empty, the checkout on the host is the only
copy.

## `nixie.ui.allowSiteEdits`

*boolean*, default: `false`.

Let the control panel commit to the site checkout on this host
("Declare") and run `nixie apply`. Off means the panel can only show
you text to paste into the site yourself.

## `nixie.ui.links`

*list of (submodule)*, default: `[]`.

Extra entries in the control panel navigation, for a site's own pages.

## `nixie.ui.theme`

*one of "graphite", "umber", "paper" (graphite, umber, paper)*, default: `"graphite"`. Wizard section: desktop.

The finish used by the control panel and the installer. Graphite and
Umber are dark; Paper is light. On a desktop the same finish colours
the whole environment.

## `nixie.ui.tokens`

*null or absolute path*, default: `null`.

A JSON file overriding any design token, for a site that wants its own colours.

