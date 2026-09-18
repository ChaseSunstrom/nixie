# The steps that touch guests already skip a host without their
# configuration; these two commands name a guest outright.
guests=@guests@
need_guests() { [ "$guests" = 1 ] || { echo "nixie: this host runs no guests (nixie.incus.enable is off)" >&2; exit 2; }; }
layout() { jq -r "$1" /run/current-system/etc/nixie/layout.json; }
feature() { [ "$(layout ".features.$1")" = true ]; }
site=${NIXIE_SITE:-/etc/nixie/site}
# Calling itself, from a unit whose PATH has no system profile as well.
self=${BASH_SOURCE[0]}
say() { printf '%-14s %s\n' "$1" "$2"; }

host=$(uname -n) # coreutils: a transient unit's PATH has no hostname(1)
# nixie.site.repo keeps a copy of the site: `nixie apply` pulls from it,
# commits hand edits, and pushes what it applied, with the host's own key.
sitekey=/var/lib/nixie/site-key
[ ! -e "$sitekey" ] || export GIT_SSH_COMMAND="ssh -i $sitekey -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
siterepo=$(jq -r '.repo // empty' /run/current-system/etc/nixie/site.json 2>/dev/null || true)
siteref=$(jq -r '.ref // "main"' /run/current-system/etc/nixie/site.json 2>/dev/null || echo main)
siterev=$(jq -r '.rev // empty' /run/current-system/etc/nixie/site.json 2>/dev/null || true)
updatemode=$(jq -r '.updates.mode // "off"' /run/current-system/etc/nixie/site.json 2>/dev/null || echo off)
updatewithin=$(jq -r '.updates.confirmWithin // ""' /run/current-system/etc/nixie/site.json 2>/dev/null || true)
push_site() {
  { [ -d "$site/.git" ] && git -C "$site" remote get-url origin >/dev/null 2>&1; } || return 0
  git -C "$site" push -q origin "HEAD:$siteref" \
    || echo "nixie: applied, but the site was not pushed to $(git -C "$site" remote get-url origin); the remote needs the key 'nixie site key' prints" >&2
}
cmd=${1:-help}; shift || true
# One screen, grouped by what a person is doing; the old one-line usage
# wrapped into a wall of pipes and brackets.
usage() {
  h() { if [ -t 1 ]; then printf '\n\033[1m%s\033[0m\n' "$1"; else printf '\n%s\n' "$1"; fi; }
  c() { printf '  %-50s %s\n' "$1" "$2"; }
  echo "nixie: this host, from its site in $site"
  h "Everyday"
  c "apply [--yes]" "commit site edits, switch, update guests, push the site"
  c "apply --confirm-within 10m | --confirm" "apply, and undo it unless confirmed in time"
  c "doctor" "boot security, keys, guests, backups, disk space"
  h "Going back"
  c "rollback [--list | --json]" "the previous system now, or list what there is"
  c "rollback --generation N | --boot-previous" "a given generation now, or the previous at next boot"
  if [ "$guests" = 1 ]; then c "rollback guest <name> [--snapshot s]" "a guest's disk from a snapshot"; fi
  c "rollback data <name> [--snapshot s] [--in-place]" "a state directory from a ZFS snapshot"
  h "Data"
  c "fetch" "fill cache/ from data.nix"
  c "backup now | list | verify | kit <file>" "back up, list, check, or write the disaster kit"
  c "restore <snapshot> [--path p] [--to dir]" "put state/ (or one path) back, or beside it"
  if [ "$guests" = 1 ]; then
    h "Guests"
    c "export <instance>" "a guests.nix entry for a scratch instance"
  fi
  h "Security and hardware"
  c "reseal" "reseal attestation to this boot chain"
  c "security reenroll" "Secure Boot, TPM, recovery key again, after a board or firmware change"
  c "security add-key" "enrol another security key (FIDO2) for the disk"
  c "secure-boot [--sign]" "what the firmware holds and what is signed, when a start says \"Access Denied\""
  c "disk open [<partition>] [--mount dir] [--write]" "open another Nixie disk with its keys, read-only unless --write"
  c "disk close" "unmount and lock what disk open opened"
  c "usb [--json] | usb allow <vendor:product>" "blocked USB devices, or allow one"
  c "hardware scan | refresh | add-disk <by-id>" "compare with hardware.nix, rewrite it, add a disk"
  h "Site"
  c "site key" "the key a site repository needs to receive pushes"
  if command -v nixie-menu >/dev/null; then
    h "Desktop"
    c "menu" "finish, wallpaper, packages, update, keybinds"
  fi
}
case "$cmd" in
  apply)
    yes=0; skip_host=0; within=""; confirm=0
    while [ $# -gt 0 ]; do case "$1" in --yes|-y) yes=1 ;; --skip-host) skip_host=1 ;; --confirm-within) within=$2; shift ;; --confirm) confirm=1 ;; esac; shift; done
    if [ "$confirm" = 1 ]; then
      systemctl stop nixie-apply-confirm.timer 2>/dev/null || true
      rm -f /run/nixie/apply-pending.json; echo "apply confirmed; automatic rollback cancelled"; exit 0
    fi
    prof=/nix/var/nix/profiles/system
    # No profile yet (a test VM, a hand-installed host): no previous generation.
    prev_gen=$( { readlink "$prof" 2>/dev/null || true; } | sed -n 's/.*system-\([0-9]*\)-link/\1/p')
    touched=""
    if [ "$skip_host" = 0 ]; then
      if [ -n "$siterepo" ] && [ -d "$site/.git" ] && ! git -C "$site" remote get-url origin >/dev/null 2>&1; then
        git -C "$site" remote add origin "$siterepo"
      fi
      # Hand edits become a commit before anything is built, so every
      # generation's label names the commit it came from.
      if [ -d "$site/.git" ] && [ -n "$(git -C "$site" status --porcelain)" ]; then
        git -C "$site" add -A
        changed=$(git -C "$site" diff --cached --name-only | head -5 | paste -sd ' ')
        git -C "$site" -c user.name="nixie on $host" -c user.email="nixie@$host" commit -qm "apply on $host: $changed"
      fi
      # A remote that has no branch yet gets its first push after the apply.
      if [ -n "$(git -C "$site" remote 2>/dev/null)" ] && git -C "$site" ls-remote --exit-code --heads origin "$siteref" >/dev/null 2>&1; then
        git -C "$site" pull --ff-only origin "$siteref" || echo "site pull failed; applying the checkout as is" >&2
      fi
      # Refuse the one change that needs a reinstall before touching anything.
      # A prebuilt system answers from its own layout, so no evaluation (and
      # no network) is needed on the host.
      if [ -n "${NIXIE_TOPLEVEL:-}" ]; then want=$(jq -r .features.encryption "$NIXIE_TOPLEVEL/etc/nixie/layout.json")
      # --json: --raw refuses a boolean ("cannot coerce a Boolean to a string").
      else want=$(nix eval --json "$site#nixosConfigurations.$host.config.nixie.security.encryption.enable"); fi
      if [ "$want" != "$(layout .features.encryption)" ]; then
        echo "nixie apply: nixie.security.encryption.enable cannot be changed on an installed system; reinstall from the ISO to change it." >&2
        exit 3
      fi
      # Local history first: ZFS snapshots of state/ (kept: last five).
      label="$(date +%Y%m%d-%H%M%S)-$(git -C "$site" rev-parse --short HEAD 2>/dev/null || echo nosite)"
      if command -v nixie-snapshot >/dev/null; then nixie-snapshot pre-apply "$label"; fi
      # Step 1: the host, so every derived piece exists before a guest has an interface.
      # A prebuilt system (deploy, tests) is switched to directly.
      # Status 4 is "switched, but some units did not start". A user's own
      # units missing their reload (a login ending mid-switch did it) must
      # not leave the guests unapplied; a failed system unit still stops here.
      switched() {
        rc=0; "$@" || rc=$?
        if [ "$rc" = 4 ] && [ -z "$(systemctl --failed --no-legend --plain)" ]; then
          echo "nixie apply: the switch reported units that did not start, but no system unit failed; continuing" >&2; rc=0
        fi
        return "$rc"
      }
      if [ -n "${NIXIE_TOPLEVEL:-}" ]; then
        nix-env --profile "$prof" --set "$NIXIE_TOPLEVEL"
        switched "$NIXIE_TOPLEVEL/bin/switch-to-configuration" switch
      else
        switched nixos-rebuild switch --flake "$site#$host"
      fi
    fi
    : "${label:=$(date +%Y%m%d-%H%M%S)}"
    [ -e /run/current-system/etc/nixie/tofu/config.tf.json ] || { echo "no guests to manage on this host"; push_site; exit 0; }
    # Step 2: NixOS guest images, built with the host, imported by alias.
    # Two guests whose configurations build the same image share one store
    # path, and importing that image twice fails ("Image with same
    # fingerprint already exists"), so the second one only gains an alias.
    declare -A imported=()
    while IFS=$'\t' read -r name alias path; do
      [ -z "$path" ] || [ "$path" = null ] && continue
      if incus image alias list -f csv | cut -d, -f1 | grep -qx "$alias"; then continue; fi
      if [ -n "${imported[$path]:-}" ]; then
        echo "image for $name is the one already imported; adding the alias $alias"
        incus image alias create "$alias" "${imported[$path]}"
      else
        echo "importing image for $name as $alias"
        incus image import "$path/metadata.tar.xz" "$path/rootfs.tar.xz" --alias "$alias"
        imported[$path]=$(incus image info "$alias" | sed -n 's/^Fingerprint: *//p' | head -1)
      fi
    done < <(jq -r '.declared | to_entries[] | [.key, .value.image, .value.imagePath] | @tsv' /run/current-system/etc/nixie/guests.json)
    # Step 3: instances from the generated tofu configuration. Scratch
    # instances are not in the state, so they are never touched.
    mkdir -p /var/lib/nixie/tofu && cd /var/lib/nixie/tofu
    cp -f /run/current-system/etc/nixie/tofu/config.tf.json config.tf.json
    tofu init -input=false >/dev/null
    set +e; tofu plan -input=false -detailed-exitcode -out=plan.bin; prc=$?; set -e
    [ "$prc" != 1 ] || exit 1
    if [ "$prc" = 2 ]; then
      # The plan changes instances: snapshot every declared one that exists
      # before tofu touches it, keeping the last five per guest.
      for g in $(jq -r '.declared | keys[]' /run/current-system/etc/nixie/guests.json); do
        incus info "$g" >/dev/null 2>&1 || continue
        incus snapshot create "$g" "pre-apply-$label"
        touched="$touched $g"
        incus snapshot list "$g" -f csv -c n | grep '^pre-apply-' | sort | head -n -5 | while read -r sn; do incus snapshot delete "$g" "$sn"; done
      done
    fi
    if [ "$yes" = 1 ]; then tofu apply -input=false plan.bin; else
      read -r -p "apply this plan? [y/N] " ans; [ "$ans" = y ] && tofu apply -input=false plan.bin
    fi
    # --confirm-within: unless `nixie apply --confirm` arrives in time, the
    # host goes back to the generation before this apply and the touched
    # guests to their pre-apply snapshots.
    if [ -n "$within" ]; then
      mkdir -p /run/nixie
      jq -n --arg prev "${prev_gen:-}" --arg label "$label" --arg guests "$touched" \
        '{prev: $prev, label: $label, guests: ($guests | split(" ") | map(select(. != "")))}' >/run/nixie/apply-pending.json
      # By path: a transient unit's PATH has no system profile, and this
      # apply may itself be running from one (nixie update --auto).
      systemd-run --quiet --unit=nixie-apply-confirm --on-active="$within" --timer-property=AccuracySec=1s "$self" rollback --auto
      echo "confirm within $within with: nixie apply --confirm"
    fi
    push_site ;;
  update)
    # What the site repository has against what this machine runs. The
    # commit the running system was built from is the honest comparison:
    # a checkout can be edited without ever being applied.
    check=0; now=0; auto=0; inputs=0
    while [ $# -gt 0 ]; do
      case "$1" in --check) check=1 ;; --now) now=1 ;; --auto) auto=1 ;; --inputs) inputs=1; shift; break ;; esac
      shift
    done
    # The platform itself, and anything else the site pins: a newer lock is
    # an ordinary site change, so the other machines follow it the same way.
    if [ "$inputs" = 1 ]; then
      [ -d "$site/.git" ] || { echo "no site checkout at $site" >&2; exit 2; }
      (cd "$site" && nix flake update "$@")
      exec "$self" apply --yes
    fi
    state=/run/nixie/update.json
    mkdir -p /run/nixie
    if [ -z "$siterepo" ]; then
      echo "no site repository: set nixie.site.repo so this machine can follow one" >&2
      exit 2
    fi
    if [ "$now" = 1 ]; then exec "$self" apply --yes; fi
    if [ -d "$site/.git" ]; then
      git -C "$site" remote get-url origin >/dev/null 2>&1 || git -C "$site" remote add origin "$siterepo"
      git -C "$site" fetch -q origin "$siteref" 2>/dev/null || { echo "the site repository could not be reached" >&2; exit 1; }
      remote=$(git -C "$site" rev-parse FETCH_HEAD)
      subject=$(git -C "$site" log -1 --format=%s FETCH_HEAD)
      running=${siterev:-$(git -C "$site" rev-parse HEAD)}
      # How many commits this machine is behind, when it knows where it is.
      behind=$(git -C "$site" rev-list --count "$running..FETCH_HEAD" 2>/dev/null || echo 0)
      available=false; [ "${remote#"$running"}" = "$remote" ] && [ "$behind" != 0 ] && available=true
    else
      echo "no site checkout at $site" >&2; exit 2
    fi
    jq -n --arg checked "$(date -Is)" --arg running "$running" --arg remote "$remote" \
      --arg subject "$subject" --argjson behind "$behind" --argjson available "$available" \
      '{checked:$checked, running:$running, remote:$remote, subject:$subject, behind:$behind, available:$available}' >"$state"
    "$self" notices --write
    if [ "$available" != true ]; then
      if [ "$auto" = 0 ]; then echo "up to date with $siteref of the site repository"; fi
      exit 0
    fi
    echo "$behind commit(s) waiting on $siteref: ${remote:0:7} $subject"
    if [ "$check" = 1 ]; then exit 0; fi
    if [ "$auto" = 1 ] && [ "$updatemode" != auto ]; then exit 0; fi
    if [ "$auto" = 1 ]; then
      # Unattended: the machine puts itself back if the new system fails its
      # own checks, or never comes back to confirm. What counts is that the
      # new system is no worse than the one it replaced: doctor is strict,
      # and a machine already unhappy about something the update does not
      # touch would otherwise revert every update, hour after hour.
      before=0; "$self" doctor >/dev/null 2>&1 || before=1
      rc=0
      "$self" apply --yes ${updatewithin:+--confirm-within "$updatewithin"} || rc=$?
      if [ "$rc" = 0 ] && [ -n "$updatewithin" ]; then
        after=0; "$self" doctor >/dev/null 2>&1 || after=1
        if [ "$after" -le "$before" ]; then "$self" apply --confirm
        else echo "nixie update: the new system does not pass doctor where the old one did; leaving the rollback timer to undo it" >&2; fi
      fi
      "$self" update --check >/dev/null || true
      exit "$rc"
    fi
    echo "run 'nixie update --now' to apply it"
    ;;
  notices)
    # Everything this machine wants a person to know, for the surfaces that
    # show it: the front panel, the host page, a desktop notification, the
    # login line and `nixie doctor`.
    write=0; json=0
    while [ $# -gt 0 ]; do case "$1" in --write) write=1 ;; --json) json=1 ;; esac; shift; done
    items=$(
      {
        if [ -s /run/nixie/update.json ] && [ "$(jq -r .available /run/nixie/update.json)" = true ]; then
          jq -c --arg a "nixie update --now" '{id:"update", level:"info",
            title:(if .behind == 1 then "A newer site is waiting" else "\(.behind) newer site commits are waiting" end),
            detail:.subject, action:$a}' /run/nixie/update.json
        fi
        if [ -e /run/nixie/apply-pending.json ]; then
          echo '{"id":"apply-confirm","level":"warn","title":"An apply is waiting to be confirmed","detail":"it is undone by itself when the time runs out","action":"nixie apply --confirm"}'
        fi
        if feature attestation && ! tpm2-totp calculate >/dev/null 2>&1; then
          echo '{"id":"reseal","level":"warn","title":"The attestation code does not compute","detail":"the boot chain changed; reseal it if you changed it yourself","action":"nixie reseal"}'
        fi
        if [ -e /var/lib/nixie/backup-check.json ] && [ "$(jq -r .ok /var/lib/nixie/backup-check.json)" != true ]; then
          echo '{"id":"backup","level":"warn","title":"The last backup check failed","detail":"the repository was unreadable or a snapshot did not verify","action":"nixie backup verify"}'
        fi
        # The first thing anyone wants to know about a machine they cannot
        # see. cut, not awk: the command's PATH is its runtimeInputs.
        broken=$(systemctl list-units --failed --plain --no-legend 2>/dev/null | cut -d' ' -f1 | tr '\n' ' ')
        if [ -n "${broken// /}" ]; then
          jq -n --arg d "$broken" '{id:"units", level:"warn", title:"A service on this machine failed",
            detail:$d, action:"systemctl --failed"}'
        fi
        if command -v usbguard >/dev/null && systemctl is-active -q usbguard 2>/dev/null; then
          n=$(usbguard list-devices -b 2>/dev/null | grep -c . || true)
          [ "$n" = 0 ] || printf '{"id":"usb","level":"info","title":"%s USB device(s) blocked","detail":"plugged in after this machine was set up","action":"nixie usb"}\n' "$n"
        fi
      } | jq -s .
    )
    out=$(jq -n --arg generated "$(date -Is)" --argjson notices "$items" '{generated:$generated, notices:$notices}')
    if [ "$write" = 1 ]; then
      mkdir -p /run/nixie
      printf '%s\n' "$out" >/run/nixie/notices.json
      chmod 644 /run/nixie/notices.json
      # The control panel reads them from the daemon's own configuration,
      # which takes a client certificate: a file served beside the bundle
      # would tell anyone who opens the page that a backup failed. The
      # notices themselves go there, without the time they were collected,
      # so an unchanged machine writes nothing every quarter of an hour --
      # each write is an event that wakes every open panel.
      if [ "$guests" = 1 ] && systemctl is-active -q incus 2>/dev/null; then
        [ "$(incus config get user.nixie.notices 2>/dev/null)" = "$items" ] ||
          incus config set user.nixie.notices "$items" >/dev/null 2>&1 || true
      fi
    fi
    if [ "$json" = 1 ]; then printf '%s\n' "$out"; exit 0; fi
    if [ "$write" = 1 ]; then exit 0; fi
    printf '%s' "$out" | jq -r '.notices[] | "  \(.title)\n    \(.detail)\n    \(.action)"'
    ;;
  site)
    case "${1:-}" in
      key)
        # Add this public key to the remote in nixie.site.repo with write
        # access; `nixie apply` then pushes every change it applies.
        [ -e "$sitekey" ] || ssh-keygen -q -t ed25519 -N "" -C "nixie site $host" -f "$sitekey"
        cat "$sitekey.pub" ;;
      *) echo "usage: nixie site key" >&2; exit 2 ;;
    esac ;;
  export)
    need_guests
    name=${1:?instance name}
    c=$(incus config show "$name")
    kind=container; [ "$(printf '%s' "$c" | yq '.type')" = virtual-machine ] && kind=vm
    img=$(printf '%s' "$c" | yq '.config["volatile.base_image"] // ""')
    echo "  $name = {"
    if printf '%s' "$c" | yq -e '.config["image.os"] == "nixos"' >/dev/null 2>&1; then
      echo '    kind = "nixos";'
    elif [ "$kind" = vm ]; then
      echo '    kind = "vm";'; echo "    image = { fingerprint = \"$img\"; };"
    else
      echo '    kind = "image";'; echo "    image = { fingerprint = \"$img\"; };"
    fi
    [ "$(printf '%s' "$c" | yq '.config["security.nesting"] // "false"')" = true ] && echo '    nesting = true;'
    printf '%s' "$c" | yq -e '.devices[] | select(.type == "gpu")' >/dev/null 2>&1 && echo '    gpu = true;'
    mem=$(printf '%s' "$c" | yq '.config["limits.memory"] // ""'); [ -n "$mem" ] && echo "    limits.memory = \"$mem\";"
    cpu=$(printf '%s' "$c" | yq '.config["limits.cpu"] // ""'); [ -n "$cpu" ] && echo "    limits.cpu = \"$cpu\";"
    mounts=$(printf '%s' "$c" | yq '.devices[] | select(.type == "disk" and .source != null) | "      \"" + .source + "\" = \"" + .path + "\";"')
    [ -n "$mounts" ] && { echo "    mounts = {"; echo "$mounts"; echo "    };"; }
    echo "  };" ;;
  doctor)
    rc=0
    if feature encryption; then
      for pair in $(layout '.luks[] | .name + "=" + .device'); do
        n=$(cryptsetup luksDump "${pair#*=}" 2>/dev/null | grep -cE '^ +[0-9]+: luks2' || true)
        say "luks" "${pair%%=*}: $n key slot(s)"
      done
    fi
    if feature tpm; then
      if [ -e /dev/tpmrm0 ]; then say "tpm" "present"; else say "tpm" "MISSING"; rc=1; fi
    fi
    if feature attestation; then
      if tpm2-totp calculate >/dev/null 2>&1; then say "attestation" "ok"; else say "attestation" "RESEAL NEEDED (run: nixie reseal)"; rc=1; fi
    fi
    if feature secureBoot; then
      if bootctl status 2>/dev/null | grep -qE 'Secure Boot: *enabled'; then say "secure boot" "enabled"; else say "secure boot" "NOT ENABLED"; rc=1; fi
    fi
    if feature tpm; then
      # systemd-cryptsetup says so when the TPM could not unseal and a
      # typed key opened the layer instead.
      if journalctl -b -q -o cat 2>/dev/null | grep -qE 'TPM2 (operation|PIN unlock) failed'; then say "unlock" "RECOVERY KEY used at the last unlock; run nixie security reenroll"; rc=1
      else say "unlock" "TPM"; fi
    fi
    if [ -e /etc/nixie/hardware.json ]; then
      drift=""
      for mac in $(jq -r '.uplinks[]' /etc/nixie/hardware.json); do
        ip -j link | jq -e --arg m "$mac" 'any(.[]; .address == $m)' >/dev/null || drift="$drift uplink:$mac"
      done
      want_disk=$(jq -r '.disks.system' /etc/nixie/hardware.json)
      [ "$want_disk" = null ] || [ -e "$want_disk" ] || drift="$drift disk:$want_disk"
      data_disk=$(jq -r '.disks.data // empty' /etc/nixie/hardware.json)
      [ -z "$data_disk" ] || [ -e "$data_disk" ] || drift="$drift disk:$data_disk"
      want_gpu=$(jq -r .gpu /etc/nixie/hardware.json)
      if [ "$want_gpu" != none ]; then
        case "$want_gpu" in nvidia) id='\[10de:' ;; amd) id='\[1002:' ;; intel) id='\[8086:' ;; *) id="" ;; esac
        if [ -n "$id" ] && ! lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -q "$id"; then drift="$drift gpu:$want_gpu"; fi
      fi
      if [ -n "$drift" ]; then say "hardware" "DRIFT:$drift; run nixie hardware scan"; rc=1
      else say "hardware" "matches the site"; fi
    fi
    if systemctl is-active -q usbguard 2>/dev/null; then
      n=$(usbguard list-devices -b 2>/dev/null | grep -c . || true)
      if [ "$n" -gt 0 ]; then say "usb" "$n BLOCKED device(s); run nixie usb"; rc=1; else say "usb" "nothing blocked"; fi
    fi
    if [ -e /run/current-system/etc/nixie/guests.json ] && incus info >/dev/null 2>&1; then
      for g in $(jq -r '.declared | keys[]' /run/current-system/etc/nixie/guests.json); do
        st=$(incus list "^$g\$" -c s -f csv 2>/dev/null || echo MISSING); say "guest" "$g: ${st:-MISSING}"
        [ "$st" = RUNNING ] || rc=1
      done
    fi
    if command -v nixie-backup >/dev/null; then
      if [ -e /var/lib/nixie/backup-check.json ]; then
        if [ "$(jq -r .ok /var/lib/nixie/backup-check.json)" = true ]; then say "backup check" "ok ($(jq -r .time /var/lib/nixie/backup-check.json))"
        else say "backup check" "FAILED; run nixie backup verify"; rc=1; fi
      else say "backup check" "not run yet"; fi
    fi
    # What the site repository holds, from the last check; the timer keeps
    # it current (nixie.updates.mode).
    if [ -s /run/nixie/update.json ]; then
      if [ "$(jq -r .available /run/nixie/update.json)" = true ]; then
        say "site" "$(jq -r '"\(.behind) commit(s) waiting: \(.subject)"' /run/nixie/update.json); run nixie update --now"
      else say "site" "up to date with the site repository"; fi
    fi
    broken=$(systemctl list-units --failed --plain --no-legend 2>/dev/null | cut -d' ' -f1 | tr '\n' ' ')
    if [ -n "${broken// /}" ]; then say "services" "FAILED:$broken"; rc=1; else say "services" "none failed"; fi
    free=$(df --output=pcent / | tail -1 | tr -dc 0-9)
    if [ "$free" -ge 90 ]; then say "disk" "root $free% full"; rc=1; else say "disk" "root $free% used"; fi
    exit $rc ;;
  reseal)
    feature attestation || { echo "attestation is off; nothing to reseal"; exit 0; }
    tpm2-totp reseal -P "$(cat /var/lib/nixie/totp-recovery 2>/dev/null)" -p 4,7,8,9 </dev/null \
      && { mkdir -p /boot/nixie; readlink -f /run/booted-system | tr -d '\n' >/boot/nixie/attestation-generation; echo "attestation resealed to the running boot chain"; } ;;
  menu)
    command -v nixie-menu >/dev/null || { echo "the menu is part of the desktop profile" >&2; exit 2; }
    exec nixie-menu "$@" ;;
  fetch)
    command -v nixie-fetch >/dev/null || { echo "no data manifest on this host" >&2; exit 2; }
    exec nixie-fetch "$@" ;;
  restore)
    command -v nixie-restore >/dev/null || { echo "backups are off on this host" >&2; exit 2; }
    exec nixie-restore "$@" ;;
  backup)
    command -v nixie-backup >/dev/null || { echo "backups are off on this host" >&2; exit 2; }
    exec nixie-backup "$@" ;;
  security)
    # A key already plugged in may be blocked; FIDO2 keys are HID devices
    # without a boot protocol.
    if [ "${1:-}" = add-key ]; then
      dev=$(layout '.luks[]? | select(.name == "rpool") | .device')
      [ -n "$dev" ] || { echo "this machine's disk is not encrypted" >&2; exit 2; }
      rule=""
      if systemctl is-active -q usbguard 2>/dev/null; then
        for id in $(usbguard list-devices -b | grep -E 'with-interface (\{[^}]*)?03:00:00' | cut -d: -f1); do usbguard allow-device "$id"; done
        rule=$(usbguard append-rule -t 'allow with-interface one-of { 03:00:00 }' || true)
      fi
      echo "Plug in the security key. You are asked for the disk passphrase, then the key's PIN, then a touch."
      rc=0
      systemd-cryptenroll --fido2-device=auto "$dev" || rc=$?
      [ -z "$rule" ] || usbguard remove-rule "$rule" >/dev/null 2>&1 || true
      exit "$rc"
    fi
    [ "${1:-}" = reenroll ] || { echo "usage: nixie security reenroll [--backup-dest <dir>] | add-key" >&2; exit 2; }
    shift
    d=/var/lib/nixie/reenroll
    mkdir -p "$d" /run/nixie/keys; chmod 700 /run/nixie/keys
    # A keyboard plugged in for this must not be blocked: the ones already
    # waiting are let through, and a temporary rule covers the rest
    # until the end.
    rule=""
    if systemctl is-active -q usbguard 2>/dev/null; then
      for id in $(usbguard list-devices -b | grep -E 'with-interface (\{[^}]*)?03:0[01]:01' | cut -d: -f1); do usbguard allow-device "$id"; done
      rule=$(usbguard append-rule -t 'allow with-interface one-of { 03:00:01 03:01:01 }' || true)
    fi
    if feature tpm && [ -t 0 ]; then
      [ -s /run/nixie/keys/recovery-key ] || { read -r -s -p "recovery key of the outer layer: " k; echo; (umask 077; printf '%s' "$k" >/run/nixie/keys/recovery-key); }
      [ -s /run/nixie/keys/pin ] || { read -r -s -p "new PIN: " k; echo; (umask 077; printf '%s' "$k" >/run/nixie/keys/pin); }
    fi
    # The phases keep their markers here, so a reboot in the middle
    # (Secure Boot enrolment) resumes where it stopped; setup's own
    # markers stay untouched.
    [ -e "$d/state.json" ] || cp /var/lib/nixie/setup/state.json "$d/" 2>/dev/null || true
    rc=0
    NIXIE_SETUP_DIR=$d nixie-phase 5 || rc=$?
    if [ "$rc" = 10 ]; then echo "reboot now, then run 'nixie security reenroll' again to continue"; fi
    if [ "$rc" = 0 ]; then
      NIXIE_SETUP_DIR=$d nixie-phase 6 --force "$@" || rc=$?
      # The new bundle replaces setup's as soon as it exists; a failed
      # verification afterwards must not lose it.
      if [ -e "$d/header-backup.tar.age" ]; then mv "$d/header-backup.tar.age" /var/lib/nixie/setup/header-backup.tar.age; fi
      [ "$rc" = 0 ] && { NIXIE_SETUP_DIR=$d nixie-phase 7 || rc=$?; }
      if [ "$rc" = 0 ]; then
        if [ -s /run/nixie/keys/recovery-key ] && [ -t 1 ]; then
          echo; echo "The new recovery key, shown once:"; qrencode -t UTF8 -m 1 "$(cat /run/nixie/keys/recovery-key)"; cat /run/nixie/keys/recovery-key; echo
        fi
        if [ -s /run/nixie/keys/attestation-qr ] && [ -t 1 ]; then echo "The new attestation secret; scan it now:"; cat /run/nixie/keys/attestation-qr; fi
        rm -r "$d"; echo "re-enrolment complete"
      fi
    fi
    [ -z "$rule" ] || usbguard remove-rule "$rule" >/dev/null 2>&1 || true
    exit "$rc" ;;
  secure-boot)
    # What the firmware holds, what is on the boot partition and what is
    # signed -- the three things "Access Denied" can be about.
    sign=0
    while [ $# -gt 0 ]; do case "$1" in --sign) sign=1 ;; esac; shift; done
    pki=${NIXIE_SBCTL:-/var/lib/sbctl}
    efivars=${NIXIE_EFIVARS:-/sys/firmware/efi/efivars}
    esp=${NIXIE_ESP:-/boot}
    # The command's own PATH comes first, so a test's stand-in is named.
    status=$(${NIXIE_BOOTCTL:-bootctl} status 2>/dev/null || true)
    sb=no; setup=no
    printf '%s' "$status" | grep -qE 'Secure Boot: *enabled' && sb=yes
    printf '%s' "$status" | grep -qE 'Setup Mode: *setup|\(setup\)' && setup=yes
    # This machine's own platform key, by its certificate inside the
    # firmware's PK variable: "disabled" reads the same with anyone's keys.
    ours=no
    pk="$efivars/PK-8be4df61-93ca-11d2-aa0d-00e098032b8c"
    if [ -r "$pk" ] && [ -r "$pki/keys/PK/PK.pem" ]; then
      mine=$(openssl x509 -in "$pki/keys/PK/PK.pem" -outform DER | od -An -v -tx1 | tr -d ' \n')
      [ -n "$mine" ] && od -An -v -tx1 "$pk" | tr -d ' \n' | grep -q "$mine" && ours=yes
    fi
    staged=no
    [ -n "$(find "$esp/loader/keys" -name '*.auth' 2>/dev/null | head -1)" ] && staged=yes
    say "firmware" "Secure Boot $sb, Setup Mode $setup, this machine's keys enrolled: $ours"
    say "keys on the boot partition" "$staged"
    # Everything the firmware could be asked to start.
    unsigned=""
    if [ -r "$pki/keys/db/db.pem" ] && command -v sbverify >/dev/null; then
      while IFS= read -r f; do
        sbverify --cert "$pki/keys/db/db.pem" "$f" >/dev/null 2>&1 || unsigned="$unsigned $f"
      done < <(find "$esp/EFI" -name '*.efi' -o -name '*.EFI' 2>/dev/null)
      if [ -z "$unsigned" ]; then say "signatures" "every boot file is signed with this machine's key"
      else say "signatures" "NOT SIGNED with this machine's key:$unsigned"; fi
    fi
    if [ "$sign" = 1 ] && [ -n "$unsigned" ] && command -v sbctl >/dev/null; then
      for f in $unsigned; do sbctl sign -s "$f" || true; done
      echo "signed again; restart to try it"
      exit 0
    fi
    echo
    if [ "$sb" = yes ] && [ -z "$unsigned" ]; then
      echo "Secure Boot is on and this machine's own keys verify its boot chain. Nothing to do."
    elif [ "$sb" = yes ]; then
      echo "Secure Boot is on but the files above are not signed with this machine's key, which is what \"Access Denied\" means."
      echo "Turn Secure Boot off, start the machine, run 'nixie secure-boot --sign', then turn it back on."
    elif [ "$setup" = yes ] && [ "$staged" = yes ]; then
      echo "The firmware is in Setup Mode and the keys are waiting on the boot partition: restart, and the boot loader enrols them. Leave Secure Boot off until it has."
    elif [ "$setup" = yes ]; then
      echo "The firmware is in Setup Mode but no keys are staged: run 'nixie apply' to put them on the boot partition, then restart."
    elif [ "$ours" = yes ]; then
      echo "This machine's keys are in the firmware: turn Secure Boot on in the firmware settings."
    else
      echo "The firmware holds someone else's keys (usually the vendor's). In the firmware settings, under Secure Boot:"
      echo "  1. Set Secure Boot Mode to Custom (some firmware says User)."
      echo "  2. Delete or reset the keys: \"Delete all keys\", \"Reset to Setup Mode\" or \"Clear Secure Boot keys\"."
      echo "  3. Leave Secure Boot itself off, save, and restart. This machine then enrols its own keys."
      echo "Turned on before that, the firmware refuses everything with \"Access Denied\"; turning it off again loses nothing."
      echo "Take the installer stick out as well: its image is not signed, and the firmware tries it first."
    fi
    ;;
  disk)
    # Another Nixie disk, opened by hand for a clone or a rescue: on the
    # installer image or another machine. Each layer takes a security key,
    # the recovery key or the passphrase; not the TPM, whose seal never
    # opens anywhere but in the boot it was made for, and which would only
    # ask for a PIN first. The pools come in under temporary names, so
    # they cannot clash with this machine's own.
    case "${1:-}" in
      open)
        shift
        dev=""; at=/mnt/nixie; rw=0
        while [ $# -gt 0 ]; do
          case "$1" in --mount) at=$2; shift ;; --write) rw=1 ;; *) dev=$1 ;; esac
          shift
        done
        [ -n "$dev" ] || dev=/dev/disk/by-partlabel/disk-system-system
        dev=$(readlink -f "$dev")
        [ -b "$dev" ] || { echo "usage: nixie disk open [<partition>] [--mount <dir>] [--write]" >&2; exit 2; }
        cur=$dev; i=0
        while cryptsetup isLuks "$cur"; do
          name="nixie-$(basename "$dev")-$i"
          opts=""
          [ "$rw" = 1 ] || opts="readonly"
          # A security key only where one is enrolled: asked for one
          # elsewhere, systemd-cryptsetup gives up instead of asking.
          if cryptsetup luksDump "$cur" | grep -q systemd-fido2; then
            opts="${opts:+$opts,}fido2-device=auto,token-timeout=5s"
          fi
          if [ ! -e "/dev/mapper/$name" ]; then
            echo "Opening $cur: a security key, the recovery key or the passphrase."
            # Without token modules systemd-cryptsetup tries only what
            # opts names; with them it first asks for the PIN of every
            # token, the TPM's included.
            SYSTEMD_CRYPTSETUP_USE_TOKEN_MODULE=0 @systemd@/lib/systemd/systemd-cryptsetup attach "$name" "$cur" none "${opts:-luks}"
          fi
          cur=/dev/mapper/$name; i=$((i + 1))
        done
        pool=$(zpool import -d "$cur" 2>/dev/null | awk '$1 == "pool:" { print $2; exit }')
        if [ -z "$pool" ]; then
          echo "no storage pool to import inside $dev (is it this machine's own, already in use?)" >&2
          exit 1
        fi
        ro=(-o readonly=on); [ "$rw" = 0 ] || ro=()
        # Forced: the pool was last used by the machine it came from.
        zpool import -N -f "${ro[@]}" -R "$at" -d "$cur" -t "$pool" "nixie-$pool"
        zfs list -H -o name,mountpoint -r "nixie-$pool" | sort -k2 | while read -r ds mp; do
          [ "$mp" = none ] || [ "$mp" = legacy ] || zfs mount "$ds"
        done
        echo "$dev is open at $at$([ "$rw" = 1 ] || echo ", read-only"); 'nixie disk close' locks it again." ;;
      close)
        zpool list -H -o name | grep '^nixie-' | while read -r p; do zpool export "$p"; done
        find /dev/mapper -name 'nixie-*-[0-9]*' -printf '%f\n' | sort -r | while read -r m; do cryptsetup close "$m"; done
        echo "closed" ;;
      *) echo "usage: nixie disk open [<partition>] [--mount <dir>] [--write] | close" >&2; exit 2 ;;
    esac ;;
  hardware)
    facts=/etc/nixie/hardware.json
    hw="$site/hosts/$host/hardware.nix"
    live_uplinks() { ip -j link | jq -r '[.[] | select(.link_type == "ether" and (.ifname | startswith("veth") or startswith("nixie-") | not)) | .address] | unique | join(" ")'; }
    live_gpu() {
      if lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -q '\[10de:'; then echo nvidia
      elif lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -q '\[1002:'; then echo amd
      elif lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -q '\[8086:'; then echo intel
      else echo none; fi
    }
    case "${1:-scan}" in
      scan|refresh)
        [ -e "$facts" ] || { echo "no $facts on this host" >&2; exit 2; }
        changed=0
        declared_uplinks=$(jq -r '.uplinks | join(" ")' "$facts")
        present=""; missing=""
        for mac in $declared_uplinks; do
          if ip -j link | jq -e --arg m "$mac" 'any(.[]; .address == $m)' >/dev/null; then present="$present $mac"; else missing="$missing $mac"; changed=1; fi
        done
        new=""
        for mac in $(live_uplinks); do
          case " $declared_uplinks " in *" $mac "*) ;; *) new="$new $mac" ;; esac
        done
        gpu_now=$(live_gpu); gpu_want=$(jq -r .gpu "$facts")
        tpm_now=false; [ -e /dev/tpmrm0 ] && tpm_now=true; tpm_want=$(jq -r .tpm "$facts")
        printf '%-10s declared:%s present:%s missing:%s new:%s\n' uplinks "${declared_uplinks:- none}" "${present:- none}" "${missing:- none}" "${new:- none}"
        printf '%-10s declared:%s found:%s\n' gpu "$gpu_want" "$gpu_now"
        printf '%-10s declared:%s found:%s\n' tpm "$tpm_want" "$tpm_now"
        for d in $(jq -r '[.disks.system, .disks.data] | map(select(. != null)) | .[]' "$facts"); do
          if [ -e "$d" ]; then printf '%-10s %s present\n' disk "$d"; else printf '%-10s %s MISSING\n' disk "$d"; changed=1; fi
        done
        [ "$gpu_now" = "$gpu_want" ] || changed=1
        [ "$tpm_now" = "$tpm_want" ] || changed=1
        if [ "${1:-scan}" = scan ]; then
          [ "$changed" = 0 ] && echo "the machine matches $hw" || echo "the machine has moved on from $hw; nixie hardware refresh writes it"
          exit 0
        fi
        [ "$changed" = 0 ] && { echo "nothing to refresh"; exit 0; }
        [ -e "$hw" ] || { echo "no $hw to refresh" >&2; exit 2; }
        # Only the facts that moved, and only in place: the disks a system
        # was installed on are never rewritten from under it.
        keep_uplinks=""
        for mac in $(live_uplinks); do
          case " $missing " in *" $mac "*) ;; *) keep_uplinks="$keep_uplinks \"$mac\"" ;; esac
        done
        tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
        sed -e "s|^  nixie.network.bridge.uplinks = .*|  nixie.network.bridge.uplinks = [$keep_uplinks ];|" \
            -e "s|^  nixie.hardware.gpu = .*|  nixie.hardware.gpu = \"$gpu_now\";|" \
            -e "s|^  nixie.hardware.tpm = .*|  nixie.hardware.tpm = $tpm_now;|" "$hw" >"$tmp"
        diff -u "$hw" "$tmp" || true
        read -r -p "write this to $hw and apply? [y/N] " a; [ "$a" = y ] || exit 1
        cp "$tmp" "$hw"
        git -C "$site" add "$hw" && git -C "$site" commit -qm "hardware: refresh $host" || true
        nixie apply --yes ;;
      add-disk)
        dev=${2:?a stable disk path, the by-id kind}
        [ -e "$dev" ] || { echo "$dev is not there" >&2; exit 2; }
        for d in $(jq -r '[.disks.system, .disks.data] | map(select(. != null)) | .[]' "$facts"); do
          if [ "$(readlink -f "$d")" = "$(readlink -f "$dev")" ]; then
            echo "$dev is already declared in nixie.disks; this command only adds new disks" >&2; exit 3
          fi
        done
        name=${3:-extra}
        # ZFS keeps some words for vdev kinds; zpool's own refusal reads
        # like a typo, so say it plainly before anything is destroyed.
        case "$name" in
          mirror | raidz | raidz1 | raidz2 | raidz3 | draid | draid1 | draid2 | draid3 | spare | log | cache | special | dedup)
            echo "'$name' is a word ZFS keeps for itself; choose another name" >&2; exit 2 ;;
          */* | [0-9]*)
            echo "a pool name cannot contain / or start with a digit" >&2; exit 2 ;;
        esac
        root=$(layout .dataRoot 2>/dev/null); [ -n "$root" ] && [ "$root" != null ] || root=/data
        # Done with the tools already on the host: an installed machine has
        # no Nix search path and may have no network, so nothing here may
        # evaluate or build anything.
        echo "$dev becomes the pool '$name', mounted at $root/$name; everything on it is lost."
        read -r -p "type the disk's name to confirm: " a; [ "$a" = "$(basename "$dev")" ] || { echo "not confirmed" >&2; exit 1; }
        sgdisk --zap-all "$dev" >/dev/null
        zpool create -f -o ashift=12 \
          -O compression=zstd -O acltype=posixacl -O xattr=sa -O mountpoint=none \
          "$name" "$dev"
        zfs create -o mountpoint="$root/$name" "$name/data"
        zpool set cachefile=/etc/zfs/zpool.cache "$name" 2>/dev/null || true
        echo "$dev is now $name, mounted at $root/$name"
        echo "declare it in hosts/$host/hardware.nix as nixie.disks.data, or leave it as an extra pool" ;;
      *) echo "usage: nixie hardware [scan | refresh | add-disk <by-id> [name]]" >&2; exit 2 ;;
    esac ;;
  usb)
    f="$site/hosts/$host/usb.nix"
    case "${1:-}" in
      allow)
        spec=${2:?vendor:product[/serial]}
        [ -e "$f" ] || printf '# Written by nixie usb allow: USB devices allowed on this host.\n{\n  nixie.security.hardening.usbguard.allow = [\n  ];\n}\n' >"$f"
        grep -qF "\"$spec\"" "$f" || sed -i "/^  \];/i\    \"$spec\"" "$f"
        git -C "$site" add "$f" && git -C "$site" commit -qm "usb: allow $spec on $host" || true
        echo "$spec added to $f; run 'nixie apply' to let it through" ;;
      ""|--json)
        list=$(usbguard list-devices -b 2>/dev/null || true)
        rows=$(printf '%s\n' "$list" | sed -n 's/^\([0-9]*\): block id \([0-9a-f:]*\) serial "\([^"]*\)" name "\([^"]*\)".*/\1\t\2\t\3\t\4/p')
        if [ "${1:-}" = --json ]; then printf '%s\n' "$rows" | jq -R -s 'split("\n") | map(select(. != "") | split("\t") | {id: .[0], device: .[1], serial: .[2], name: .[3]})'
        elif [ -z "$rows" ]; then echo "no blocked USB devices"
        else printf '%-13s %-16s %s\n' device serial name; printf '%s\n' "$rows" | awk -F'\t' '{printf "%-13s %-16s %s\n", $2, $3, $4}'; echo "allow one with: nixie usb allow <vendor:product[/serial]>"; fi ;;
      *) echo "usage: nixie usb [--json] | usb allow <vendor:product[/serial]>" >&2; exit 2 ;;
    esac ;;
  rollback)
    prof=/nix/var/nix/profiles/system
    root=$(layout .dataRoot 2>/dev/null); [ -n "$root" ] && [ "$root" != null ] || root=/data
    gen_num() { { readlink "$1" 2>/dev/null || true; } | sed -n 's/.*system-\([0-9]*\)-link/\1/p'; }
    switch_gen() {
      nix-env --profile "$prof" --switch-generation "$1"
      "$(readlink -f "$prof")/bin/switch-to-configuration" switch
      echo "now on generation $1"
    }
    cur=$(gen_num "$prof")
    # A generation's date is its profile link's own: `date -r` follows the
    # link into the store, where every path is dated 1970.
    case "${1:-}" in
      --list)
        printf '%-4s %-17s %-40s %-14s %s\n' gen date label kernel marks
        newest=0; for l in "$prof"-*-link; do n=${l##*system-}; n=${n%-link}; [ "$n" -gt "$newest" ] && newest=$n; done
        for n in $(for m in "$prof"-*-link; do g=${m##*system-}; echo "${g%-link}"; done | sort -n); do
          l="$prof-$n-link"; marks=""
          [ "$(readlink -f "$l")" = "$(readlink -f /run/current-system)" ] && marks="$marks current"
          [ "$(readlink -f "$l")" = "$(readlink -f /run/booted-system 2>/dev/null)" ] && marks="$marks booted"
          [ "$n" = "$newest" ] && marks="$marks boot-default"
          printf '%-4s %-17s %-40s %-14s %s\n' "$n" "$(date -d "@$(stat -c %Y "$l")" '+%F %R')" "$(cat "$l/nixos-version")" "$(basename "$(dirname "$(readlink -f "$l/kernel")")" | sed 's/^[a-z0-9]*-linux-//' | cut -c1-14)" "$marks"
        done ;;
      --json)
        gens=$(for m in "$prof"-*-link; do
          n=${m##*system-}; n=${n%-link}
          jq -n --arg gen "$n" --arg date "$(date -d "@$(stat -c %Y "$m")" -Is)" --arg label "$(cat "$m/nixos-version" 2>/dev/null || echo unknown)" \
            --arg kernel "$(basename "$(dirname "$(readlink -f "$m/kernel")")" 2>/dev/null | sed 's/^[a-z0-9]*-linux-//')" \
            --argjson current "$([ "$(readlink -f "$m")" = "$(readlink -f /run/current-system)" ] && echo true || echo false)" \
            --argjson booted "$([ "$(readlink -f "$m")" = "$(readlink -f /run/booted-system 2>/dev/null)" ] && echo true || echo false)" \
            '{generation: ($gen | tonumber), date: $date, label: $label, kernel: $kernel, current: $current, booted: $booted}'
        done | jq -s 'sort_by(.generation)')
        guests=$(if [ -e /run/current-system/etc/nixie/guests.json ] && incus info >/dev/null 2>&1; then
          for g in $(jq -r '.declared | keys[]' /run/current-system/etc/nixie/guests.json); do
            { incus snapshot list "$g" -f json 2>/dev/null || echo '[]'; } | jq --arg g "$g" '[.[]? | {guest: $g, name: .name, taken: .created_at}]'
          done | jq -s 'add // []'
        else echo '[]'; fi)
        guests=${guests:-[]}
        data=$(if command -v zfs >/dev/null && zfs list -H -o name "$root/state" >/dev/null 2>&1; then
          zfs list -H -t snapshot -o name,creation -s creation "$root/state" | jq -R -s 'split("\n") | map(select(. != "") | split("\t") | {name: (.[0] | sub(".*@"; "")), taken: .[1]})'
        else echo '[]'; fi)
        backups=$(if command -v restic-nixie >/dev/null; then restic-nixie snapshots --json 2>/dev/null | jq '[.[] | {id: .short_id, taken: .time, paths: .paths}]' || echo '[]'; else echo '[]'; fi)
        jq -n --argjson generations "$gens" --argjson guests "$guests" --argjson data "$data" --argjson backups "$backups" \
          '{generations: $generations, guests: $guests, data: $data, backups: $backups}' ;;
      --generation) switch_gen "$2" ;;
      --boot-previous)
        id=$(bootctl list --json=short | jq -r --arg n "$((cur - 1))" '.[] | select(.id | test("generation-" + $n + "([-.]|$)")) | .id' | head -1)
        [ -n "$id" ] || { echo "no boot entry for generation $((cur - 1))" >&2; exit 1; }
        bootctl set-oneshot "$id"; echo "next boot: generation $((cur - 1)) ($id)" ;;
      --auto)
        p=/run/nixie/apply-pending.json; [ -e "$p" ] || exit 0
        prev=$(jq -r .prev "$p"); label=$(jq -r .label "$p")
        for g in $(jq -r '.guests[]' "$p"); do
          incus stop -f "$g" 2>/dev/null || true; incus snapshot restore "$g" "pre-apply-$label" && incus start "$g" || true
        done
        rm -f "$p"
        if [ -n "$prev" ] && [ "$prev" != "$cur" ]; then echo "apply not confirmed; rolling back"; switch_gen "$prev"; fi ;;
      guest)
        need_guests
        name=${2:?guest name}; snap=""; shift 2
        while [ $# -gt 0 ]; do case "$1" in --snapshot) snap=$2; shift ;; esac; shift; done
        [ -n "$snap" ] || snap=$(incus snapshot list "$name" -f csv -c n | grep '^pre-apply-' | sort | tail -1)
        [ -n "$snap" ] || { echo "no snapshot for $name" >&2; exit 1; }
        incus stop -f "$name" 2>/dev/null || true
        incus snapshot restore "$name" "$snap"; incus start "$name"; echo "$name restored to $snap" ;;
      data)
        name=${2:?state name (or 'state' for all)}; snap=""; in_place=0; yes=0; shift 2
        while [ $# -gt 0 ]; do case "$1" in --snapshot) snap=$2; shift ;; --in-place) in_place=1 ;; --yes|-y) yes=1 ;; esac; shift; done
        ds=$(zfs list -H -o name "$root/state" 2>/dev/null) || { echo "$root/state is not a ZFS dataset" >&2; exit 1; }
        [ -n "$snap" ] || snap=$(zfs list -H -t snapshot -o name -s creation "$ds" | sed 's/.*@//' | grep '^pre-apply-' | tail -1)
        [ -n "$snap" ] || { echo "no snapshot of $ds" >&2; exit 1; }
        ts=$(date +%Y%m%d-%H%M%S)
        if [ "$name" = state ]; then
          if [ "$in_place" = 1 ]; then
            [ "$yes" = 1 ] || { read -r -p "roll $root/state back to $snap, discarding everything newer? [y/N] " a; [ "$a" = y ] || exit 1; }
            zfs rollback -r "$ds@$snap"; echo "$root/state rolled back to $snap"
          else
            zfs clone -o mountpoint="$root/state.restore-$ts" "$ds@$snap" "$ds-restore-$ts"; echo "snapshot $snap mounted beside at $root/state.restore-$ts"
          fi
        else
          src="$root/state/.zfs/snapshot/$snap/$name"
          [ -d "$src" ] || { echo "$name is not in snapshot $snap" >&2; exit 1; }
          if [ "$in_place" = 1 ]; then
            [ "$yes" = 1 ] || { read -r -p "replace $root/state/$name with its copy from $snap? [y/N] " a; [ "$a" = y ] || exit 1; }
            rsync -a --delete "$src/" "$root/state/$name/"; echo "$root/state/$name restored in place from $snap"
          else
            cp -a "$src" "$root/state/$name.restored-$ts"; echo "restored beside at $root/state/$name.restored-$ts"
          fi
        fi ;;
      "") [ -n "$cur" ] && [ "$cur" -gt 1 ] || { echo "no earlier generation" >&2; exit 1; }; switch_gen "$((cur - 1))" ;;
      *) echo "usage: nixie rollback [--list | --json | --generation N | --boot-previous | guest <name> [--snapshot s] | data <name>|state [--snapshot s] [--in-place] [--yes]]" >&2; exit 2 ;;
    esac ;;
  help | -h | --help) usage ;;
  *)
    echo "nixie: no command \"$cmd\"" >&2
    usage >&2
    exit 2 ;;
esac
