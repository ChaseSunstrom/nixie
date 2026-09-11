# Restore

`nixie.backups` runs restic on `nixie.backups.schedule` over `state/`, every
guest's `backup` paths and, by option, `media/`. `cache/` and the Incus
database are never included.

- List snapshots: `nixie backup list` (`--json` for scripts).
- Put everything back: `nixie restore latest` (or a snapshot id). Files are
  restored in place under `/`.
- Restore one path: `nixie restore latest --path /data/state/web`.
- Restore beside the live data to compare first:
  `nixie restore latest --path /data/state/web --to /root/restored`.
- Check the repository: `nixie backup verify` (also on the
  `nixie.backups.check` schedule; `nixie doctor` shows the result).

Local history: `nixie.backups.snapshots` keeps hourly, daily and weekly ZFS
snapshots of `state/`, and `nixie apply` takes one (`@pre-apply-<label>`,
last five kept) before it changes anything; guests get an Incus snapshot
`pre-apply-<label>` before an apply replaces them. `nixie rollback data`
and `nixie rollback guest` restore from these (rollback slice).

`nixie apply` afterwards recreates any instance that was missing; its state
is the restored directory.

Disaster kit: `nixie backup kit <file>` writes a passphrase-encrypted tar
with the LUKS headers, the host's age key, the restic secrets, a fresh
recovery key for the TPM layer and the rebuild steps; the README's "Rebuild
from nothing" section walks through using it.

Disk headers: setup wrote `header-backup.tar.age` (all LUKS headers, the TPM
lockout password and the attestation reseal password), encrypted to the
host's age key and every recipient in `.sops.yaml`. Decrypt with
`age -d -i <key> header-backup.tar.age | tar x` and restore a header with
`cryptsetup luksHeaderRestore <device> --header-backup-file <name>.header`.
