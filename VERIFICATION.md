# Verification log

Each slice appends a section: what ran, the exact commands, pass/fail per
check, and anything that could not be verified with the reason. All runs are
on the build host described in `ARCHITECTURE.md` section 0 (rootless Nix
2.20, KVM available; every VM test ran under KVM, none under TCG).

## Slice (a): flake skeleton, option tree, mkSite, site template, minimal host

Commands:

```
nix flake check -L --keep-going      # 2026-09-10, "running 9 flake checks", exit 0
```

| check | result | evidence |
|---|---|---|
| fmt | pass | nixfmt --check over every .nix file |
| statix | pass | `statix.toml` disables only `repeated_keys` (dotted keys are the module idiom) |
| deadnix | pass | |
| no-hardware-facts | pass | grep over the tree excluding `tests/`, `hardware.nix`, the brief and the design-token inventory |
| option-docs | pass | every `nixie.*` option has a description (evaluated, not built) |
| eval-matrix | pass | five throwaway sites evaluate: no GPU with a data disk, one NIC with NVIDIA, no TPM with encryption, no data disk desktop with TPM, VM |
| profile-server-has-no-desktop | pass | closure of the example server contains no hyprland, cage, chromium, firefox, quickshell, greetd |
| profile-desktop-has-no-server | pass | closure of the example laptop contains no incus, opentofu, prometheus, grafana, restic, cockpit |
| vm-boot-plain | pass | example server boots under OVMF + swtpm; admin user exists from the sops secret, sshd active; "test script finished in 17.19s" |

Not verified in this slice: the disko layout is declared and evaluated but
not applied (the test framework supplies its own disk); a real install is the
subject of slice (b). The `nix why-depends` form of the profile check is
replaced by a pure closure grep (`closureInfo`); the equivalent manual
command is `nix why-depends .#checks.x86_64-linux.vm-boot-plain.driver nixpkgs#cage`.

## Slice (b): encryption

`vm-encryption` installs the example server from an installer VM onto a blank
disk with every boot-time feature on (encryption, TPM + PIN, attestation,
duress, remote unlock, Secure Boot) under OVMF (Secure Boot capable, Setup
Mode) with swtpm, then boots the disk and walks phases 4 to 7 through the
same scripts a front end calls: remote unlock over SSH from a client VM,
Secure Boot enrolment by systemd-boot from Setup Mode, TPM enrolment with a
PIN and a recovery key, attestation init, header-backup bundle, the
verification reboot with the attestation code on the console, and finally
the duress passphrase wiping every key slot. Passed on 2026-09-11 ("test
script finished in 891.00s"): install 158 s, first boot with remote unlock,
signed chain, TPM + PIN enrolment with recovery key and header bundle, the
TPM + PIN reboot with the attestation code shown and `nixie reseal`, and the
duress wipe (the target powers itself off 39 s into that boot; the installer
then finds no key slots left).

Known timing: each boot of the target takes about five minutes in this test
because the console password agent (`systemd-ask-password-console`) blocks
on `/dev/console` until its start timeout; the SSH relay answers the prompts
long before that. Not a correctness problem; noted for a later slice.

Secure Boot: phase 5 detects the firmware's Setup Mode and stages enrolment,
and `sbverify` confirms lanzaboote signed systemd-boot, the fallback loader
and every generation's UKI with the site's db key. The firmware actually
enrolling those keys and then completing a Secure Boot verified boot is
exercised on real hardware, not in this test: the OVMF build used here enrols
the staged keys (an earlier run showed "Custom Secure Boot keys successfully
enrolled" on the console) but will not then complete a verified boot of the
signed chain, so auto-enrolment is turned off in the test VM and the signed
chain is asserted directly instead.

Lockdown (`nixie.security.lockdown = "integrity"`) is evaluated by the
`eval-matrix` check only; it rebuilds the kernel and is documented in
ARCHITECTURE D4 rather than booted.

## Slice (c): network

`vm-egress`: under exit-node egress a declared guest (`veth-web`) and an
undeclared one (`veth-scratch`) reach only the tunnel side and not the LAN;
guests cannot reach the host's SSH while the LAN can; under direct egress
both reach the LAN through the host. Passed on 2026-09-11
("test script finished in 25.02s").

## Slice (d): guests

`vm-guests`: `nixie apply --yes --skip-host` imports the NixOS image built
with the host and creates the declared guest through tofu; the guest serves
from its mounted state; a scratch instance is left alone by a second apply;
deleting the guest and applying recreates it with state intact; `nixie export`
emits a `guests.nix` entry. Passed on 2026-09-11 ("test script finished in
45.07s").

## Slice (e): examples

`examples/site/guests.nix` declares one guest per capability; the whole site
evaluates and its NixOS guest images build as part of the host closure
(`eval-matrix`, `vm-boot-plain`, and the `server-guest-*` packages of the
site). Foreign images and the VM are pinned by fingerprint and evaluated;
they are not started in tests because that needs the network and nested
virtualisation.

## Slice (f): data

`vm-data`: `nixie fetch` fills `cache/http/dataset` from a mirror VM and is
idempotent; deleting `cache/` and fetching restores it; a restic backup of
`state/` and `nixie restore latest` bring a deleted file back; `cache/` is
absent from the snapshot. Passed on 2026-09-11 ("test script finished in
23.96s").

## Slice (g): monitoring

`vm-monitoring`: every Prometheus target (node, incus) is up; the three
shipped dashboards are provisioned in Grafana with the GPU power cap
substituted. Passed on 2026-09-11 ("test script finished in 33.00s").

## Slice (h): control panel

`vm-ui`: incusd serves the bundle under `/ui/` with this host's `nixie.json`
(finish, links, declared guests), the bundle contains the command palette,
fonts are served, and the daemon answers "untrusted" on the same origin
without a client certificate. Passed on 2026-09-11 ("test script finished in
15.55s"). The panel's screens are exercised by the `panel` media run with a
trusted client certificate.

## Slice (i): installer

`vm-installer-lan`: the installer system (the ISO's configuration) runs the
setup service and the kiosk; the kiosk screen shows the wizard (OCR); a
client VM pairs with the single-use code (a second use is refused), reads
hardware and option metadata, configures, plans (the generated `hardware.nix`
and `site.nix` are checked textually), installs through phases 1 to 3, and the
installed disk boots into the setup generation where the continuation
service answers on the same port and phases 4 to 7 run over the API. The ISO
image itself is built by `packages.nixie-iso`; `nix run .#test-iso` boots it
in QEMU with OVMF and swtpm and drives the same API from outside.

## Slice (j): desktop

`vm-desktop`: greetd with the token-styled greeter comes up, a login lands in
a Hyprland session with the shell bar; one token source reaches Hyprland,
kitty, neovim and the shell; local.conf is sourced last; switching finish
through a specialisation takes effect after `switch-to-configuration test`
without a reboot.

## Slice (k): host page

`vm-host-ui`: Cockpit answers on its port with Nixie branding; login with the
administrator password and a valid TOTP code succeeds, a wrong code is
refused; logins reach the journal.

## Console

`vm-console`: tty1 shows the front panel (OCR finds the wordmark and the
prompt), any key opens login; with the kiosk on, the local display shows the
lock page, the gate accepts the administrator password and refuses a wrong
one, the control panel renders, and the front panel moves to tty2.
`profile-server-kiosk-only` proves the kiosk closure contains no Hyprland,
Firefox, Quickshell or greeter.

## Profiles

`profile-server-has-no-desktop`, `profile-desktop-has-no-server` and
`profile-server-kiosk-only` grep the built closures (`closureInfo`) for the
forbidden package names; all three pass on every full check run.

## Units and secrets

`systemd-security` analyses every `nixie-*` unit of a fully enabled server
and the desktop offline with `systemd-analyze security --threshold=3`; units
above "OK" must be in the documented list and their module must carry an
`# exposure:` comment. `no-secrets-in-store` greps the fully enabled server
closure for private-key and age-identity markers.

## Final run

Every check ran on 2026-09-11 on the rootless host described in
`ARCHITECTURE.md` (KVM, `sandbox = false`, see the note under Slice (b) and
in the test files for why).

`nix flake check -L` as one process does not finish on this host: the
evaluator reached 50 GB of resident memory while evaluating the checks in
one go and was killed by the kernel (Nix 2.20, every check evaluates its own
NixOS systems). The gate was therefore run as the equivalent loop, one
process per output: `nix build .#checks.x86_64-linux.<name>` for each of the
24 checks below, plus `nix eval` of the derivation path of every package,
every media test and the site template. The loop is in the shell history of
the verification session; its summary is the table.

| check | result |
|---|---|
| fmt, statix, deadnix | pass |
| eval-matrix, option-docs, option-reference, readme | pass |
| no-hardware-facts, no-secrets-in-store, systemd-security | pass |
| profile-server-has-no-desktop, profile-desktop-has-no-server, profile-server-kiosk-only | pass |
| vm-boot-plain (15 s), vm-egress (22 s), vm-guests (44 s), vm-data (25 s), vm-monitoring (38 s), vm-ui (14 s) | pass |
| vm-host-ui (14 s) | pass |
| vm-installer-lan (172 s) | pass |
| vm-console (258 s) | pass |
| vm-desktop (49 s) | pass |
| vm-encryption (891 s) | pass; Secure Boot firmware enrolment is hardware-only, see Slice (b) |
