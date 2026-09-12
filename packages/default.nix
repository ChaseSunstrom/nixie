# Platform packages. Each lands in the slice that needs it.
{
  pkgs,
  inputs,
  self,
}:
let
  web = import ./nixie-web.nix { inherit pkgs; };
  installer = import ./nixie-installer.nix { inherit pkgs; };
in
rec {
  nixie-installer = installer;
  nixie-cli = import ./nixie-cli.nix { inherit pkgs; };
  nixie-panel = import ./nixie-panel.nix { inherit pkgs; };
  nixie-cockpit = import ./nixie-cockpit.nix { inherit pkgs; };
  inherit (web) nixie-ui nixie-setup-web;
  nixie-setup = import ./nixie-setup.nix { inherit pkgs inputs self; };
  deploy = import ./deploy.nix { inherit pkgs; };
  nixie-iso = import ./nixie-iso.nix {
    inherit pkgs inputs self;
    packages = {
      inherit
        nixie-installer
        nixie-setup
        nixie-cli
        deploy
        ;
    };
  };
  test-iso = import ./test-iso.nix { inherit pkgs nixie-iso; };
  docs = import ./docs.nix { inherit pkgs nixie-setup; };
  media = import ./media.nix { inherit pkgs; };
}
