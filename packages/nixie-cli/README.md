# nixie (the command)

`nixie apply [--yes] [--skip-host]` applies the site checkout: host switch,
guest images by hash, `tofu apply` for declared instances (a plan is shown
first unless `--yes`). `nixie export <instance>` prints a `guests.nix` entry.
`nixie fetch` fills the cache from `data.nix`; `nixie restore [snapshot]` puts
`state/` back; `nixie reseal` reseals attestation to the running boot chain;
`nixie doctor` reports TPM, attestation, Secure Boot, key slots, guests and
disk space; `nixie menu` opens the desktop menu.
