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
`pre-apply-<label>` before an apply replaces them. `nixie rollback data <name> [--snapshot s]` copies a state directory from one
beside the live one (`<name>.restored-<time>`), or over it with
`--in-place`; `nixie rollback data state` clones or rolls back the whole
dataset. `nixie rollback guest <name> [--snapshot s]` restores a guest's root
disk from an Incus snapshot; its `state/` mount is outside the snapshot.

Host generations: `nixie rollback --list` shows every kept generation with
its site commit, date and kernel; `nixie rollback` goes back one now,
`--generation N` to a specific one, `--boot-previous` only for the next
boot. The tty1 front panel offers the first and the last with one key. An
`apply --confirm-within 10m` reverts on its own unless `nixie apply
--confirm` follows.

`nixie apply` afterwards recreates any instance that was missing; its state
is the restored directory.

Both web surfaces show the same history: the host page has a History screen
(generations, guest and data snapshots, restic backups, with the command
that undoes each) and the control panel has one under History. Both read
`nixie rollback --json`.

Disaster kit: `nixie backup kit <file>` writes a passphrase-encrypted tar
with the LUKS headers, the host's age key, the restic secrets, a fresh
recovery key for the TPM layer and the rebuild steps; the README's "Rebuild
from nothing" section walks through using it.

Board, TPM or firmware replaced: boot with the recovery key at the
passphrase prompt (the TPM prompt fails first), then run
`nixie security reenroll` from a terminal or the front panel (`e`). It asks
for the recovery key and a PIN, walks Secure Boot enrolment (one reboot
when the firmware is in Setup Mode), rebinds the TPM, regenerates the
attestation secret and shows the new recovery key and QR once.

Disk headers: setup wrote `header-backup.tar.age` (all LUKS headers, the TPM
lockout password and the attestation reseal password), encrypted to the
host's age key and every recipient in `.sops.yaml`. Decrypt with
`age -d -i <key> header-backup.tar.age | tar x` and restore a header with
`cryptsetup luksHeaderRestore <device> --header-backup-file <name>.header`.
