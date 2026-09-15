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
are the same scripts `nixie-phase N` runs.
