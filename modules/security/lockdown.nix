{
  config,
  lib,
  ...
}:
let
  inherit (import ../../lib/option.nix lib) mkOption;
  cfg = config.nixie.security.lockdown;
in
{
  options.nixie.security.lockdown = mkOption {
    type = lib.types.enum [
      "none"
      "integrity"
    ];
    default = "none";
    description = ''
      Kernel lockdown. "integrity" stops even the administrator from changing
      the running kernel. The stock kernel is built without it, so choosing
      it rebuilds the kernel from source, and because NixOS does not sign
      kernel modules, every driver that is not built in stops loading. Leave
      it at "none" unless you have checked your hardware.
    '';
    nixieUi = {
      section = "security";
      order = 8;
    };
  };

  config = lib.mkIf (cfg == "integrity") {
    boot.kernelPatches = [
      {
        name = "nixie-lockdown";
        patch = null;
        structuredExtraConfig = {
          SECURITY_LOCKDOWN_LSM = lib.kernel.yes;
          SECURITY_LOCKDOWN_LSM_EARLY = lib.kernel.yes;
        };
      }
    ];
    boot.kernelParams = [ "lockdown=integrity" ];
    warnings = [
      "nixie.security.lockdown = \"integrity\" rebuilds the kernel and refuses unsigned modules; expect drivers to fail."
    ];
  };
}
