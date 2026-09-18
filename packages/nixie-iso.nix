# The bootable installer image.
{
  pkgs,
  inputs,
  self,
  packages,
  # What a test image adds; the shipped one adds nothing.
  extraModules ? [ ],
}:
let
  # Every source the platform's lock names. Evaluating a site on the installer
  # otherwise unpacked disko, lanzaboote, sops-nix, terranix and their inputs
  # from GitHub into the RAM the installer runs in.
  sources =
    let
      walk = i: [ i.outPath ] ++ builtins.concatMap walk (builtins.attrValues (i.inputs or { }));
    in
    pkgs.lib.unique (builtins.concatMap walk (builtins.attrValues inputs));
  iso = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs.nixieVersion = self.lib.version;
    modules = [
      ../installer/iso.nix
      {
        nixie.installer.packages = packages;
        nixpkgs.pkgs = pkgs;
        system.extraDependencies = sources;
      }
    ]
    ++ extraModules;
  };
in
# The configuration rides along for checks.iso-config.
iso.config.system.build.isoImage // { inherit (iso) config; }
