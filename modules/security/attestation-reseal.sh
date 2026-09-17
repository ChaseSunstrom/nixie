# shellcheck shell=bash
# After an update, seal the attestation secret to the system that has just
# been unlocked -- but only one the firmware verified and this machine
# installed. @sealed@ is the ESP's record (attestation.nix).
booted=$(readlink -f /run/booted-system)
sealed=$(cat @sealed@ 2>/dev/null || true)
# Never sealed (setup does that), or sealed for this very system: a
# code that does not compute then means the chain changed without an
# update, which is for a person to look into.
[ -n "$sealed" ] && [ "$sealed" != "$booted" ] || exit 0
installed=""
for g in /nix/var/nix/profiles/system-*-link; do
  for s in "$g" "$g"/specialisation/*; do
    [ "$(readlink -f "$s")" != "$booted" ] || installed=1
  done
done
if [ -z "$installed" ] || ! bootctl status 2>/dev/null | grep -qE 'Secure Boot: *enabled'; then
  echo "not sealing: $booted is not a Secure Boot verified system this machine installed; run 'nixie reseal' if you trust it"
  exit 0
fi
tpm2-totp reseal -P "$(cat /var/lib/nixie/totp-recovery)" -p 4,7,8,9
printf '%s' "$booted" >@sealed@
echo "attestation sealed to $booted"
