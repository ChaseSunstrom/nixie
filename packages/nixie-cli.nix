# `nixie`: the everyday command. Subcommands arrive with their slices.
{ pkgs }:
pkgs.writeShellApplication {
  name = "nixie";
  runtimeInputs = with pkgs; [
    coreutils
    cryptsetup
    git
    gnugrep
    gnused
    rsync
    zfs
    incus-lts.client
    jq
    nix # nix-env for generations; a transient unit's PATH has no system profile
    nixos-rebuild
    (opentofu.withPlugins (p: [ p.lxc_incus ]))
    systemd
    tpm2-tools
    tpm2-totp
    usbguard
    qrencode
    util-linux
    yq-go
    # `security reenroll` runs the same phase scripts setup ran.
    (import ./nixie-installer.nix { inherit pkgs; })
  ];
  text = ''
    layout() { jq -r "$1" /run/current-system/etc/nixie/layout.json; }
    feature() { [ "$(layout ".features.$1")" = true ]; }
    site=''${NIXIE_SITE:-/etc/nixie/site}
    host=$(uname -n) # coreutils: a transient unit's PATH has no hostname(1)
    cmd=''${1:-help}; shift || true
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
          if [ -n "$(git -C "$site" remote 2>/dev/null)" ]; then git -C "$site" pull --ff-only || echo "site pull failed; applying the checkout as is" >&2; fi
          # Refuse the one change that needs a reinstall before touching anything.
          # A prebuilt system answers from its own layout, so no evaluation (and
          # no network) is needed on the host.
          if [ -n "''${NIXIE_TOPLEVEL:-}" ]; then want=$(jq -r .features.encryption "$NIXIE_TOPLEVEL/etc/nixie/layout.json")
          else want=$(nix eval --raw "$site#nixosConfigurations.$host.config.nixie.security.encryption.enable"); fi
          if [ "$want" != "$(layout .features.encryption)" ]; then
            echo "nixie apply: nixie.security.encryption.enable cannot be changed on an installed system; reinstall from the ISO to change it." >&2
            exit 3
          fi
          # Local history first: ZFS snapshots of state/ (kept: last five).
          label="$(date +%Y%m%d-%H%M%S)-$(git -C "$site" rev-parse --short HEAD 2>/dev/null || echo nosite)"
          if command -v nixie-snapshot >/dev/null; then nixie-snapshot pre-apply "$label"; fi
          # Step 1: the host, so every derived piece exists before a guest has an interface.
          # A prebuilt system (deploy, tests) is switched to directly.
          if [ -n "''${NIXIE_TOPLEVEL:-}" ]; then
            nix-env --profile "$prof" --set "$NIXIE_TOPLEVEL"
            "$NIXIE_TOPLEVEL/bin/switch-to-configuration" switch
          else
            nixos-rebuild switch --flake "$site#$host"
          fi
        fi
        : "''${label:=$(date +%Y%m%d-%H%M%S)}"
        [ -e /run/current-system/etc/nixie/tofu/config.tf.json ] || { echo "no guests to manage on this host"; exit 0; }
        # Step 2: NixOS guest images, built with the host, imported by alias.
        while IFS=$'\t' read -r name alias path; do
          [ -z "$path" ] || [ "$path" = null ] && continue
          if ! incus image alias list -f csv | cut -d, -f1 | grep -qx "$alias"; then
            echo "importing image for $name as $alias"
            incus image import "$path/metadata.tar.xz" "$path/rootfs.tar.xz" --alias "$alias"
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
          jq -n --arg prev "''${prev_gen:-}" --arg label "$label" --arg guests "$touched" \
            '{prev: $prev, label: $label, guests: ($guests | split(" ") | map(select(. != "")))}' >/run/nixie/apply-pending.json
          systemd-run --quiet --unit=nixie-apply-confirm --on-active="$within" --timer-property=AccuracySec=1s nixie rollback --auto
          echo "confirm within $within with: nixie apply --confirm"
        fi ;;
      export)
        name=''${1:?instance name}
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
        say() { printf '%-14s %s\n' "$1" "$2"; }
        if feature encryption; then
          for pair in $(layout '.luks[] | .name + "=" + .device'); do
            n=$(cryptsetup luksDump "''${pair#*=}" 2>/dev/null | grep -cE '^ +[0-9]+: luks2' || true)
            say "luks" "''${pair%%=*}: $n key slot(s)"
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
        if systemctl is-active -q usbguard 2>/dev/null; then
          n=$(usbguard list-devices -b 2>/dev/null | grep -c . || true)
          if [ "$n" -gt 0 ]; then say "usb" "$n BLOCKED device(s); run nixie usb"; rc=1; else say "usb" "nothing blocked"; fi
        fi
        if [ -e /run/current-system/etc/nixie/guests.json ] && incus info >/dev/null 2>&1; then
          for g in $(jq -r '.declared | keys[]' /run/current-system/etc/nixie/guests.json); do
            st=$(incus list "^$g\$" -c s -f csv 2>/dev/null || echo MISSING); say "guest" "$g: ''${st:-MISSING}"
            [ "$st" = RUNNING ] || rc=1
          done
        fi
        if command -v nixie-backup >/dev/null; then
          if [ -e /var/lib/nixie/backup-check.json ]; then
            if [ "$(jq -r .ok /var/lib/nixie/backup-check.json)" = true ]; then say "backup check" "ok ($(jq -r .time /var/lib/nixie/backup-check.json))"
            else say "backup check" "FAILED; run nixie backup verify"; rc=1; fi
          else say "backup check" "not run yet"; fi
        fi
        free=$(df --output=pcent / | tail -1 | tr -dc 0-9)
        if [ "$free" -ge 90 ]; then say "disk" "root $free% full"; rc=1; else say "disk" "root $free% used"; fi
        exit $rc ;;
      reseal)
        feature attestation || { echo "attestation is off; nothing to reseal"; exit 0; }
        tpm2-totp reseal -P "$(cat /var/lib/nixie/totp-recovery 2>/dev/null)" -p 4,7,8,9 </dev/null \
          && { mkdir -p /boot/nixie; cat /run/current-system/nixos-version >/boot/nixie/attestation-generation; echo "attestation resealed to the current boot chain"; } ;;
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
        [ "''${1:-}" = reenroll ] || { echo "usage: nixie security reenroll [--backup-dest <dir>]" >&2; exit 2; }
        shift
        d=/var/lib/nixie/reenroll
        mkdir -p "$d" /run/nixie/keys; chmod 700 /run/nixie/keys
        # A keyboard plugged in for this must not be blocked: the ones already
        # waiting are let through, and a temporary rule covers the rest
        # until the end.
        rule=""
        if systemctl is-active -q usbguard 2>/dev/null; then
          for id in $(usbguard list-devices -b | grep -E 'with-interface [^ ]*03:0[01]:01' | cut -d: -f1); do usbguard allow-device "$id"; done
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
      usb)
        f="$site/hosts/$host/usb.nix"
        case "''${1:-}" in
          allow)
            spec=''${2:?vendor:product[/serial]}
            [ -e "$f" ] || printf '# Written by nixie usb allow: USB devices allowed on this host.\n{\n  nixie.security.hardening.usbguard.allow = [\n  ];\n}\n' >"$f"
            grep -qF "\"$spec\"" "$f" || sed -i "/^  \];/i\    \"$spec\"" "$f"
            git -C "$site" add "$f" && git -C "$site" commit -qm "usb: allow $spec on $host" || true
            echo "$spec added to $f; run 'nixie apply' to let it through" ;;
          ""|--json)
            list=$(usbguard list-devices -b 2>/dev/null || true)
            rows=$(printf '%s\n' "$list" | sed -n 's/^\([0-9]*\): block id \([0-9a-f:]*\) serial "\([^"]*\)" name "\([^"]*\)".*/\1\t\2\t\3\t\4/p')
            if [ "''${1:-}" = --json ]; then printf '%s\n' "$rows" | jq -R -s 'split("\n") | map(select(. != "") | split("\t") | {id: .[0], device: .[1], serial: .[2], name: .[3]})'
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
        case "''${1:-}" in
          --list)
            printf '%-4s %-17s %-40s %-14s %s\n' gen date label kernel marks
            newest=0; for l in "$prof"-*-link; do n=''${l##*system-}; n=''${n%-link}; [ "$n" -gt "$newest" ] && newest=$n; done
            for n in $(for m in "$prof"-*-link; do g=''${m##*system-}; echo "''${g%-link}"; done | sort -n); do
              l="$prof-$n-link"; marks=""
              [ "$(readlink -f "$l")" = "$(readlink -f /run/current-system)" ] && marks="$marks current"
              [ "$(readlink -f "$l")" = "$(readlink -f /run/booted-system 2>/dev/null)" ] && marks="$marks booted"
              [ "$n" = "$newest" ] && marks="$marks boot-default"
              printf '%-4s %-17s %-40s %-14s %s\n' "$n" "$(date -r "$l" '+%F %R')" "$(cat "$l/nixos-version")" "$(basename "$(readlink -f "$l/kernel")" | sed 's/^[a-z0-9]*-linux-//' | cut -c1-14)" "$marks"
            done ;;
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
            name=''${2:?guest name}; snap=""; shift 2
            while [ $# -gt 0 ]; do case "$1" in --snapshot) snap=$2; shift ;; esac; shift; done
            [ -n "$snap" ] || snap=$(incus snapshot list "$name" -f csv -c n | grep '^pre-apply-' | sort | tail -1)
            [ -n "$snap" ] || { echo "no snapshot for $name" >&2; exit 1; }
            incus stop -f "$name" 2>/dev/null || true
            incus snapshot restore "$name" "$snap"; incus start "$name"; echo "$name restored to $snap" ;;
          data)
            name=''${2:?state name (or 'state' for all)}; snap=""; in_place=0; yes=0; shift 2
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
          *) echo "usage: nixie rollback [--list | --generation N | --boot-previous | guest <name> [--snapshot s] | data <name>|state [--snapshot s] [--in-place] [--yes]]" >&2; exit 2 ;;
        esac ;;
      *)
        echo "usage: nixie apply [--yes] [--skip-host] [--confirm-within <duration>] | apply --confirm | rollback ... | export <instance> | fetch | backup now|list|verify|kit <file> | restore <snapshot> [--path <p>] [--to <dir>] | reseal | security reenroll | usb [--json] | usb allow <device> | doctor | menu" >&2; exit 2 ;;
    esac
  '';
}
