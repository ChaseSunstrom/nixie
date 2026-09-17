# The duress passphrase: the check itself is in the password agent
# (unlock.nix), the slots in phase 3.
{
  config,
  lib,
  ...
}:
let
  inherit (import ../../lib/option.nix lib) mkOption;
  cfg = config.nixie.security.duress;
in
{
  options.nixie.security.duress.enable = mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      A second, "duress" passphrase. Typing it at any unlock prompt (the PIN
      and the recovery key's included) destroys every key slot on every
      encryption layer, making the data permanently unreadable, then powers
      off. There is no undo. It opens nothing itself, so knowing it does not
      help anyone read the disk elsewhere.
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
  };
}
