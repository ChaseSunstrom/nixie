{
  description = "My Nixie site";
  inputs.nixie.url = "github:OWNER/nixie";
  # HyDE instead of the Nixie desktop (nixie.desktop.hyde.enable): the
  # installer adds these two lines when HyDE is chosen.
  # inputs.hydenix.url = "github:richen604/hydenix/55370cd2ab2361bf0066e3bc89987b1717381c6d";
  # inputs.hydenix.inputs.nixpkgs.follows = "nixie/nixpkgs";
  # The commit labels each generation the host builds from this site, and the
  # site's inputs reach its hosts' modules as `inputs`.
  outputs =
    { self, nixie, ... }@inputs:
    nixie.lib.mkSite {
      site = ./site.nix;
      rev = self.shortRev or self.dirtyShortRev or null;
      inherit inputs;
    };
}
