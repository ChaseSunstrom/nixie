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
3. Walk the steps: Profile, Hardware (system disk, optional data disk, ports
   for the bridge), Site (new here, clone a git URL, or upload), Security
   (each feature with its description; secrets typed here stay in the backend
   until a phase needs them), Authentication (administrator, keys, second
   factor with the authenticator QR), Network, Desktop (desktop profile only),
   Review (the generated `hardware.nix` and the `site.nix` it will write).
4. Install. Phases 1 to 3 run with streamed output: hardware facts, host
   identity and secrets, partition and install. Reboot; if the firmware starts
   the installer again, remove the USB stick or detach the ISO from the VM.
5. The installed system boots into its setup generation and the same URL
   continues on the machine's screen and in your browser: first boot, Secure
   Boot enrolment (with the Setup Mode checklist), TPM and PIN enrolment with
   the attestation QR and the header-backup download, verification reboot,
   apply. Finish switches to the normal generation and removes the wizard;
   from then on the control panel is the only web page.

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
