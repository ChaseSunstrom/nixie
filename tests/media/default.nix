# Media runs: slow VM tests that produce screenshots, videos and recordings
# for docs/media. Not checks; `nix run .#media` builds them by name.
{
  pkgs,
  self,
  inputs,
}:
let
  nixieLib = import ../../lib { inherit inputs self; };
  exampleSite = import ../../examples/site/site.nix;
  desktopSite = import ../../examples/desktop-site/site.nix;
  nixieCli = self.packages.x86_64-linux.nixie-cli;
in
{
  panel = import ./panel.nix {
    inherit
      pkgs
      nixieLib
      exampleSite
      nixieCli
      ;
  };
  desktop = import ./desktop.nix { inherit pkgs nixieLib desktopSite; };
  guests = import ./guests.nix {
    inherit
      pkgs
      nixieLib
      exampleSite
      nixieCli
      ;
  };
  installer = import ./installer.nix {
    inherit
      pkgs
      inputs
      self
      nixieLib
      exampleSite
      ;
  };
  boot = import ./boot.nix {
    inherit
      pkgs
      inputs
      nixieLib
      exampleSite
      nixieCli
      ;
    nixieInstaller = self.packages.x86_64-linux.nixie-installer;
  };
  console = self.checks.x86_64-linux.vm-console;
}
