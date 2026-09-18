# Boot the built ISO under QEMU with OVMF, a swtpm, a blank disk and
# user-mode networking (so the site is evaluated and built online, as on a
# real machine), drive the wizard over its HTTP API through the install,
# answer the unlock prompts on the serial console, and continue in the setup
# generation to Finish. Screenshots and the serial log land in
# tests/artifacts/.
#
#   --kiosk               drive the wizard through the browser on the
#                         machine's own screen, not over the HTTP API
#   --usb                 the image is a USB stick instead of a CD
#   --profile desktop     install a desktop: setup shows the wizard on its
#                         screen too, and Finish hands over to the greeter
#   --security plain      encryption only (default)
#   --security hardened   what the wizard's hardened setup turns on
#   --security tpm        and TPM with PIN, attestation, duress, to Finish
#   --security secureboot and Secure Boot, until the keys are staged: firmware
#                         enrolment then needs real hardware (VERIFICATION.md)
{
  pkgs,
  nixie-iso,
  nixie-iso-kiosk,
}:
let
  ovmf = (pkgs.OVMF.override { secureBoot = true; }).fd;
  # --kiosk drives the browser on the machine's own screen, over the
  # debugger the kiosk image opens on the loopback.
  py = pkgs.python3.withPackages (p: [ p.playwright ]);
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
  # The run itself is packages/test-iso/test-iso.sh.
  text = (import ../lib/template.nix pkgs.lib).fill ./test-iso/test-iso.sh {
    iso = nixie-iso;
    kioskIso = nixie-iso-kiosk;
    kioskDriver = "${py}/bin/python3 ${./test-iso/kiosk-wizard.py}";
    inherit ovmf;
  };
}
