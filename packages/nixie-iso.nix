# The bootable installer image.
{
  pkgs,
  inputs,
  self,
  packages,
}:
let
  iso = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      ../installer/iso.nix
      {
        nixie.installer.packages = packages;
        nixie.installer.platform = self;
        nixpkgs.pkgs = pkgs;
      }
    ];
  };
in
iso.config.system.build.isoImage
