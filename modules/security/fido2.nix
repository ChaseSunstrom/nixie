{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../../lib/option.nix lib) mkOption;
  cfg = config.nixie.security.fido2;
in
{
  options.nixie.security.fido2.enable = mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Open the disk with a FIDO2 security key (a YubiKey, Nitrokey, SoloKey or
      similar) plugged in at start: the key's PIN and a touch take the place
      of the passphrase, which keeps working for a start without the key.
      Setup enrols the key plugged in at the time; `nixie security add-key`
      enrols a spare. The TPM PIN, when there is one, is still asked first.
    '';
    nixieUi = {
      section = "security";
      # After the TPM's settings, before Secure Boot.
      order = 2.5;
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.nixie.security.encryption.enable;
        message = "nixie.security.fido2.enable needs nixie.security.encryption.enable";
      }
    ];
    boot.initrd.systemd.fido2.enable = true;
    # The passphrase layer, which the person unlocks. Without the key plugged
    # in, systemd-cryptsetup waits this long before asking for the passphrase.
    boot.initrd.luks.devices.rpool.crypttabExtraOpts = [
      "fido2-device=auto"
      "token-timeout=10s"
    ];
    # fido2-token, to see a key's state and set its PIN.
    environment.systemPackages = [ pkgs.libfido2 ];
  };
}
