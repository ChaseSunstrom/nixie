# site.nix -> flake outputs. A site is data; this is the only wiring.
{ inputs, self }:
let
  inherit (inputs.nixpkgs) lib;
  system = "x86_64-linux";

  hostModules = name: host: [
    self.nixosModules.nixie
    host.hardware
    host.settings
    {
      nixie.host.name = lib.mkDefault name;
      nixie.guests = host.guests or { };
      nixie.data.manifest = host.data or { };
      nixie.secrets.file = host.secrets or null;
    }
  ];

  mkHost =
    name: host:
    lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
      };
      modules = hostModules name host;
    };

  mkSite =
    sitePath:
    let
      site = import sitePath;
      hosts = lib.mapAttrs mkHost site.hosts;
    in
    {
      nixosConfigurations = hosts;
      packages.${system} = lib.mapAttrs' (
        n: h: lib.nameValuePair "${n}-vm" h.config.system.build.vm
      ) hosts;
      checks.${system} = lib.mapAttrs' (
        n: h: lib.nameValuePair "${n}-eval" h.config.system.build.toplevel
      ) hosts;
    };
in
{
  inherit mkSite hostModules;
}
