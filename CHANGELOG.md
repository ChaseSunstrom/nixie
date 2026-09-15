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

First build of the platform against nixpkgs 26.05: option tree, `mkSite`,
security stack, network and egress policy, Incus with declared guests, data
manifest and backups, monitoring, control panel, installer (kiosk, LAN,
headless), desktop profile, host page, console front panel and kiosk.
See `VERIFICATION.md` for what has been proven in VMs.
