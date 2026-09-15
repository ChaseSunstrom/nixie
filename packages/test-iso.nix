# Boot the built ISO under QEMU with OVMF, a swtpm, a blank disk and
# user-mode networking (so the site is evaluated and built online, as on a
# real machine), drive the wizard over its HTTP API through the install,
# answer the passphrase prompt on the serial console, and continue in the
# setup generation to Finish. Screenshots and the serial log land in
# tests/artifacts/. TPM, Secure Boot and duress enrolment are vm-encryption's.
{ pkgs, nixie-iso }:
let
  ovmf = (pkgs.OVMF.override { secureBoot = true; }).fd;
in
pkgs.writeShellApplication {
  name = "nixie-test-iso";
  runtimeInputs = with pkgs; [
    qemu_kvm
    swtpm
    socat
    curl
    jq
    coreutils
    gnugrep
    gawk
    imagemagick
    procps
  ];
  text = ''
    out=''${NIXIE_ARTIFACTS:-tests/artifacts}; mkdir -p "$out"
    iso=$(ls ${nixie-iso}/iso/nixie_*.iso)
    disk="$out/target.qcow2"; qemu-img create -q -f qcow2 "$disk" 40G
    vars="$out/efi-vars.fd"; cp ${ovmf}/FV/OVMF_VARS.fd "$vars"; chmod +w "$vars"
    # A failed run must not leave the VM holding the disk for the next one.
    trap 'pkill -f "$out/serial.sock" || true; pkill -f "tpmstate dir=$out/tpm" || true' EXIT
    mkdir -p "$out/tpm"
    # Under KVM, -cpu max offers instructions the host cannot always emulate
    # ("KVM internal error ... emulation failure" mid-install); host is exact.
    accel=tcg; cpu=max; [ -w /dev/kvm ] && { accel=kvm; cpu=host; }
    [ "$accel" = tcg ] && echo "no /dev/kvm: running under TCG, this is slow" | tee -a "$out/run.log"
    : >"$out/serial.log"
    # Everything boot starts in the background writes to files: an inherited
    # stdout keeps the caller's $(boot) open until QEMU exits. QEMU logs the
    # serial port itself: the socket takes one client, and a logger holding it
    # was dropped when console() connected, cancelling the passphrase prompt.
    boot() {
      # swtpm exits when QEMU disconnects; the state directory carries over.
      swtpm socket --tpmstate dir="$out/tpm" --ctrl type=unixio,path="$out/tpm/sock" --tpm2 --daemon
      qemu-system-x86_64 -machine q35,smm=on,accel=$accel -cpu $cpu -m 4096 -smp 4 -no-reboot \
        -drive if=pflash,format=raw,readonly=on,file=${ovmf}/FV/OVMF_CODE.fd \
        -drive if=pflash,format=raw,file="$vars" \
        -drive file="$disk",if=none,id=sys,format=qcow2 -device virtio-blk-pci,drive=sys,serial=nixie-system \
        -chardev socket,id=chrtpm,path="$out/tpm/sock" -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 \
        -netdev user,id=n0,hostfwd=tcp::9443-:9443,hostfwd=tcp::8443-:8443 -device virtio-net-pci,netdev=n0 \
        -chardev "socket,id=ser,path=$out/serial.sock,server=on,wait=off,logfile=$out/serial.log,logappend=on" -serial chardev:ser \
        -display none -monitor unix:"$out/monitor.sock",server,nowait "$@" \
        >>"$out/qemu.log" 2>&1 &
      echo $!
    }
    # QEMU is not this shell's child (boot runs in $(...)), so `wait` cannot
    # see it; with -no-reboot a guest reboot ends the process.
    stopped() { while kill -0 "$1" 2>/dev/null; do sleep 1; done; }
    console() { printf '%s\n' "$1" | socat - UNIX-CONNECT:"$out/serial.sock" >/dev/null 2>&1 || true; }
    shot() {
      printf 'screendump %s\n' "$out/$1.ppm" | socat - UNIX-CONNECT:"$out/monitor.sock" >/dev/null 2>&1 || true
      sleep 1; magick "$out/$1.ppm" "$out/$1.png" 2>/dev/null && rm -f "$out/$1.ppm" || true
    }
    # Only what the serial console printed since the last mark counts, so a
    # banner from before a reboot is never mistaken for the new one.
    since=0
    mark() { since=$(stat -c %s "$out/serial.log"); }
    fresh() { tail -c +"$((since + 1))" "$out/serial.log"; }
    waitfor() { for _ in $(seq "$2"); do fresh | grep -q "$1" && return 0; sleep 2; done; echo "timeout waiting for: $1" >&2; return 1; }
    api() { curl -sk -b "$out/cookies" -c "$out/cookies" "$@"; }
    phase() { api -X POST -H 'Content-Type: application/json' -d "''${2:-{\}}" "https://127.0.0.1:9443/api/phase/$1" | tee -a "$out/phases.log" | grep -q '"rc": 0'; }
    pair() {
      code=$(fresh | grep -o 'Pairing code: [0-9]*' | tail -1 | awk '{print $3}')
      rm -f "$out/cookies"
      api -X POST -H 'Content-Type: application/json' -d "{\"code\":\"$code\"}" https://127.0.0.1:9443/api/pair | grep -q ok
    }
    # Answer each passphrase prompt as it appears until the setup service
    # prints its banner: how many prompts there are depends on the layout.
    unlock() {
      answered=0
      for _ in $(seq 450); do
        fresh | grep -q 'Pairing code:' && return 0
        n=$(fresh | grep -c 'Please enter passphrase' || true)
        if [ "$n" -gt "$answered" ]; then sleep 2; console hunter2; answered=$n; fi
        sleep 2
      done
      echo "timeout waiting for the setup generation" >&2; return 1
    }

    echo "== boot the ISO (graphical entry)" | tee -a "$out/run.log"
    mark; pid=$(boot -cdrom "$iso" -boot d)
    sleep 6; shot iso-boot-menu
    waitfor 'Pairing code:' 300
    sleep 40; shot iso-kiosk
    pair
    api https://127.0.0.1:9443/api/hardware | tee "$out/hardware.json" | jq -e '.efi and (.disks | length > 0)' >/dev/null
    disk_id=$(jq -r '.disks[] | select((.id // "") | test("nixie-system")) | .id' "$out/hardware.json")
    mac=$(jq -r '.nics[0].mac' "$out/hardware.json")
    api -X POST -H 'Content-Type: application/json' -d '{"passphrase":"hunter2","admin-password":"nixie"}' https://127.0.0.1:9443/api/secrets >/dev/null
    # The installed system's console is the serial port, so its passphrase
    # prompt and banner reach this script.
    api -X POST -H 'Content-Type: application/json' -d "$(jq -n --arg d "$disk_id" --arg m "$mac" '{host:"iso-test",profile:"server",systemDisk:$d,uplinks:[$m],settings:{"nixie.auth.admin.name":"admin","nixie.security.encryption.enable":true,"boot.kernelParams":["console=tty0","console=ttyS0,115200n8"]}}')" https://127.0.0.1:9443/api/config | grep -q ok
    echo "== phases 1 to 3: the site flake is evaluated and built on the ISO" | tee -a "$out/run.log"
    start=$(date +%s)
    phase 1 && phase 2 && phase 3
    echo "install took $(( $(date +%s) - start )) s" | tee -a "$out/run.log"
    shot install-done
    api -X POST https://127.0.0.1:9443/api/reboot >/dev/null; stopped "$pid"

    echo "== first boot: unlock, then the setup generation" | tee -a "$out/run.log"
    mark; pid=$(boot)
    unlock
    sleep 20; shot setup-generation
    pair
    phase 4 && phase 5
    api -X POST -H 'Content-Type: application/json' -d '{"passphrase":"hunter2"}' https://127.0.0.1:9443/api/secrets >/dev/null
    phase 6 && phase 7 && phase 8
    mark
    api -X POST https://127.0.0.1:9443/api/finish | tee -a "$out/phases.log" | grep -q '"ok": true'
    echo "== finish: the setup service goes, the control panel stays" | tee -a "$out/run.log"
    # The last line finish.sh prints, after the switch, boot default and clean-up.
    waitfor 'setup finished' 450
    gone=0
    for _ in $(seq 300); do curl -sk --max-time 3 https://127.0.0.1:9443/api/state >/dev/null || { gone=1; break; }; sleep 2; done
    [ "$gone" = 1 ] || { echo "the setup service still answers" >&2; exit 1; }
    curl -sfk --max-time 10 https://127.0.0.1:8443/ui/ | grep -q '<title>nixie</title>'
    sleep 15; shot finished
    printf 'quit\n' | socat - UNIX-CONNECT:"$out/monitor.sock" >/dev/null 2>&1 || true
    stopped "$pid"
    echo "test-iso: PASS (artifacts in $out)" | tee -a "$out/run.log"
  '';
}
