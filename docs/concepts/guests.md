# Guests

`guests.nix` is the only place guest names appear. From it the platform
derives the Incus instance (through terranix and OpenTofu), the nic named
`veth-<name>` on the host side, the disk devices for mounts with ownership
shifting, the GPU device, the firewall chain keyed on that veth, the backup
paths, the scrape labels, the dashboard variables and the control panel's
declared list.

Three kinds: `nixos` (built from the site with nixpkgs' LXC image module and
imported by hash), `image` (a foreign container image pinned by
fingerprint, configured with cloud-init) and `vm` (the same, as a virtual
machine).

Two tiers, visible everywhere: **declared** guests live in `guests.nix`,
survive a reinstall and get every derived piece; **scratch** instances are
made from the control panel or `incus launch`, are real, are never touched by
`nixie apply`, and still get the default egress policy through the catch-all
chain. The panel labels each and offers Export (a `guests.nix` entry for the
instance as it is) and, with `nixie.ui.allowSiteEdits`, Declare.

Recipes are ready-made guest modules: `static-web` (nginx over a mounted
directory) and `oci-service` (one container image under podman, no daemon).
A site adds its own through `nixie.recipes`.

A changed NixOS guest image gets a new alias with the store hash in it, so
`nixie apply` replaces the instance through tofu. State lives in mounts from
the data root and is untouched; removing a guest destroys the instance and
never its `state/` directory.
