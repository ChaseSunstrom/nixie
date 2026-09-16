# Install graphically

1. Write the ISO (`nix build .#nixie-iso`, the file is
   `result/iso/nixie_<version>_x86_64-linux.iso`) to a USB stick and boot it
   with UEFI; in a VM, turn EFI on first (VirtualBox: Settings, System,
   Enable EFI). The boot menu has three entries:
   - **graphical, on this screen** (the default): the wizard fills the screen.
   - **from a browser on another device**: the screen shows a URL like
     `https://<address>:9443/`, a six-digit pairing code and the certificate
     fingerprint, with a QR code, for a browser on the same network.
   - **terminal**: the text wizard, described in
     [install-headlessly.md](install-headlessly.md).
   The graphical entry serves the same URL and code to other devices too, and
   Alt+F2 opens the terminal wizard from either of the first two.
2. Pair (if on another device): open the URL, compare the fingerprint the
   browser shows with the printed one, enter the code. It works once.
3. Walk the steps: Machine (server or desktop, and Standard or Hardened:
   Hardened turns on every security feature the installer can set without a
   decision from you — TPM and PIN, attestation, Secure Boot, duress, USB
   blocking, memory encryption, key-only SSH, a second factor — and walks
   through each one, asking for what it needs; kernel lockdown stays out
   because it builds the kernel from source), Disks (system disk, optional
   data disk, ports for guests), Name (the host name, and a new site, a git
   URL or an upload; a cloned site whose secrets already name this machine
   also takes its `age.key` from the backup kit), Security (encryption and
   the administrator), Network,
   Services (backups, monitoring, host page), and Desktop on a desktop (the
   Nixie desktop or HyDE, the finish, the apps). Each field shows its first
   sentence of help with More for the rest; advanced settings are behind
   More options. Secrets typed here stay in the backend until a phase needs
   them.
4. Review: a summary with a Change link per step, every file the install
   uses (`site.nix`, the host's `configuration.nix` and `hardware.nix`,
   `guests.nix`, `data.nix`, `flake.nix`) in an editor with Nix highlighting
   and completion and help for every `nixie.*` option, and All options, a
   searchable list that adds any option to `configuration.nix`. The host is
   evaluated the way the install will build it; an error is marked on its
   line, and Install waits for a passing check after the last edit. Your own
   settings belong in `hosts/<name>/configuration.nix`, which going back to a
   step never rewrites.
5. Install. Keys and secrets, then partition and install, as a checklist
   with the output under Details. Restart; if the firmware starts the
   installer again, remove the USB stick or detach the ISO from the VM.
6. The installed system starts straight into its setup generation, with no
   boot menu (hold Space while it starts to see one) and the passphrase asked
   on the Nixie splash. Setup continues in the front end chosen at the
   image's boot menu, on a desktop as on a server, and runs by itself as a
   checklist: steps this machine does not use are skipped without being
   shown. It stops only for what needs a person: one restart for Secure Boot
   enrolment (or a restart into the firmware settings when Setup Mode is not
   on yet), and the disk passphrase and a PIN to bind the TPM. Binding tests
   right away that the TPM and PIN open the disk, so no restart is needed to
   verify it; the recovery key, the attestation QR and the header-backup
   download stay on the page until Finish. Finish switches to the normal
   generation and removes the wizard; from then on the control panel is the
   only web page.

Everything the wizard did is in the site checkout on the host; the phases
are the same scripts `nixie-phase N` runs. If Finish stops, the setup page
shows why (a site that no longer evaluates, for one); fix it and press
Finish again.

After setup:

- **Unlocking.** The passphrase prompt is on the machine's screen; with
  remote unlock on, `ssh -t -p 2222 root@<address>` with the administrator's
  key asks the same.
- **Control panel.** `https://<address>:8443/ui/`. The first visit explains
  how to trust the browser: a client certificate made with `openssl` on the
  host and `incus config trust add-certificate`. The gear opens Settings.
- **The site.** `/etc/nixie/site` is a git checkout owned by root: edit it
  with `sudo`, then `sudo nixie apply`, which commits the edits first so
  every generation names its commit. With `nixie.site.repo` set (the wizard's
  Name step asks), apply also pushes what it applied there; `sudo nixie site
  key` prints the key the repository needs write access for.
- **Guests.** Add them to `guests.nix` in the site checkout
  (`/etc/nixie/site`, as root), commit, and run `nixie apply`; see
  [add-a-guest.md](add-a-guest.md). Instances made from the panel's Create
  are scratch instances on the same bridge.

## Trying it in a virtual machine

Any hypervisor with UEFI works; these are the settings that matter.

- **Firmware:** UEFI. VirtualBox: Settings, System, Enable EFI. libvirt and
  virt-manager: firmware "UEFI" (OVMF). A BIOS VM boots the image but the
  installer refuses to install.
- **Memory and disk:** 4 GB and 20 GB or more. The installer runs in RAM and
  builds the system onto the disk.
- **Network:** NAT is enough; the install downloads packages. To use the web
  entry from the host, forward a host port to the guest's 9443 (VirtualBox:
  Network, Port Forwarding) and open `https://127.0.0.1:<port>/`.
- **TPM (optional):** VirtualBox 7 and libvirt offer a virtual TPM 2.0; without
  one the wizard does not offer TPM binding.
- **Graphics:** no 3D acceleration is needed; the wizard falls back to
  software rendering.
- The image can stay attached while setup runs: each of setup's reboots goes
  to the installed system. Detach it after Finish; VirtualBox otherwise
  starts the installer on later boots.

`nix run .#test-iso` does all of this under QEMU and drives the install end
to end; `--usb` boots the image as a USB stick and `--security tpm` or
`--security secureboot` turns the security features on.
