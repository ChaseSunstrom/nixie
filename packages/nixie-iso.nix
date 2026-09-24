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
  # Built here rather than on the installer: none is on cache.nixos.org, and
  # each fetches from its own server while it builds (the Rust toolchain and
  # crates.io, proxy.golang.org, GitHub), where one dropped download stopped
  # an install at phase 3. They depend on the platform, not on the site, so
  # the example server with Secure Boot on names the same derivations.
  sample = (self.lib.mkSite ../examples/site/site.nix).nixosConfigurations.server.extendModules {
    modules = [ { nixie.security.secureBoot.enable = true; } ];
  };
  web = import ./nixie-web.nix { inherit (sample) pkgs; };
  prebuilt = [
    sample.config.boot.lanzaboote.package
    sample.config.sops.package
    web.archivo
    # Its npm packages: the web build on the installer is then offline.
    web.web.npmDeps
  ];
  iso = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs.nixieVersion = self.lib.version;
    modules = [
      ../installer/iso.nix
      {
        nixie.installer.packages = packages;
        nixpkgs.pkgs = pkgs;
        system.extraDependencies = sources ++ prebuilt;
      }
    ]
    ++ extraModules;
  };
in
# The configuration rides along for checks.iso-config.
iso.config.system.build.isoImage // { inherit (iso) config; }
