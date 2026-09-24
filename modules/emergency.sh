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
  systemctl --failed --no-legend --plain 2>/dev/null || true
  # A start that is stuck rather than failed lists nothing above: what names
  # it is the job that never finished -- a disk that never appeared, a
  # device waited for until its timeout.
  jobs=$(systemctl list-jobs --no-legend --plain 2>/dev/null || true)
  if [ -n "$jobs" ]; then
    echo "Still waiting for:"
    printf '%s\n' "$jobs"
    echo
  fi
  echo "The disk is still locked and nothing has been changed."
  # The outer layer is the TPM's: when it refuses, only the recovery key
  # setup showed opens it, not the disk passphrase.
  if [[ $(systemctl --failed --no-legend --plain 2>/dev/null) == *x2douter* ]]; then
    echo "The outer layer did not open. If the PIN was not accepted, the TPM refused:"
    echo "start again and type the recovery key from setup at the Recovery key prompt,"
    echo "then run 'nixie security reenroll' to bind the TPM again."
  fi
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
