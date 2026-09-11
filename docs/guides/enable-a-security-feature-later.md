# Enable a security feature later

Every feature except encryption itself is a config change and an apply:

1. Set the option in the host's `settings`, for example
   `nixie.security.remoteUnlock.enable = true;` (which also needs a key in
   `nixie.auth.sshKeys`), or `nixie.security.secureBoot.enable = true;`.
2. `nixie apply`. The host switches; the initrd, the boot loader entries and
   the firewall follow.
3. Features with an enrolment step need it run once: Secure Boot (Setup Mode
   in the firmware, then `nixie-phase 5` and a reboot), TPM binding and
   attestation (`nixie-phase 6` with the passphrase and PIN in
   `/run/nixie/keys`, then a reboot; `nixie-phase 7` verifies). The setup
   generation's wizard can be brought back for this by setting
   `nixie.setup.pending = true` in the site, applying, and choosing the
   `nixie-setup` boot entry; Finish removes it again.

Turning a feature off is the same edit the other way. `nixie apply` refuses
to change `nixie.security.encryption.enable` on an installed system with a
message telling you to reinstall from the ISO.
