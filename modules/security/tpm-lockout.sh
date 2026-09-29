# shellcheck shell=bash
# The TPM's dictionary-attack lockout, kept by this machine.
#
#   prepare [--new-auth]  phase 6 and `nixie security rebind`: a lockout
#                         password this machine knows, the tries raised, the
#                         count cleared. --new-auth replaces a known password.
#   check                 every start (nixie-tpm-check.service): how the outer
#                         layer was opened, into @state@, then the same
#                         upkeep as prepare when the password is known.
#
# A virtual TPM (libtpms: VirtualBox, QEMU's swtpm) starts with 3 tries and
# gives one back per 1000 seconds it runs. Three wrong PINs over any number of
# starts, the recovery key typed into the PIN prompt among them, and it
# refused the right PIN too, so only the recovery key opened the disk. 32
# tries and one back every two hours are what Windows sets; a start that got
# through forgives the count, because only the owner gets that far.
mode=${1:-check}
auth=/var/lib/nixie/tpm-lockout-auth
state=@state@
export TPM2TOOLS_TCTI=${TPM2TOOLS_TCTI:-device:/dev/tpmrm0}
maxTries=32
recoveryTime=7200
lockoutRecovery=86400

# One property of the TPM's current state, as a number.
prop() {
  local v
  v=$(tpm2_getcap properties-variable | awk -v k="$1:" '$1 == k { print $2; exit }')
  printf '%d' "${v:-0}"
}

# Clear the count and set the limits with the password this machine keeps.
upkeep() {
  local failed max
  failed=$(prop TPM2_PT_LOCKOUT_COUNTER)
  max=$(prop TPM2_PT_MAX_AUTH_FAIL)
  if [ "$max" != "$maxTries" ]; then
    tpm2_dictionarylockout --setup-parameters --max-tries="$maxTries" \
      --recovery-time="$recoveryTime" --lockout-recovery-time="$lockoutRecovery" -p "file:$auth" || return 1
    echo "TPM PIN tries set to $maxTries (was $max)"
  fi
  if [ "$failed" -gt 0 ]; then
    tpm2_dictionarylockout --clear-lockout -p "file:$auth" || return 1
    echo "TPM count of wrong PINs cleared (was $failed)"
  fi
}

case $mode in
  prepare)
    if [ "$(prop lockoutAuthSet)" = 0 ]; then
      # No password yet: the empty one works, once, to set ours. Asking with
      # a wrong one instead would lock the lockout hierarchy for a day.
      tpm2_dictionarylockout --clear-lockout
      new=$(openssl rand -hex 16) # 32 characters: one SHA-256 digest, the TPM's limit
      tpm2_changeauth -c lockout "$new"
      install -d -m 0700 "$(dirname "$auth")"
      (umask 077; echo "$new" >"$auth")
      echo "TPM lockout password set"
    elif [ ! -s "$auth" ]; then
      # A reinstall on the same TPM: the password went with the old disk (it
      # is in that install's header backup). The limits stay as they are.
      echo "this TPM has a lockout password from an earlier install; its PIN tries are left as they are" >&2
      exit 0
    elif [ "${2:-}" = --new-auth ]; then
      new=$(openssl rand -hex 16)
      tpm2_changeauth -c lockout -p "file:$auth" "$new"
      (umask 077; echo "$new" >"$auth")
      echo "TPM lockout password replaced"
    fi
    upkeep
    ;;
  check)
    outer=$(jq -r '.luks[]? | select(.name == "rpool-outer") | .device' /run/current-system/etc/nixie/layout.json)
    enrolled=false; opened=none; reason=""
    if [ -n "$outer" ] && cryptsetup luksDump "$outer" 2>/dev/null | grep -q systemd-tpm2; then
      enrolled=true; opened=tpm
      # systemd-cryptsetup's own words from the initrd, carried in this
      # start's journal: it names why the TPM refused before it asks for a
      # key instead.
      log=$(journalctl -b -q -o cat -u "$(systemd-escape --template=systemd-cryptsetup@.service rpool-outer)" 2>/dev/null || true)
      case $log in
        *"falling back to traditional unlocking"*)
          opened=recovery
          case $log in
            *"dictionary attack lock"*) reason=lockout ;;
            *"policy does not match"*) reason=changed ;;
            *"does not belong to this TPM"* | *"Failed to unseal"*) reason=forgot ;;
            *) reason=unknown ;;
          esac
          ;;
      esac
    fi
    managed=false; failed=0
    if [ -e /dev/tpmrm0 ]; then
      failed=$(prop TPM2_PT_LOCKOUT_COUNTER)
      if [ -s "$auth" ] && [ "$(prop lockoutAuthSet)" = 1 ] && upkeep; then managed=true; fi
    fi
    install -d -m 0755 "$(dirname "$state")"
    jq -n --argjson enrolled "$enrolled" --arg opened "$opened" --arg reason "$reason" \
      --argjson failed "$failed" --argjson managed "$managed" --arg checked "$(date -Is)" \
      '{enrolled: $enrolled, opened: $opened, reason: $reason, failedAtStart: $failed, managed: $managed, rebound: false, checked: $checked}' >"$state.new"
    mv "$state.new" "$state"
    ;;
  *)
    echo "usage: nixie-tpm-lockout prepare [--new-auth] | check" >&2
    exit 2
    ;;
esac
