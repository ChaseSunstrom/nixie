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
    # Not offered by the installer: one click would mean a kernel built from
    # source during the install and drivers that no longer load.
  };

  config = lib.mkIf (cfg == "integrity") {
    boot.kernelPatches = [
      {
        name = "nixie-lockdown";
        patch = null;
        structuredExtraConfig = {
          # The stock configuration sets these to no at the same priority.
          SECURITY_LOCKDOWN_LSM = lib.mkForce lib.kernel.yes;
          SECURITY_LOCKDOWN_LSM_EARLY = lib.mkForce lib.kernel.yes;
        };
      }
    ];
    boot.kernelParams = [ "lockdown=integrity" ];
    warnings = [
      "nixie.security.lockdown = \"integrity\" rebuilds the kernel and refuses unsigned modules; expect drivers to fail."
    ];
  };
}
