# Facts the installer discovers and writes into a site's hardware.nix. Nothing
# in the platform may set these.
{ lib, ... }:
let
  inherit (import ../lib/option.nix lib) mkOption;
in
{
  options.nixie.hardware = {
    gpu = mkOption {
      type = lib.types.enum [
        "none"
        "nvidia"
        "amd"
        "intel"
      ];
      default = "none";
      description = ''
        The kind of graphics card the installer found. Drives which driver is
        installed and, on a server, whether guests may be given the GPU.
      '';
    };
    tpm = mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether the installer found a TPM 2.0 chip. TPM binding and attestation
        need one.
      '';
    };
  };
}
