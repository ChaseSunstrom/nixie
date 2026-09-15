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
    specialArgs.nixieVersion = self.lib.version;
    modules = [
      ../installer/iso.nix
      {
        nixie.installer.packages = packages;
        nixpkgs.pkgs = pkgs;
      }
    ];
  };
in
# The configuration rides along for checks.iso-config.
iso.config.system.build.isoImage // { inherit (iso) config; }
