#!/usr/bin/env bash
# Phase 1: write hosts/<name>/hardware.nix from the choices in state.json plus
# the modules this machine needs to boot. Nothing else is written.
set -euo pipefail
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"
phase_start 1
need jq nixos-generate-config
# Every front end refuses here, before a disk is touched.
[ -d /sys/firmware/efi ] || die "this machine started the installer in legacy BIOS mode, and Nixie installs a UEFI system. Turn on UEFI boot in the firmware (VirtualBox: Settings, System, Enable EFI), start the installer again, and choose it from the boot menu."
h=$(host); dir="$NIXIE_SITE/hosts/$h"; mkdir -p "$dir"

generated=$(nixos-generate-config --show-hardware-config --no-filesystems 2>/dev/null || true)
modules=$(printf '%s\n' "$generated" | sed -n 's/.*boot.initrd.availableKernelModules = \(\[.*\]\);/\1/p' | head -1)
kmods=$(printf '%s\n' "$generated" | sed -n 's/.*boot.kernelModules = \(\[.*\]\);/\1/p' | head -1)
micro=$(printf '%s\n' "$generated" | grep -E 'hardware.cpu.(intel|amd).updateMicrocode' | sed 's/^ *//' || true)
uplinks=$(state '.uplinks | map("\"" + . + "\"") | join(" ")')
data=$(state '.dataDisk // empty')
hostid=$(state '.hostId // empty')
[ -n "$hostid" ] || hostid=$(head -c4 /dev/urandom | od -An -tx4 | tr -d ' ')

{
  echo "# Written by the Nixie installer (phase 1). Hardware facts only."
  echo "{"
  echo "  nixie.disks.system = \"$(state .systemDisk)\";"
  echo "  nixie.disks.data = ${data:+\"$data\"}${data:-null};"
  echo "  nixie.network.bridge.uplinks = [ $uplinks ];"
  echo "  nixie.hardware.gpu = \"$(state '.gpu // "none"')\";"
  echo "  nixie.hardware.tpm = $(state '.tpm // false');"
  echo "  networking.hostId = \"$hostid\";"
  [ -n "$modules" ] && echo "  boot.initrd.availableKernelModules = $modules;"
  [ -n "$kmods" ] && echo "  boot.kernelModules = $kmods;"
  [ -n "$micro" ] && echo "  $micro"
  echo "}"
} >"$dir/hardware.nix"
jq --arg id "$hostid" '.hostId = $id' "$STATE" >"$STATE.new" && mv "$STATE.new" "$STATE"
log "wrote $dir/hardware.nix"
phase_finish
