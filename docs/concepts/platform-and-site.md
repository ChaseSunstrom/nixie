# Platform and site

Nixie is two repositories.

The **platform** is this repository: the `nixie.*` option tree, the profiles,
the installer, the control panel and the checks. It holds nothing about any
particular person's services, hardware or network; a check greps for such
facts and fails the build if it finds one outside `tests/` and the generated
hardware files.

A **site** is your repository. It is small: `site.nix` (plain data, one
entry per host), `guests.nix`, `data.nix`, one `hosts/<name>/hardware.nix` per
machine (written by the installer), and sops-encrypted secrets. Its
`flake.nix` is two lines: it takes the platform as an input and calls
`nixie.lib.mkSite ./site.nix`. That call yields everything: NixOS systems,
guest images, the tofu configuration, checks.

`settings` in a host entry is a full NixOS module, so a site can set any
`nixie.*` option and any NixOS option, or import its own modules. Nothing
requires patching the platform; section "Extending" lists the hook points.

Secrets are never copied into the Nix store. The sops file is read from the
site checkout on the host (`nixie.site.path`, default `/etc/nixie/site`) at
activation and decrypted with the host's own age key, made by the installer
and kept in `/var/lib/nixie/age.key`.
