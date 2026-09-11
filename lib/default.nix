{ inputs, self }:
{
  inherit (import ./mk-site.nix { inherit inputs self; }) mkSite hostModules;
}
