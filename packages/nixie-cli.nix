# `nixie`: the everyday command. Subcommands arrive with their slices.
{ pkgs }:
pkgs.writeShellApplication {
  name = "nixie";
  runtimeInputs = with pkgs; [
    coreutils
    cryptsetup
    git
    incus-lts.client
    jq
    nixos-rebuild
    (opentofu.withPlugins (p: [ p.lxc_incus ]))
    systemd
    tpm2-tools
    tpm2-totp
    util-linux
    yq-go
  ];
  text = ''
    layout() { jq -r "$1" /run/current-system/etc/nixie/layout.json; }
    feature() { [ "$(layout ".features.$1")" = true ]; }
    site=''${NIXIE_SITE:-/etc/nixie/site}
    host=$(hostname)
    cmd=''${1:-help}; shift || true
    case "$cmd" in
      apply)
        yes=0; skip_host=0
        for a in "$@"; do case "$a" in --yes|-y) yes=1 ;; --skip-host) skip_host=1 ;; esac; done
        if [ "$skip_host" = 0 ]; then
          if [ -n "$(git -C "$site" remote 2>/dev/null)" ]; then git -C "$site" pull --ff-only || echo "site pull failed; applying the checkout as is" >&2; fi
          # Refuse the one change that needs a reinstall before touching anything.
          want=$(nix eval --raw "$site#nixosConfigurations.$host.config.nixie.security.encryption.enable")
          if [ "$want" != "$(layout .features.encryption)" ]; then
            echo "nixie apply: nixie.security.encryption.enable cannot be changed on an installed system; reinstall from the ISO to change it." >&2
            exit 3
          fi
          # Step 1: the host, so every derived piece exists before a guest has an interface.
          nixos-rebuild switch --flake "$site#$host"
        fi
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
        tofu plan -input=false -out=plan.bin
        if [ "$yes" = 1 ]; then tofu apply -input=false plan.bin; else
          read -r -p "apply this plan? [y/N] " ans; [ "$ans" = y ] && tofu apply -input=false plan.bin
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
          if tpm2-totp show >/dev/null 2>&1; then say "attestation" "ok"; else say "attestation" "RESEAL NEEDED (run: nixie reseal)"; rc=1; fi
        fi
        if feature secureBoot; then
          if bootctl status 2>/dev/null | grep -qE 'Secure Boot: *enabled'; then say "secure boot" "enabled"; else say "secure boot" "NOT ENABLED"; rc=1; fi
        fi
        if [ -e /run/current-system/etc/nixie/guests.json ] && incus info >/dev/null 2>&1; then
          for g in $(jq -r '.declared | keys[]' /run/current-system/etc/nixie/guests.json); do
            st=$(incus list "^$g\$" -c s -f csv 2>/dev/null || echo MISSING); say "guest" "$g: ''${st:-MISSING}"
            [ "$st" = RUNNING ] || rc=1
          done
        fi
        free=$(df --output=pcent / | tail -1 | tr -dc 0-9)
        if [ "$free" -ge 90 ]; then say "disk" "root $free% full"; rc=1; else say "disk" "root $free% used"; fi
        exit $rc ;;
      reseal)
        feature attestation || { echo "attestation is off; nothing to reseal"; exit 0; }
        tpm2-totp reseal -p 4,7,8,9 && echo "attestation resealed to the current boot chain" ;;
      menu)
        command -v nixie-menu >/dev/null || { echo "the menu is part of the desktop profile" >&2; exit 2; }
        exec nixie-menu "$@" ;;
      fetch)
        command -v nixie-fetch >/dev/null || { echo "no data manifest on this host" >&2; exit 2; }
        exec nixie-fetch "$@" ;;
      restore)
        command -v nixie-restore >/dev/null || { echo "backups are off on this host" >&2; exit 2; }
        exec nixie-restore "$@" ;;
      *)
        echo "usage: nixie apply [--yes] [--skip-host] | export <instance> | fetch | restore | reseal | doctor | menu" >&2; exit 2 ;;
    esac
  '';
}
