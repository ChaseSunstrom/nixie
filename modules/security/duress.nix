{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../../lib/option.nix lib) mkOption;
  cfg = config.nixie.security.duress;
  devices = lib.mapAttrsToList (_: d: d.device) config.boot.initrd.luks.devices;
  # Slot 7 of the passphrase layer holds the duress passphrase. The agent
  # answers every early-boot prompt; for passphrase prompts it first checks
  # which slot the entry opens, and slot 7 means wipe everything and halt.
  agent = pkgs.writeShellApplication {
    name = "nixie-unlock";
    runtimeInputs = [
      pkgs.cryptsetup
      config.boot.initrd.systemd.package
    ];
    text = ''
      devices=(${lib.escapeShellArgs devices})
      until_unlocked=''${1:-}
      while true; do
        handled=0
        for ask in /run/systemd/ask-password/ask.*; do
          [ -e "$ask" ] || continue
          handled=1
          msg=$(sed -n 's/^Message=//p' "$ask")
          sock=$(sed -n 's/^Socket=//p' "$ask")
          id=$(sed -n 's/^Id=//p' "$ask")
          printf '%s ' "$msg"
          IFS= read -rs pw
          echo
          if [[ $id == cryptsetup:* && $msg == *passphrase* ]]; then
            dev=''${id#cryptsetup:}
            slot=$(printf '%s' "$pw" | cryptsetup open --test-passphrase --verbose --key-file=- "$dev" 2>&1 \
              | sed -n 's/^Key slot \([0-9]*\) unlocked.*/\1/p' || true)
            if [ "$slot" = "7" ]; then
              for d in "''${devices[@]}"; do cryptsetup -q erase "$d" || true; done
              sync
              systemctl --force --force poweroff
              exit 0
            fi
          fi
          printf '%s' "$pw" | systemd-reply-password 1 "$sock"
          while [ -e "$ask" ]; do sleep 0.2; done
        done
        if [ "$handled" = 0 ]; then
          if [ -n "$until_unlocked" ] && systemctl -q is-active initrd-root-fs.target; then exit 0; fi
          sleep 0.5
        fi
      done
    '';
  };
in
{
  options.nixie.security.duress.enable = mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      A second, "duress" passphrase. Typing it at the unlock prompt destroys
      every key slot on every encryption layer, making the data permanently
      unreadable, then powers off. There is no undo.
    '';
    nixieUi = {
      section = "security";
      order = 5;
      secret = "duress";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.nixie.security.encryption.enable;
        message = "nixie.security.duress.enable needs nixie.security.encryption.enable";
      }
    ];
    boot.initrd.systemd.storePaths = [ agent ];
    boot.initrd.systemd.services.systemd-ask-password-console.serviceConfig = {
      ExecStart = [
        ""
        "${agent}/bin/nixie-unlock"
      ];
      StandardInput = "tty";
      StandardOutput = "tty";
      StandardError = "tty";
      TTYPath = "/dev/console";
    };
    # The remote-unlock shell relays prompts through the same agent.
    boot.initrd.systemd.users.root.shell =
      lib.mkIf config.nixie.security.remoteUnlock.enable "${agent}/bin/nixie-unlock";
  };
}
