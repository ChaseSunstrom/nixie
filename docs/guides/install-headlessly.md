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

On the ISO itself, tty2 runs the same wizard as a terminal program
(`nixie-deploy --local`); its menu can also set a root password to allow the
headless path in.
