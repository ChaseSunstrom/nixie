# shellcheck shell=bash
# nixie-deploy: headless installer. Same phases, same markers, over SSH.
set -euo pipefail
site=""; host=""; target=""; local=0; yes=0
while [ $# -gt 0 ]; do
  case "$1" in
    --site) site=$2; shift 2 ;;
    --host) host=$2; shift 2 ;;
    --local) local=1; shift ;;
    --yes) yes=1; shift ;;
    -h|--help) echo "usage: nixie-deploy --site <path> --host <name> [--yes] <user@target> | --local"; exit 0 ;;
    *) target=$1; shift ;;
  esac
done

say() { gum style --foreground 4 "$*"; }
ask() { gum input --placeholder "$1" "${@:2}"; }
secret() { gum input --password --placeholder "$1"; }
banner() { [ -s /var/lib/nixie/setup/banner.txt ] && gum style --border rounded --padding "0 1" "$(cat /var/lib/nixie/setup/banner.txt)" || true; }

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
        enc=$(gum confirm "Encrypt the disk (passphrase every boot)?" && echo true || echo false)
        tpm=false; att=false; sb=false; dur=false; ru=false
        if [ "$enc" = true ]; then
          secret "Disk passphrase" >/run/nixie/keys/passphrase
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
        admin=$(ask "administrator user name" --value admin)
        secret "administrator password" >/run/nixie/keys/admin-password
        keys=$(ask "SSH public key (optional, one)")
        # The same JSON the web wizard posts to /api/config, written by the same code.
        settings=$(jq -n --arg admin "$admin" --arg key "$keys" --arg mode "$mode" \
          --argjson enc "$enc" --argjson tpm "$tpm" --argjson att "$att" --argjson sb "$sb" --argjson dur "$dur" --argjson ru "$ru" \
          '{"nixie.auth.admin.name": $admin, "nixie.auth.sshKeys": ([$key] | map(select(. != ""))),
            "nixie.security.encryption.enable": $enc, "nixie.security.tpm.enable": $tpm,
            "nixie.security.attestation.enable": $att, "nixie.security.secureBoot.enable": $sb,
            "nixie.security.duress.enable": $dur, "nixie.security.remoteUnlock.enable": $ru,
            "nixie.network.bridge.mode": $mode}')
        jq -n --arg h "$host" --arg p "$profile" --arg d "$disk" --arg dd "$data" --argjson u "$uplinks" --arg g "$(jq -r .gpu <<<"$hw")" --argjson t "$(jq .tpm <<<"$hw")" --argjson s "$settings" \
          '{host:$h, profile:$p, systemDisk:$d, dataDisk:(if $dd=="" then null else $dd end), uplinks:$u, gpu:$g, tpm:$t, settings:$s}' \
          | nixie-setup --configure --site "$NIXIE_SITE" --state-dir "$NIXIE_SETUP_DIR"
        gum confirm "Write hardware.nix, keys and secrets, then wipe $disk and install?" || continue
        # A failed phase must leave its reason on screen: the unit restarts
        # the wizard, which clears it.
        if ! { nixie-phase 1 && nixie-phase 2 && nixie-phase 3; }; then
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
