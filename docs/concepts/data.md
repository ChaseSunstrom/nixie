# Data

The data root (`nixie.data.root`, default `/data`) separates things by
replaceability, and the three parts never share a directory:

- `state/<name>`: irreplaceable, backed up by restic when backups are on.
- `cache/<kind>/<name>`: re-fetchable, never backed up, filled by
  `nixie fetch` from `data.nix`.
- `media`: a library, backed up only when `nixie.data.mediaBackup` is on.

`data.nix` lists what lives in `cache/` by fetcher kind: `hf` (a Hugging
Face repository at a revision), `oci` (an image by digest into a local OCI
layout), `incus-images` (an image by fingerprint) and `http` (a URL with a
checksum). Each kind is a small file with one interface; a site adds a kind
with `nixie.data.kinds.<name> = ./my-kind.nix` and uses it in `data.nix`
without touching the platform.

Deleting `cache/` and running `nixie fetch` reproduces it wherever the
source still exists; a `.complete` marker per entry makes the fetch
idempotent. Backups cover `state/` plus every guest's `backup` paths and
exclude `cache/` and the Incus database, which `nixie apply` regenerates.
`nixie restore <snapshot>` is the counterpart.
