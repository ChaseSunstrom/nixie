# Boot the ISO under QEMU with Secure Boot capable OVMF in Setup Mode, a
# swtpm, a blank disk and user-mode networking, then drive the wizard over
# its HTTP API through the install and the first reboot, answering the boot
# prompts on the serial console. Artifacts land in tests/artifacts/.
{ pkgs, nixie-iso }:
let
  ovmf = pkgs.OVMF.override { secureBoot = true; };
in
pkgs.writeShellApplication {
  name = "nixie-test-iso";
  runtimeInputs = with pkgs; [
    qemu_kvm
    swtpm
    socat
    curl
    jq
    openssh
    coreutils
    gnugrep
    gawk
    procps
  ];
  text = ''
    out=''${NIXIE_ARTIFACTS:-tests/artifacts}; mkdir -p "$out"
    iso=$(ls ${nixie-iso}/iso/*.iso)
    disk="$out/target.qcow2"; qemu-img create -q -f qcow2 "$disk" 20G
    vars="$out/efi-vars.fd"; cp ${ovmf}/FV/OVMF_VARS.fd "$vars"; chmod +w "$vars"
    mkdir -p "$out/tpm"; swtpm socket --tpmstate dir="$out/tpm" --ctrl type=unixio,path="$out/tpm/sock" --tpm2 --daemon
    accel=tcg; [ -w /dev/kvm ] && accel=kvm
    [ "$accel" = tcg ] && echo "no /dev/kvm: running under TCG, this is slow" | tee -a "$out/run.log"
    : >"$out/serial.log"
    boot() {
      qemu-system-x86_64 -machine q35,smm=on,accel=$accel -cpu max -m 4096 -smp 4 \
        -drive if=pflash,format=raw,readonly=on,file=${ovmf}/FV/OVMF_CODE.fd \
        -drive if=pflash,format=raw,file="$vars" \
        -drive file="$disk",if=virtio,format=qcow2,serial=nixie-system \
        -chardev socket,id=chrtpm,path="$out/tpm/sock" -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 \
        -netdev user,id=n0,hostfwd=tcp::9443-:9443,hostfwd=tcp::2222-:22,hostfwd=tcp::2223-:2222 -device virtio-net-pci,netdev=n0 \
        -display none -serial unix:"$out/serial.sock",server,nowait -monitor unix:"$out/monitor.sock",server,nowait "$@" &
      pid=$!
      sleep 1
      socat -u UNIX-CONNECT:"$out/serial.sock" - >>"$out/serial.log" 2>/dev/null &
      echo $pid
    }
    console() { printf '%s\n' "$1" | socat - UNIX-CONNECT:"$out/serial.sock" >/dev/null 2>&1 || true; }
    shot() { printf 'screendump %s\n' "$out/$1.ppm" | socat - UNIX-CONNECT:"$out/monitor.sock" >/dev/null 2>&1 || true; }
    waitfor() { for _ in $(seq "$2"); do grep -q "$1" "$out/serial.log" && return 0; sleep 2; done; echo "timeout waiting for: $1" >&2; return 1; }
    api() { curl -sk -b "$out/cookies" -c "$out/cookies" "$@"; }
    phase() { api -X POST -H 'Content-Type: application/json' -d "''${2:-{\}}" "https://127.0.0.1:9443/api/phase/$1" | tee -a "$out/phases.log" | grep -q '"rc": 0'; }

    echo "== boot ISO" | tee -a "$out/run.log"
    pid=$(boot -cdrom "$iso" -boot d)
    waitfor 'Pairing code:' 300
    code=$(grep -o 'Pairing code: [0-9]*' "$out/serial.log" | tail -1 | awk '{print $3}')
    shot iso-console
    api -X POST -H 'Content-Type: application/json' -d "{\"code\":\"$code\"}" https://127.0.0.1:9443/api/pair | grep -q ok
    api https://127.0.0.1:9443/api/hardware | tee "$out/hardware.json" | jq -e '.disks | length > 0' >/dev/null
    disk_id=$(jq -r '.disks[] | select((.id // "") | test("nixie-system")) | .id' "$out/hardware.json")
    mac=$(jq -r '.nics[0].mac' "$out/hardware.json")
    api -X POST -H 'Content-Type: application/json' -d '{"passphrase":"hunter2","pin":"1234","duress":"wipe-me","admin-password":"nixie"}' https://127.0.0.1:9443/api/secrets >/dev/null
    api -X POST -H 'Content-Type: application/json' -d "$(jq -n --arg d "$disk_id" --arg m "$mac" '{host:"iso-test",profile:"server",systemDisk:$d,uplinks:[$m],settings:{"nixie.auth.admin.name":"admin","nixie.security.encryption.enable":true,"nixie.security.tpm.enable":true,"nixie.security.attestation.enable":true,"nixie.security.duress.enable":true,"nixie.security.secureBoot.enable":true}}')" https://127.0.0.1:9443/api/config | grep -q ok
    phase 1 && phase 2 && phase 3
    shot install-done
    api -X POST https://127.0.0.1:9443/api/reboot >/dev/null; wait "$pid" || true

    echo "== first boot: passphrase twice until the TPM is enrolled" | tee -a "$out/run.log"
    pid=$(boot)
    waitfor 'Please enter passphrase' 300; console hunter2
    waitfor 'Please enter passphrase for disk.*rpool)' 300; console hunter2
    waitfor 'Nixie setup' 600
    shot continuation
    echo "== continuation phases over the same API" | tee -a "$out/run.log"
    code=$(grep -o 'Pairing code: [0-9]*' "$out/serial.log" | tail -1 | awk '{print $3}')
    api -X POST -H 'Content-Type: application/json' -d "{\"code\":\"$code\"}" https://127.0.0.1:9443/api/pair | grep -q ok
    phase 4
    api -X POST -H 'Content-Type: application/json' -d '{}' https://127.0.0.1:9443/api/phase/5 | tee -a "$out/phases.log" | grep -q '"rc": 10'
    api -X POST https://127.0.0.1:9443/api/reboot >/dev/null; wait "$pid" || true
    pid=$(boot)
    waitfor 'Please enter passphrase' 300; console hunter2
    waitfor 'Please enter passphrase for disk.*rpool)' 300; console hunter2
    waitfor 'Nixie setup' 600
    code=$(grep -o 'Pairing code: [0-9]*' "$out/serial.log" | tail -1 | awk '{print $3}')
    api -X POST -H 'Content-Type: application/json' -d "{\"code\":\"$code\"}" https://127.0.0.1:9443/api/pair | grep -q ok
    phase 5
    api -X POST -H 'Content-Type: application/json' -d '{"passphrase":"hunter2","pin":"1234"}' https://127.0.0.1:9443/api/secrets >/dev/null
    phase 6
    api https://127.0.0.1:9443/api/download/header-backup -o "$out/headers.tar.age"
    api https://127.0.0.1:9443/api/attestation | jq -r .text >"$out/attestation-qr.txt"
    api -X POST https://127.0.0.1:9443/api/reboot >/dev/null; wait "$pid" || true
    pid=$(boot)
    waitfor 'Attestation code: [0-9]' 300
    waitfor 'Please enter TPM2 PIN' 300; console 1234
    waitfor 'Please enter passphrase for disk.*rpool)' 300; console hunter2
    waitfor 'Nixie setup' 600
    shot booted
    code=$(grep -o 'Pairing code: [0-9]*' "$out/serial.log" | tail -1 | awk '{print $3}')
    api -X POST -H 'Content-Type: application/json' -d "{\"code\":\"$code\"}" https://127.0.0.1:9443/api/pair | grep -q ok
    phase 7 && phase 8
    api -X POST https://127.0.0.1:9443/api/finish | tee -a "$out/phases.log" | grep -q '"ok": true'
    echo "== finished; the setup service is gone" | tee -a "$out/run.log"
    sleep 5; ! curl -sk --max-time 3 https://127.0.0.1:9443/api/state >/dev/null
    printf 'quit\n' | socat - UNIX-CONNECT:"$out/monitor.sock" >/dev/null 2>&1 || true
    wait "$pid" || true
    echo "test-iso: PASS (artifacts in $out)" | tee -a "$out/run.log"
  '';
}
