# shellcheck shell=bash
# The initrd gave up, and the person is looking at a prompt they cannot use:
# the root account is locked, so sulogin offers nothing, and a signed boot
# chain has no editable kernel command line to add a debug parameter to
# either. Without this they have a screen that says only "emergency mode".
#
# The splash is covering the console, so it goes first; the disk is still
# locked and nothing has been written, which is worth saying to someone
# watching a new machine refuse to start.
[ -z "@plymouth@" ] || "@plymouth@" quit 2>/dev/null || true
report() {
  echo
  echo "Nixie could not finish starting. What failed:"
  echo
  systemctl --failed --no-legend --plain 2>/dev/null || echo "  (systemd listed nothing)"
  echo
  echo "The disk is still locked and nothing has been changed."
  echo "Take a photo of this screen: it says which part gave up."
  echo "Starting again and holding Space offers the previous system."
  echo
}
# On the screen, which is /dev/console: the last console= on the command
# line, so on a machine with a serial console this is not it.
report || true
# And into the kernel log at error level, which is what reaches a serial
# console and the journal: this machine boots quiet, with the console log
# level at 3, so anything milder than an error is never shown.
report 2>/dev/null | while IFS= read -r line; do
  [ -z "$line" ] || echo "<3>nixie-emergency: $line" >/dev/kmsg 2>/dev/null || true
done
