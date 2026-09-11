# Restore

`nixie.backups` runs restic on `nixie.backups.schedule` over `state/`, every
guest's `backup` paths and, by option, `media/`. `cache/` and the Incus
database are never included.

- List snapshots: `restic-nixie snapshots`.
- Put everything back: `nixie restore latest` (or a snapshot id). Files are
  restored in place under `/`.
- Restore one guest's state: `nixie restore latest --include /data/state/web`.

`nixie apply` afterwards recreates any instance that was missing; its state
is the restored directory.

Disk headers: setup wrote `header-backup.tar.age` (all LUKS headers, the
recovery key of the TPM layer and the TPM lockout password), encrypted to the
host's age key and every recipient in `.sops.yaml`. Decrypt with
`age -d -i <key> header-backup.tar.age | tar x` and restore a header with
`cryptsetup luksHeaderRestore <device> --header-backup-file <name>.header`.
