# shellcheck shell=bash
out=${NIXIE_ARTIFACTS:-tests/artifacts}; mkdir -p "$out"
iso=$(ls @iso@/iso/nixie_*.iso)
medium=(-cdrom "$iso" -boot d); security=plain; profile=server; kiosk=0; tpm=tis; bus=virtio
while [ $# -gt 0 ]; do
  case "$1" in
    # The wizard driven on the machine's own screen. That image differs by
    # one Chromium flag -- the debugger this needs to reach the page -- and
    # is the only one the platform builds with it.
    --kiosk) kiosk=1; iso=$(ls @kioskIso@/iso/nixie_*.iso); medium=(-cdrom "$iso" -boot d) ;;
    # Which interface the TPM speaks. Real machines vary, and so do the
    # hypervisors: VirtualBox presents a CRB device where QEMU's default
    # here is TIS, and the driver for each is a different kernel module.
    --tpm) tpm=$2; shift ;;
    # What the system disk hangs off. VirtualBox gives a new machine a SATA
    # controller where this gives it virtio, and the driver for each is a
    # different kernel module -- one the installed initrd has to carry, or
    # the disk it boots from is not there.
    --disk) bus=$2; shift ;;
    --usb) medium=(-drive "if=none,id=stick,format=raw,readonly=on,file=$iso" -device qemu-xhci -device "usb-storage,drive=stick,bootindex=0") ;;
    --security) security=$2; shift ;;
    --profile) profile=$2; shift ;;
    *) echo "usage: nixie-test-iso [--kiosk] [--usb] [--tpm tis|crb] [--disk virtio|sata] [--security plain|tpm|secureboot|hardened] [--profile server|desktop]" >&2; exit 2 ;;
  esac
  shift
done
# The device the drive hangs off, and the controller it needs when it is not
# virtio: by-id names come from the serial either way.
if [ "$bus" = sata ]; then
  sysdisk=(-device "ahci,id=ahci" -device "ide-hd,bus=ahci.0,drive=sys,serial=nixie-system")
else
  sysdisk=(-device "virtio-blk-pci,drive=sys,serial=nixie-system")
fi
echo "== medium ${medium[0]}, security $security, profile $profile, tpm $tpm, disk $bus" | tee -a "$out/run.log"
disk="$out/target.qcow2"; qemu-img create -q -f qcow2 "$disk" 40G; rm -f "$out/unlock-prompt.png"
vars="$out/efi-vars.fd"; cp @ovmf@/FV/OVMF_VARS.fd "$vars"; chmod +w "$vars"
# A failed run must not leave the VM holding the disk for the next one.
# A guard, not a repair: the phases keep the recovery key out of their own
# output today, and the logs here show systemd's message with the key line
# empty. But these files are what VERIFICATION.md links to and what a person
# attaches to a bug report, and the key is the one secret among them that
# opens the disk -- so anything shaped like one is redacted on the way out,
# whatever ends the run. Word-bounded, because a nix store hash can carry
# that shape inside it and those are not secrets.
redact() {
  find "$out" -type f \( -name '*.log' -o -name '*.txt' -o -name '*.json' \) -print0 2>/dev/null \
    | xargs -0 -r sed -i -E 's/\b[0-9a-z]{8}(-[0-9a-z]{5}){4}\b/<recovery key redacted>/g' || true
}
trap 'pkill -f "$out/serial.sock" || true; pkill -f "tpmstate dir=$out/tpm" || true; redact' EXIT
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
    -drive if=pflash,format=raw,readonly=on,file=@ovmf@/FV/OVMF_CODE.fd \
    -drive if=pflash,format=raw,file="$vars" \
    -drive file="$disk",if=none,id=sys,format=qcow2 "${sysdisk[@]}" \
    -chardev socket,id=chrtpm,path="$out/tpm/sock" -tpmdev emulator,id=tpm0,chardev=chrtpm -device "tpm-$tpm,tpmdev=tpm0" \
    -netdev "user,id=n0,hostfwd=tcp::9443-:9443,hostfwd=tcp::8443-:8443${kiosk:+,hostfwd=tcp::9222-:9223}" -device virtio-net-pci,netdev=n0 \
    -chardev "socket,id=ser,path=$out/serial.sock,server=on,wait=off,logfile=$out/serial.log,logappend=on" -serial chardev:ser \
    -display none -monitor unix:"$out/monitor.sock",server,nowait "$@" \
    >>"$out/qemu.log" 2>&1 &
  echo $!
}
# QEMU is not this shell's child (boot runs in $(...)), so `wait` cannot
# see it; with -no-reboot a guest reboot ends the process.
stopped() { while kill -0 "$1" 2>/dev/null; do sleep 1; done; }
console() { printf '%s\n' "$1" | socat - UNIX-CONNECT:"$out/serial.sock" >/dev/null 2>&1 || true; }
# The same, typed at the machine's own keyboard: a machine installed by the
# wizard has no serial console to send anything to.
mon() { printf '%s\n' "$1" | socat - UNIX-CONNECT:"$out/monitor.sock" >/dev/null 2>&1 || true; }
keys() {
  for c in $(printf '%s' "$1" | grep -o .); do mon "sendkey $c"; sleep 0.1; done
  mon "sendkey ret"
}
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
rc() { api -X POST -H 'Content-Type: application/json' -d "${2:-{\}}" "https://127.0.0.1:9443/api/phase/$1" | tee -a "$out/phases.log" | sed -n 's/.*"rc": \([0-9]*\).*/\1/p' | tail -1; }
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
  words=0; pins=0; wait_first=${1:-2}
  for _ in $(seq 450); do
    fresh | grep -q 'Pairing code:' && return 0
    # systemd's own wording on a text console, or the splash's labels in
    # Plymouth's text view, which a serial console gets.
    n=$(fresh | grep -cE 'Please enter passphrase|(Passphrase or recovery key|Disk passphrase):' || true)
    p=$(fresh | grep -cE 'Please enter.*PIN|PIN:' || true)
    # The first prompt's screen.
    [ $((n + p)) -gt 0 ] && [ ! -e "$out/unlock-prompt.png" ] && shot unlock-prompt
    if [ "$p" -gt "$pins" ]; then sleep "$wait_first"; console 1234; pins=$p; wait_first=2
    elif [ "$n" -gt "$words" ]; then sleep "$wait_first"; console hunter2; words=$n; wait_first=2; fi
    sleep 2
  done
  echo "timeout waiting for the setup generation" >&2; return 1
}

echo "== boot the ISO (graphical entry)" | tee -a "$out/run.log"
mark; pid=$(boot "${medium[@]}")
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
# What the wizard's hardened setup writes, Secure Boot included: leaving it
# out meant the combination a person actually installs -- the signed boot
# chain with the whole security stack in the initrd behind it -- was never
# booted here, while each half was. This firmware will not boot the signed
# chain once the keys are enrolled (see the secureboot run), so the run
# stops where that one does, after phase 5 stages them; the first start,
# which is where this combination failed for someone, happens before that.
[ "$security" != hardened ] || features='{"nixie.security.encryption.enable":true,"nixie.security.tpm.enable":true,"nixie.security.attestation.enable":true,"nixie.security.secureBoot.enable":true,"nixie.security.duress.enable":true,"nixie.security.hardening.ssh.enable":true,"nixie.security.hardening.usbguard.enable":true,"nixie.security.hardening.memoryEncryption.enable":true,"nixie.auth.ssh.passwordLogin":false,"nixie.auth.ssh.keyAndPassword":true}'
# The installed system's console is the serial port, so its prompts and
# banner reach this script.
# In kiosk mode the wizard is what configures the machine, so nothing is
# posted here: a host written by this would leave the site holding an entry
# whose hardware.nix phase 1 never wrote, and the page then refuses to
# evaluate ("does not exist in Git repository").
if [ "$kiosk" = 0 ]; then
  api -X POST -H 'Content-Type: application/json' -d "$(jq -n --arg d "$disk_id" --arg m "$mac" --arg p "$profile" --argjson f "$features" '{host:"iso-test",profile:$p,systemDisk:$d,uplinks:(if $p == "server" then [$m] else [] end),settings:({"nixie.auth.admin.name":"admin","boot.kernelParams":["console=tty0","console=ttyS0,115200n8"]} + $f)}')" https://127.0.0.1:9443/api/config | grep -q ok
fi
echo "== phases 1 to 3: the site flake is evaluated and built on the ISO" | tee -a "$out/run.log"
start=$(date +%s)
if [ "$kiosk" = 1 ]; then
  # The same install, driven through the page on the screen instead. The
  # configuration posted above is replaced by what the driver types in.
  echo "== driving the wizard through the kiosk's own browser" | tee -a "$out/run.log"
  # What the debugger answers, before anything drives it: a hang-up here is
  # the browser refusing the connection, not the wizard misbehaving.
  for _ in $(seq 60); do curl -sS --max-time 5 http://127.0.0.1:9222/json/version >>"$out/run.log" 2>&1 && break; sleep 5; done
  tail -3 "$out/run.log"
  @kioskDriver@ "http://127.0.0.1:9222" "$out" "$security" 2>&1 | tee -a "$out/run.log"
  echo "install took $(( $(date +%s) - start )) s" | tee -a "$out/run.log"
  shot install-done
  api -X POST https://127.0.0.1:9443/api/reboot >/dev/null; stopped "$pid"
  # What follows the restart is the setup generation, which the HTTP path
  # drives to Finish and this one cannot: a machine the wizard configured
  # has no serial console for the script to read, because the HTTP path adds
  # console=ttyS0 to its settings and a person does not. So the first start
  # is photographed instead -- which is what someone whose machine will not
  # start has to send anyway, and this is the install they send it about.
  echo "== the first start after a kiosk install, in pictures" | tee -a "$out/run.log"
  pid=$(boot)
  at=0
  for n in 30 60 100 140 200 280; do
    sleep $((n - at)); at=$n
    shot "kiosk-restart-$n"
    # Blind, because there is nothing to read. The first start asks for the
    # passphrase whatever else is turned on: the TPM is not enrolled until
    # phase 6, which is after this. Twice, in case the first was early --
    # the box takes the second as a fresh attempt.
    { [ "$n" = 60 ] || [ "$n" = 100 ]; } && keys hunter2
  done
  kill "$pid" 2>/dev/null || true
  echo "test-iso: PASS, the kiosk drove a whole install (artifacts in $out)" | tee -a "$out/run.log"
  exit 0
else
phase 1
# The review step's check: the host evaluates the way phase 3 builds it.
api -X POST https://127.0.0.1:9443/api/check | tee "$out/check.json" | jq -e .ok >/dev/null
phase 2 && phase 3
echo "install took $(( $(date +%s) - start )) s" | tee -a "$out/run.log"
shot install-done
api -X POST https://127.0.0.1:9443/api/reboot >/dev/null; stopped "$pid"
fi

echo "== first boot: unlock, then the setup generation" | tee -a "$out/run.log"
mark; pid=$(boot)
unlock 80
sleep 20; shot setup-generation
pair
phase 4
if [ "$security" = secureboot ] || [ "$security" = hardened ]; then
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
if [ "$security" = tpm ] || [ "$security" = hardened ]; then
  echo "== reboot: the TPM and PIN open the outer layer, the code is shown" | tee -a "$out/run.log"
  api -X POST https://127.0.0.1:9443/api/reboot >/dev/null; stopped "$pid"
  mark; pid=$(boot)
  waitfor 'Attestation code' 300
  unlock
  fresh | grep -qE 'Please enter.*PIN|PIN:'
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
# The hardened setup asks for more than the others. What this VM can show
# is on its console: USB blocking started, the attestation code and the
# PIN prompt appeared at boot (waited for above). Memory encryption is a
# kernel parameter with nothing to say on a machine without an IOMMU, and
# the whole set is proven to build by tests/sites/wizard-server.nix.
if [ "$security" = hardened ]; then
  grep -qi 'usbguard' "$out/serial.log" || { echo "usbguard did not start" >&2; exit 1; }
  echo "hardened: USB blocking started, the attestation code and PIN prompt appeared" | tee -a "$out/run.log"
fi
sleep 15; shot finished
printf 'quit\n' | socat - UNIX-CONNECT:"$out/monitor.sock" >/dev/null 2>&1 || true
stopped "$pid"
echo "test-iso: PASS (artifacts in $out)" | tee -a "$out/run.log"
