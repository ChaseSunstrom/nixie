# Security choices and what each costs

Each feature is one option with a description written for the installer; all
are off by default except that the ISO pre-selects encryption.

| option | what it does | what it costs |
|---|---|---|
| `nixie.security.encryption.enable` | LUKS2 under ZFS on the system disk (and the data disk, keyed from the root) | a passphrase at every boot; the only choice that needs a reinstall to change |
| `nixie.security.tpm.enable` | a second, outer LUKS layer bound to the TPM 2.0 with a required PIN, PCRs from `tpm.pcrs` (default 7) | a PIN at every boot in addition to the passphrase; a firmware update can require `nixie reseal` |
| `nixie.security.secureBoot.enable` | lanzaboote signs the boot chain with your own keys, kept in the site's secrets; systemd-boot enrols them from Setup Mode | a firmware visit to clear the vendor keys; unsigned media will not boot |
| `nixie.security.attestation.enable` | a TOTP code from `tpm2-totp` sealed to PCRs 4, 7, 8, 9, shown before the passphrase prompt | comparing a code with your app at boot; `nixie reseal` after kernel updates |
| `nixie.security.duress.enable` | a second passphrase (key slot 7) that erases every key slot on every layer and powers off | there is no undo |
| `nixie.security.remoteUnlock.enable` | early-boot SSH on `remoteUnlock.port` with the administrator's keys; prompts are relayed in order | the early-boot host key lives on the unencrypted boot partition, like any initrd secret |
| `nixie.security.lockdown` | kernel lockdown integrity mode | rebuilds the kernel and refuses unsigned modules, which on NixOS means every module; leave it at `none` unless you have checked your hardware |
| `nixie.security.hardening.*` | key-only SSH with modern ciphers, USBGuard with the setup-time allowlist, memory encryption and IOMMU parameters, remote journal | USBGuard blocks new devices until listed |

Always on with encryption: `panic=10`, a TPM lockout password set by setup
and kept on the encrypted root, and LUKS header backups for every layer,
encrypted with age to the host's key and every recipient in `.sops.yaml`.
With the TPM layer, setup also enrols a recovery key on the outer layer,
shows it once (text and QR) and keeps it nowhere on the machine; the boot
prompt falls back to it whenever the TPM cannot unseal, `nixie doctor` says
when that happened, and `nixie security reenroll` then rebinds the TPM
(Secure Boot, TPM + PIN, attestation, lockout password, header backups; the
same phases as setup, resumable across the enrolment reboot) and shows a
fresh key. USB devices plugged in later are blocked; `nixie usb` lists
them and `nixie usb allow` records one in the site. A keyboard is never
blocked while setup or a reenroll runs.

On the host: nftables default-drop inbound, guests can never reach the host's
SSH, control panel, host page or metrics ports, every platform unit passes
`systemd-analyze security` at "OK" or carries a comment naming its exposure,
and a check greps the closure for key-like material.
