# Hosts

A host is one machine with one profile: `nixie.profile = "server"` or
`"desktop"`. The profile is chosen at install and decides which software the
system contains. A server has no compositor, browser or desktop package; a
desktop has no Incus, tofu, monitoring or backup stack unless the site
enables them. A check on the example sites proves both directions from the
built closures.

What every host shares: the boot chain and security stack (encryption, TPM
binding, Secure Boot, attestation, duress, remote unlock, hardening options),
the installer and the phase engine, the `nixie` command, the sops wiring and
the data root layout.

`hardware.nix` is the one generated file. It carries only facts: the system
and data disk by stable id, the uplink ports by hardware address, the kind of
GPU, whether there is a TPM, the ZFS host id and the kernel modules the
machine needs to boot. Everything else is a choice in `settings`.

Every option that is optional is off by default and can be turned on or off
later with a config change and `nixie apply`, except full-disk encryption,
which the CLI refuses to flip on an installed system.
