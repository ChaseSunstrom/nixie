# Install headlessly

From a machine with Nix and SSH access to the target:

```
nix run github:OWNER/nixie#deploy -- --site ./my-site --host web1 root@target
```

The wizard prints the firmware prerequisites it cannot do for you (UEFI with
CSM off, TPM enabled and cleared, Secure Boot off with keys cleared, undeclared
disks unplugged) and asks for confirmation. If the target runs the Nixie ISO
it is used as is; otherwise `nixos-anywhere` kexecs it into an installer. The
host is built locally from the site, copied over, and phases 1 to 3 run on the
target with the same markers under `/var/lib/nixie/setup/`. Generated files
(`hardware.nix`, the secrets, `.sops.yaml`) are pulled back into the site.

After the reboot, continue over SSH: `nixie-phase 4` … `nixie-phase 8`, then
`nixie-finish`. With remote unlock on, the early-boot prompt is on port 2222.

On the ISO itself the terminal wizard (`nixie-deploy --local`) is the
**terminal** boot entry, on tty1, and Alt+F2 in the other two entries. It asks
the same questions as the web wizard and writes the site with the same code;
its menu can also set a root password to allow the headless path in. Before
anything is erased it offers to edit the site's files in `$EDITOR` (nano by
default) and checks that the host evaluates. If a phase fails, its output
stays on screen and choosing Install again skips the phases that finished.
After the restart, the terminal setup runs phases 4 to 8 by itself the same
way the web page does.
