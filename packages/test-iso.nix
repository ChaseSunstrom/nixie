# Boot the built ISO under QEMU with OVMF, a swtpm, a blank disk and
# user-mode networking (so the site is evaluated and built online, as on a
# real machine), drive the wizard over its HTTP API through the install,
# answer the unlock prompts on the serial console, and continue in the setup
# generation to Finish. Screenshots and the serial log land in
# tests/artifacts/.
#
#   --usb                 the image is a USB stick instead of a CD
#   --profile desktop     install a desktop: setup shows the wizard on its
#                         screen too, and Finish hands over to the greeter
#   --security plain      encryption only (default)
#   --security tpm        and TPM with PIN, attestation, duress, to Finish
#   --security secureboot and Secure Boot, until the keys are staged: firmware
#                         enrolment then needs real hardware (VERIFICATION.md)
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
    medium=(-cdrom "$iso" -boot d); security=plain; profile=server
    while [ $# -gt 0 ]; do
      case "$1" in
        --usb) medium=(-drive "if=none,id=stick,format=raw,readonly=on,file=$iso" -device qemu-xhci -device "usb-storage,drive=stick,bootindex=0") ;;
        --security) security=$2; shift ;;
        --profile) profile=$2; shift ;;
        *) echo "usage: nixie-test-iso [--usb] [--security plain|tpm|secureboot] [--profile server|desktop]" >&2; exit 2 ;;
      esac
      shift
    done
    echo "== medium ''${medium[0]}, security $security, profile $profile" | tee -a "$out/run.log"
    disk="$out/target.qcow2"; qemu-img create -q -f qcow2 "$disk" 40G; rm -f "$out/unlock-prompt.png"
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
    rc() { api -X POST -H 'Content-Type: application/json' -d "''${2:-{\}}" "https://127.0.0.1:9443/api/phase/$1" | tee -a "$out/phases.log" | sed -n 's/.*"rc": \([0-9]*\).*/\1/p' | tail -1; }
    phase() { [ "$(rc "$@")" = 0 ]; }
    pair() {
      code=$(fresh | grep -o 'Pairing code: [0-9]*' | tail -1 | awk '{print $3}')
      rm -f "$out/cookies"
      api -X POST -H 'Content-Type: application/json' -d "{\"code\":\"$code\"}" https://127.0.0.1:9443/api/pair | grep -q ok
    }
    # Answer each prompt as it appears until the setup service prints its
    # banner: how many there are, and which, depends on the layout and on
    # whether the TPM is enrolled yet. The first answer can wait $1 seconds,
    # as a person does: the root pool import once gave up after a minute.
    unlock() {
      words=0; pins=0; wait_first=''${1:-2}
      for _ in $(seq 450); do
        fresh | grep -q 'Pairing code:' && return 0
        n=$(fresh | grep -c 'Please enter passphrase' || true)
        p=$(fresh | grep -c 'Please enter.*PIN' || true)
        # The first prompt's screen: the splash, or the text console with
        # duress or attestation.
        [ $((n + p)) -gt 0 ] && [ ! -e "$out/unlock-prompt.png" ] && shot unlock-prompt
        if [ "$p" -gt "$pins" ]; then sleep "$wait_first"; console 1234; pins=$p; wait_first=2
        elif [ "$n" -gt "$words" ]; then sleep "$wait_first"; console hunter2; words=$n; wait_first=2; fi
        sleep 2
      done
      echo "timeout waiting for the setup generation" >&2; return 1
    }

    echo "== boot the ISO (graphical entry)" | tee -a "$out/run.log"
    mark; pid=$(boot "''${medium[@]}")
    sleep 6; shot iso-boot-menu
    waitfor 'Pairing code:' 300
    sleep 40; shot iso-kiosk
    pair
    # Exactly the target disk: never the installer's own medium, never zram.
    api https://127.0.0.1:9443/api/hardware | tee "$out/hardware.json" | jq -e '.efi and (.disks | length == 1)' >/dev/null
    disk_id=$(jq -r '.disks[] | select((.id // "") | test("nixie-system")) | .id' "$out/hardware.json")
    mac=$(jq -r '.nics[0].mac' "$out/hardware.json")
    api -X POST -H 'Content-Type: application/json' -d '{"passphrase":"hunter2","pin":"1234","duress":"wipe-me","admin-password":"nixie"}' https://127.0.0.1:9443/api/secrets >/dev/null
    features='{"nixie.security.encryption.enable":true}'
    [ "$security" != tpm ] || features='{"nixie.security.encryption.enable":true,"nixie.security.tpm.enable":true,"nixie.security.attestation.enable":true,"nixie.security.duress.enable":true}'
    [ "$security" != secureboot ] || features='{"nixie.security.encryption.enable":true,"nixie.security.secureBoot.enable":true}'
    # The installed system's console is the serial port, so its prompts and
    # banner reach this script.
    api -X POST -H 'Content-Type: application/json' -d "$(jq -n --arg d "$disk_id" --arg m "$mac" --arg p "$profile" --argjson f "$features" '{host:"iso-test",profile:$p,systemDisk:$d,uplinks:(if $p == "server" then [$m] else [] end),settings:({"nixie.auth.admin.name":"admin","boot.kernelParams":["console=tty0","console=ttyS0,115200n8"]} + $f)}')" https://127.0.0.1:9443/api/config | grep -q ok
    echo "== phases 1 to 3: the site flake is evaluated and built on the ISO" | tee -a "$out/run.log"
    start=$(date +%s)
    phase 1 && phase 2 && phase 3
    echo "install took $(( $(date +%s) - start )) s" | tee -a "$out/run.log"
    shot install-done
    api -X POST https://127.0.0.1:9443/api/reboot >/dev/null; stopped "$pid"

    echo "== first boot: unlock, then the setup generation" | tee -a "$out/run.log"
    mark; pid=$(boot)
    unlock 80
    sleep 20; shot setup-generation
    pair
    phase 4
    if [ "$security" = secureboot ]; then
      # Reaching the setup generation proves lanzaboote's default entry; in
      # Setup Mode phase 5 stages the keys and asks for the reboot (10).
      [ "$(rc 5)" = 10 ]
      printf 'quit\n' | socat - UNIX-CONNECT:"$out/monitor.sock" >/dev/null 2>&1 || true
      stopped "$pid"
      echo "test-iso: PASS, Secure Boot keys staged (artifacts in $out)" | tee -a "$out/run.log"
      exit 0
    fi
    phase 5
    api -X POST -H 'Content-Type: application/json' -d '{"passphrase":"hunter2","pin":"1234"}' https://127.0.0.1:9443/api/secrets >/dev/null
    phase 6
    if [ "$security" = tpm ]; then
      echo "== reboot: the TPM and PIN open the outer layer, the code is shown" | tee -a "$out/run.log"
      api -X POST https://127.0.0.1:9443/api/reboot >/dev/null; stopped "$pid"
      mark; pid=$(boot)
      waitfor 'Attestation code' 300
      unlock
      fresh | grep -q 'Please enter.*PIN'
      pair
    fi
    phase 7 && phase 8
    mark
    api -X POST https://127.0.0.1:9443/api/finish | tee -a "$out/phases.log" | grep -q '"ok": true'
    echo "== finish: the setup service goes, the control panel stays" | tee -a "$out/run.log"
    # The last line finish.sh prints, after the switch, boot default and clean-up.
    waitfor 'setup finished' 450
    gone=0
    for _ in $(seq 300); do curl -sk --max-time 3 https://127.0.0.1:9443/api/state >/dev/null || { gone=1; break; }; sleep 2; done
    [ "$gone" = 1 ] || { echo "the setup service still answers" >&2; exit 1; }
    # A server's control panel; a desktop's greeter is on the screenshot.
    [ "$profile" = desktop ] || curl -sfk --max-time 10 https://127.0.0.1:8443/ui/ | grep -q '<title>nixie</title>'
    sleep 15; shot finished
    printf 'quit\n' | socat - UNIX-CONNECT:"$out/monitor.sock" >/dev/null 2>&1 || true
    stopped "$pid"
    echo "test-iso: PASS (artifacts in $out)" | tee -a "$out/run.log"
  '';
}
