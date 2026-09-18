{
  description = "Nixie: one installer, a hardened Incus server profile and a Hyprland desktop profile";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    terranix = {
      url = "github:terranix/terranix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      nixieLib = import ./lib { inherit inputs self; };
    in
    {
      nixosModules.nixie = import ./modules { inherit inputs self; };
      lib = {
        inherit (nixieLib) mkSite;
        # The wizard renders any option carrying `nixieUi`, and nixpkgs'
        # own mkOption refuses an argument it does not know, so a site that
        # wants an option of its own in the installer declares it with this
        # one (docs/extending.md). Its modules reach it as
        # `inputs.nixie.lib.mkOption`.
        inherit (import ./lib/option.nix inputs.nixpkgs.lib) mkOption;
        version = "0.1.0";
      };
      templates.site = {
        path = ./templates/site;
        description = "A Nixie site: hosts, guests, data manifest and secrets";
      };
      packages.${system} = import ./packages { inherit pkgs self inputs; };
      checks.${system} = import ./tests { inherit pkgs self inputs; };
      # Slow media runs; see packages.media.
      mediaTests.${system} = import ./tests/media { inherit pkgs self inputs; };
      formatter.${system} = pkgs.nixfmt;
    };
}
