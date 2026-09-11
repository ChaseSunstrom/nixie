# The local console

What a monitor plugged into a server shows, in each mode.

## Front panel (default)

`nixie.console.frontPanel.enable` is on by default on the server profile.
The first text console (tty1) shows, instead of a bare login: the host name
and addresses, the control panel address with a QR code, every instance as
a lane with its state, CPU seconds and memory and a heat strip, pool usage
bars, GPU temperature when a card is present, and anything `nixie doctor`
would flag. It is drawn in the chosen finish with 256-colour approximations
of the tokens. Press any key to get the normal `login` prompt; tty3 and up
are ordinary logins (Ctrl+Alt+F3).

The panel reads the same Incus socket as the web UI, read-only, and the
same metrics; it is never a second data path.

## Kiosk (optional)

`nixie.console.kiosk.enable` keeps the setup kiosk permanently: cage and a
browser on tty1 showing a lock page, then the full control panel. The lock
page checks the administrator password (through `su`) and, when a second
factor is enrolled, the same TOTP code the host page uses. After
`nixie.console.kiosk.idleLock` (default 10 minutes) of inactivity it locks
again. With the kiosk on, the front panel moves to tty2. The server closure
then contains exactly the kiosk stack (cage and the browser); a check proves
nothing else from the desktop list is present.

During setup (`nixie.setup.pending`), the setup generation owns tty1 and the
front panel is not started.

## GPU, VFIO and what you will see

The passphrase, PIN and attestation prompts, and tty1, render on the primary
GPU. With the NVIDIA driver the platform enables modesetting and
`nvidia-drm.fbdev=1` so the console stays visible after the driver loads.

Giving a guest an Incus `gpu` device shares the card: the host driver stays
in charge and the console keeps working. Passing the card through to a VM
with VFIO takes it away from the host; the console goes dark from that point
and comes back only when the VM releases the device. If the machine has one
card, choose between a console and VFIO.

## Switching consoles

Ctrl+Alt+F1 front panel (or kiosk), Ctrl+Alt+F2 front panel when the kiosk is
on, Ctrl+Alt+F3 and up plain logins. From the front panel, any key opens
`login`; exiting the shell returns to the panel.
