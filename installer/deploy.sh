# shellcheck shell=bash
# nixie-deploy: headless installer. Same phases, same markers, over SSH.
set -euo pipefail
site=""; host=""; target=""; local=0; continue=0; yes=0
while [ $# -gt 0 ]; do
  case "$1" in
    --site) site=$2; shift 2 ;;
    --host) host=$2; shift 2 ;;
    --local) local=1; shift ;;
    --continue) continue=1; shift ;;
    --yes) yes=1; shift ;;
    -h|--help) echo "usage: nixie-deploy --site <path> --host <name> [--yes] <user@target> | --local | --continue"; exit 0 ;;
    *) target=$1; shift ;;
  esac
done

# The web installer's colours (Graphite); a console with sixteen colours gets
# the nearest ones.
export GUM_CHOOSE_CURSOR_FOREGROUND="#7ebae4" GUM_CHOOSE_SELECTED_FOREGROUND="#7ebae4" GUM_CHOOSE_HEADER_FOREGROUND="#9a9ea6" \
  GUM_INPUT_CURSOR_FOREGROUND="#7ebae4" GUM_INPUT_PROMPT_FOREGROUND="#7ebae4" GUM_INPUT_PLACEHOLDER_FOREGROUND="#9a9ea6" \
  GUM_CONFIRM_PROMPT_FOREGROUND="#eceae5" GUM_CONFIRM_SELECTED_BACKGROUND="#5277c3" GUM_CONFIRM_UNSELECTED_BACKGROUND="#31363d"
say() { gum style --foreground "#7ebae4" "$*"; }
ask() { gum input --placeholder "$1" "${@:2}"; }
# Without the newline gum ends its output with: a key file keeps every byte,
# and the passphrase typed at boot has no newline in it.
secret() { gum input --password --placeholder "$1" | tr -d '\n'; }
banner() { [ -s /var/lib/nixie/setup/banner.txt ] && gum style --border rounded --border-foreground "#383e46" --padding "0 1" "$(cat /var/lib/nixie/setup/banner.txt)" || true; }

# ---------------------------------------------------------------- local mode
if [ "$local" = 1 ]; then
  export NIXIE_SITE=${site:-/etc/nixie/site} NIXIE_SETUP_DIR=/var/lib/nixie/setup NIXIE_KEYS=/run/nixie/keys
  mkdir -p /run/nixie/keys "$NIXIE_SETUP_DIR"; chmod 700 /run/nixie/keys
  while true; do
    clear; gum style --bold "Nixie installer (terminal)"; banner
    choice=$(gum choose "Install this machine" "Enable SSH for headless install (set root password)" "Shell" "Reboot")
    case "$choice" in
      "Enable SSH"*) passwd root; say "SSH is on; from another machine: nix run nixie#deploy -- --site <site> --host <name> root@<this address>"; gum confirm "Back to menu?" || true ;;
      Shell) bash -l || true ;;
      Reboot) systemctl reboot ;;
      "Install this machine")
        hw=$(nixie-discover)
        profile=$(gum choose --header "Profile" server desktop)
        # HyDE comes from GitHub while installing, so it is offered only online.
        hyde=false
        if [ "$profile" = desktop ] && timeout 3 bash -c '</dev/tcp/github.com/443' 2>/dev/null; then
          [ "$(gum choose --header "Desktop" "Nixie desktop" "HyDE (its own look; needs the network while installing)")" = "Nixie desktop" ] || hyde=true
        fi
        host=$(ask "host name" --value "${host:-nixie}")
        disk=$(jq -r '.disks[] | (.id // .path) + "  " + ((.size/1e9|floor|tostring) + " GB  ") + (.model // "")' <<<"$hw" | gum choose --header "System disk (wiped)" | awk '{print $1}')
        data=$(jq -r '.disks[] | (.id // .path)' <<<"$hw" | grep -v "^$disk$" | { echo none; cat; } | gum choose --header "Data disk (optional)")
        [ "$data" = none ] && data=""
        uplinks='[]'; mode=unmanaged-lan
        # Only a server runs guests, so only a server has a bridge to join.
        if [ "$profile" = server ]; then
          uplinks=$(jq -r '.nics[].mac' <<<"$hw" | gum choose --no-limit --header "Ports joining the bridge" | jq -R . | jq -sc .)
          mode=$(gum choose --header "Bridge mode" unmanaged-lan managed-nat)
        fi
        # The hardened setup is the web wizard's: every feature on, each one
        # still asked for what it needs. Kernel lockdown stays out (it builds
        # the kernel from source), and so does unlocking over SSH.
        hard=false
        [ "$(gum choose --header "How much security" "Standard" "Hardened")" = Hardened ] && hard=true
        enc=$(if [ "$hard" = true ]; then echo true; else gum confirm "Encrypt the disk (passphrase every boot)?" && echo true || echo false; fi)
        tpm=false; att=false; sb=false; dur=false; ru=false; usb=false; memenc=false
        if [ "$enc" = true ]; then
          secret "Disk passphrase" >/run/nixie/keys/passphrase
          if [ "$hard" = true ]; then
            sb=true; dur=true; usb=true; memenc=true
            [ "$(jq -r .tpm <<<"$hw")" = true ] && { tpm=true; att=true; }
            [ "$tpm" = true ] && secret "TPM PIN" >/run/nixie/keys/pin
            secret "Duress passphrase (typed at boot, it destroys the disk)" >/run/nixie/keys/duress
            say "Hardened: Secure Boot, a duress passphrase, USB device blocking and memory encryption are on${tpm:+, with the TPM and an attestation code}."
          else
            if [ "$(jq -r .tpm <<<"$hw")" = true ]; then
              tpm=$(gum confirm "Bind to the TPM with a PIN?" && echo true || echo false)
              [ "$tpm" = true ] && secret "TPM PIN" >/run/nixie/keys/pin
              att=$(gum confirm "Attestation code before the passphrase prompt?" && echo true || echo false)
            fi
            sb=$(gum confirm "Secure Boot with your own keys?" && echo true || echo false)
            dur=$(gum confirm "Duress passphrase (wipes the disk if typed)?" && echo true || echo false)
            [ "$dur" = true ] && secret "Duress passphrase" >/run/nixie/keys/duress
            ru=$(gum confirm "Remote unlock over SSH at boot?" && echo true || echo false)
          fi
        fi
        admin=$(ask "administrator user name" --value admin)
        # The system's own accounts cannot be the administrator (modules/auth.nix).
        until [[ $admin =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && [ "$admin" != root ] && [ "$admin" != nobody ]; do
          admin=$(ask "administrator user name (lowercase, not root or nobody)" --value admin)
        done
        secret "administrator password" >/run/nixie/keys/admin-password
        keys=$(ask "SSH public key (optional, one)")
        # Remote unlock is an SSH login; without a key the system cannot be built.
        while [ "$ru" = true ] && [ -z "$keys" ]; do
          keys=$(ask "SSH public key (needed: remote unlock is on)")
        done
        # The same JSON the web wizard posts to /api/config, written by the same code.
        settings=$(jq -n --arg admin "$admin" --arg key "$keys" --arg mode "$mode" --argjson hyde "$hyde" \
          --argjson enc "$enc" --argjson tpm "$tpm" --argjson att "$att" --argjson sb "$sb" --argjson dur "$dur" --argjson ru "$ru" \
          --argjson usb "$usb" --argjson memenc "$memenc" \
          '{"nixie.auth.admin.name": $admin, "nixie.auth.sshKeys": ([$key] | map(select(. != ""))),
            "nixie.security.encryption.enable": $enc, "nixie.security.tpm.enable": $tpm,
            "nixie.security.attestation.enable": $att, "nixie.security.secureBoot.enable": $sb,
            "nixie.security.duress.enable": $dur, "nixie.security.remoteUnlock.enable": $ru,
            "nixie.network.bridge.mode": $mode}
           + (if $hyde then {"nixie.desktop.hyde.enable": true} else {} end)
           + (if $usb then {"nixie.security.hardening.usbguard.enable": true} else {} end)
           + (if $memenc then {"nixie.security.hardening.memoryEncryption.enable": true,
                               "nixie.auth.ssh.passwordLogin": false} else {} end)')
        jq -n --arg h "$host" --arg p "$profile" --arg d "$disk" --arg dd "$data" --argjson u "$uplinks" --arg g "$(jq -r .gpu <<<"$hw")" --argjson t "$(jq .tpm <<<"$hw")" --argjson s "$settings" \
          '{host:$h, profile:$p, systemDisk:$d, dataDisk:(if $dd=="" then null else $dd end), uplinks:$u, gpu:$g, tpm:$t, settings:$s}' \
          | nixie-setup --configure --front-end terminal --site "$NIXIE_SITE" --state-dir "$NIXIE_SETUP_DIR"
        # A failed phase must leave its reason on screen: the unit restarts
        # the wizard, which clears it.
        if ! nixie-phase 1; then
          say "Looking at the hardware failed; the lines above say why."
          gum confirm "Back to menu?" || true
          continue
        fi
        # The web wizard's Review: every file can be changed, and nothing is
        # erased until the host evaluates the way phase 3 will build it.
        ready=false
        while [ "$ready" = false ]; do
          case "$(gum choose --header "Ready to erase $disk and install $host" "Install" "Edit the configuration first" "Back to the menu")" in
            Edit*) (cd "$NIXIE_SITE" && "${EDITOR:-nano}" site.nix "hosts/$host/configuration.nix" "hosts/$host/hardware.nix" flake.nix) ;;
            Back*) break ;;
            Install)
              say "Checking the configuration…"
              if (cd "$NIXIE_SITE" && git add -A && nix eval --no-eval-cache --raw ".#nixosConfigurations.$host.config.system.build.toplevel.drvPath" >/dev/null); then
                ready=true
              else
                say "The configuration does not evaluate; the lines above say where. Edit it and choose Install again."
              fi ;;
          esac
        done
        [ "$ready" = true ] || continue
        if ! { nixie-phase 2 && nixie-phase 3; }; then
          say "The install stopped; the lines above say why. Choosing Install again skips the phases that finished."
          gum confirm "Back to menu?" || true
          continue
        fi
        say "Installed. Reboot to continue setup on the new system."
        gum confirm "Reboot now?" && systemctl reboot
        ;;
    esac
  done
fi

# ------------------------------------------------------------- continue mode
# The setup generation's terminal front end: phases 4 to 8 and Finish, run by
# themselves as on the web page, stopping only for the passphrase and PIN,
# the Secure Boot restart, or a phase that failed.
if [ "$continue" = 1 ]; then
  export NIXIE_SITE=/etc/nixie/site NIXIE_SETUP_DIR=/var/lib/nixie/setup NIXIE_KEYS=/run/nixie/keys NIXIE_TOPLEVEL=/run/current-system
  mkdir -p "$NIXIE_KEYS"; chmod 700 "$NIXIE_KEYS"
  feature() { [ "$(jq -r ".features.$1 // false" /run/current-system/etc/nixie/layout.json 2>/dev/null)" = true ]; }
  titles=([4]="First start" [5]="Secure Boot" [6]="Disk unlock" [7]="Checks" [8]="Apply the site")
  # A phase this machine does not use records itself without being shown.
  used() { case "$1" in 5) feature secureBoot ;; 6) feature encryption ;; *) true ;; esac; }
  checklist() {
    clear; gum style --bold "Setting up $(jq -r .host "$NIXIE_SETUP_DIR/state.json" 2>/dev/null)"
    for n in 4 5 6 7 8; do
      used "$n" || continue
      if [ -e "$NIXIE_SETUP_DIR/$n.done" ]; then gum style --foreground "#8fd6a8" "  ✓ ${titles[$n]}"
      elif [ "$n" = "${1:-}" ]; then gum style --foreground "#7ebae4" --bold "  ▸ ${titles[$n]}"
      else gum style --faint "    ${titles[$n]}"; fi
    done
    echo
  }
  # Anything but carrying on: a shell or a restart, then back to the list.
  menu() {
    case "$(gum choose "$@" "Shell" "Restart")" in
      Shell) bash -l || true ;;
      Restart|"Restart now") systemctl reboot; exit 0 ;;
      "Restart into firmware settings") systemctl reboot --firmware-setup; exit 0 ;;
    esac
  }
  while true; do
    next=""; for n in 4 5 6 7 8; do [ -e "$NIXIE_SETUP_DIR/$n.done" ] || { next=$n; break; }; done
    checklist "$next"
    if [ -z "$next" ]; then
      [ -s "$NIXIE_KEYS/recovery-key" ] && gum style --border rounded --padding "0 1" "Recovery key, shown once (write it down): $(cat "$NIXIE_KEYS/recovery-key")"
      [ -s "$NIXIE_KEYS/attestation-qr" ] && cat "$NIXIE_KEYS/attestation-qr"
      feature encryption && say "The header backup is $NIXIE_SETUP_DIR/header-backup.tar.age; copy it off this machine."
      case "$(gum choose "Finish: switch to the normal system and remove setup" "Shell" "Restart")" in
        Shell) bash -l || true; continue ;;
        Restart) systemctl reboot; exit 0 ;;
      esac
      # The switch stops this wizard with the rest of the setup generation,
      # so Finish runs as a unit of its own, as it does from the web page.
      systemd-run --unit=nixie-finish --collect -p StandardOutput=journal+console -p StandardError=journal+console "$(command -v nixie-finish)"
      journalctl -fu nixie-finish -o cat & follow=$!
      while systemctl -q is-active nixie-finish; do sleep 1; done
      kill "$follow" 2>/dev/null || true
      rm -f "$NIXIE_KEYS"/*
      # The switch usually ends this wizard first; if not, the marker says how it went.
      [ ! -e "$NIXIE_SETUP_DIR/finished" ] || { say "Setup finished."; exit 0; }
      say "Finish stopped; the lines above say why. Fix the site in $NIXIE_SITE and choose Finish again."
      menu "Try again"
      continue
    fi
    if [ "$next" = 6 ] && feature tpm; then
      say "Bind the disk to this machine's TPM with a PIN."
      secret "Disk passphrase" >"$NIXIE_KEYS/passphrase"
      secret "TPM PIN, asked at every start" >"$NIXIE_KEYS/pin"
    fi
    rc=0; nixie-phase "$next" || rc=$?
    case "$rc" in
      0) ;;
      10) say "The Secure Boot keys are ready. The firmware enrols them while the machine restarts; leave Secure Boot off until setup says to turn it on."
          menu "Restart now" ;;
      # The phase printed the steps (Custom mode, reset the keys, Secure Boot off).
      11) say "Secure Boot needs Setup Mode first: follow the steps above, and leave Secure Boot off until setup asks. \"Access Denied\" at boot means it was turned on too early; turning it off again loses nothing."
          menu "Restart into firmware settings" "Check again" ;;
      12) say "This machine's keys are in the firmware now: turn Secure Boot on in the firmware settings, save and exit."
          menu "Restart into firmware settings" "Check again" ;;
      *) say "${titles[$next]} stopped; the lines above say why."
         menu "Try again" ;;
    esac
  done
fi

# --------------------------------------------------------------- remote mode
[ -n "$site" ] && [ -n "$host" ] && [ -n "$target" ] || { echo "usage: nixie-deploy --site <path> --host <name> [--yes] <user@target>" >&2; exit 2; }
ssh_opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
r() { ssh "${ssh_opts[@]}" "$target" "$@"; }

gum style --bold "Nixie headless install: $host -> $target"
cat <<'MSG'
Before continuing, on the target's firmware:
  - UEFI boot with CSM off
  - TPM enabled and cleared
  - Secure Boot off with the keys cleared (Setup Mode); also needed to kexec under lockdown
  - disks not listed in the site unplugged
MSG
[ "$yes" = 1 ] || gum confirm "Confirmed?" || exit 1

if r test -e /etc/nixie-iso; then
  say "target runs the Nixie ISO; no kexec needed"
else
  say "kexec into the installer"
  nixos-anywhere --phases kexec "$target"
  # After kexec the target is a plain NixOS installer; give it the phase engine.
  nix copy --to "ssh://$target" "$(dirname "$(dirname "$(command -v nixie-phase)")")"
fi

say "building $host from $site"
toplevel=$(nix build --no-link --print-out-paths "$site#nixosConfigurations.$host.config.system.build.toplevel")
disko=$(nix build --no-link --print-out-paths "$site#nixosConfigurations.$host.config.system.build.diskoScript")
nix copy --to "ssh://$target" "$toplevel" "$disko"
rsync -a --delete "$site/" "$target:/tmp/nixie-site/"
r mkdir -p /var/lib/nixie/setup /run/nixie/keys "&&" chmod 700 /run/nixie/keys

hw=$(r nixie-discover 2>/dev/null || echo '{}')
disk=$(nix eval --raw "$site#nixosConfigurations.$host.config.nixie.disks.system")
data=$(nix eval --raw "$site#nixosConfigurations.$host.config.nixie.disks.data" 2>/dev/null || echo null)
enc=$(nix eval "$site#nixosConfigurations.$host.config.nixie.security.encryption.enable")
tpm=$(nix eval "$site#nixosConfigurations.$host.config.nixie.security.tpm.enable")
dur=$(nix eval "$site#nixosConfigurations.$host.config.nixie.security.duress.enable")
sb=$(nix eval "$site#nixosConfigurations.$host.config.nixie.security.secureBoot.enable")
jq -n --arg h "$host" --arg d "$disk" --arg dd "$data" --argjson sb "$sb" --argjson hw "$hw" \
  '{host:$h, profile:"server", systemDisk:$d, dataDisk:(if $dd=="null" then null else $dd end), uplinks:[], gpu:($hw.gpu // "none"), tpm:($hw.tpm // false), options:{secureBoot:$sb}}' \
  | r "cat >/var/lib/nixie/setup/state.json"
if [ "$enc" = true ]; then secret "disk passphrase" | r "cat >/run/nixie/keys/passphrase"; fi
if [ "$tpm" = true ]; then secret "TPM PIN" | r "cat >/run/nixie/keys/pin"; fi
if [ "$dur" = true ]; then secret "duress passphrase" | r "cat >/run/nixie/keys/duress"; fi
if [ -s "$site/secrets/$host.yaml" ]; then
  say "existing secrets found; the host's age key must be provided to reuse them"
  keyfile=$(ask "path to the host's age key (empty: generate a new identity)")
  [ -n "$keyfile" ] && scp "${ssh_opts[@]}" "$keyfile" "$target:/run/nixie/keys/age.key"
else
  secret "administrator password" | r "cat >/run/nixie/keys/admin-password"
fi
env="NIXIE_SITE=/tmp/nixie-site NIXIE_TOPLEVEL=$toplevel NIXIE_DISKO=$disko"
r "$env nixie-phase 1 && $env nixie-phase 2 && $env nixie-phase 3"
say "pulling the generated files back into the site"
rsync -a "$target:/tmp/nixie-site/hosts/" "$site/hosts/"
rsync -a "$target:/tmp/nixie-site/secrets/" "$site/secrets/"
rsync -a "$target:/tmp/nixie-site/.sops.yaml" "$site/.sops.yaml"
say "installed; rebooting the target"
r systemctl reboot || true
say "When it is back (unlock it over SSH on port 2222 if remote unlock is on), continue with:"
echo "  ssh $target nixie-phase 4; nixie-phase 5; ... nixie-phase 8; nixie-finish"
