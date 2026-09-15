#!/usr/bin/env bash
# Hardware facts as JSON for the wizard: disks, network ports, GPUs, TPM.
set -euo pipefail
# Not offered: compressed swap in RAM (the installer's zram) and the medium
# the installer was started from. A hybrid image written to a stick is mounted
# from the whole disk and a CD from its drive, so the medium is that name or
# its parent's.
src=$(findmnt -no SOURCE /iso 2>/dev/null || true)
boot=""; [ -z "$src" ] || boot=$(lsblk -no PKNAME "$src" 2>/dev/null | head -1 || true)
[ -n "$boot" ] || [ -z "$src" ] || boot=$(basename "$src")
disks=$(lsblk -J -d -b -o NAME,SIZE,MODEL,SERIAL,TYPE,PATH,TRAN | jq --arg boot "$boot" '[.blockdevices[] | select(.type == "disk" and (.name | startswith("zram") | not) and .name != $boot)]')
byid=$(for l in /dev/disk/by-id/*; do
  [ -e "$l" ] || continue
  case "$l" in */wwn-*|*-part*|*/lvm-*|*/dm-*) continue ;; esac
  printf '{"id":"%s","dev":"%s"}\n' "$l" "$(readlink -f "$l")"
done | jq -s .)
nics=$(ip -j link | jq '[.[] | select(.link_type == "ether" and (.ifname | startswith("veth") | not)) | {mac: .address, name: .ifname, up: (.operstate == "UP")}]')
gpu=none
if lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -q '\[10de:'; then gpu=nvidia
elif lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -q '\[1002:'; then gpu=amd
elif lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -q '\[8086:'; then gpu=intel; fi
tpm=false; [ -e /dev/tpmrm0 ] && tpm=true
efi=false; [ -d /sys/firmware/efi ] && efi=true
jq -n --argjson disks "$disks" --argjson byid "$byid" --argjson nics "$nics" --arg gpu "$gpu" --argjson tpm "$tpm" --argjson efi "$efi" \
  '{disks: [$disks[] | . as $d | {path: .path, size: .size, model: .model, serial: .serial, transport: .tran,
    # An object whose value expression yields nothing is not built at all, so
    # a bare `$byid[] | select(...)` drops every disk that has no by-id link
    # and the wizard offers nothing to install on. Null is what the UI expects.
    id: ([$byid[] | select(.dev == $d.path) | .id] | first)}], nics: $nics, gpu: $gpu, tpm: $tpm, efi: $efi}'
