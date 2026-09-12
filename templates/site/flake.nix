{
  description = "My Nixie site";
  inputs.nixie.url = "github:OWNER/nixie";
  # The commit labels each generation the host builds from this site.
  outputs =
    { self, nixie, ... }:
    nixie.lib.mkSite {
      site = ./site.nix;
      rev = self.shortRev or self.dirtyShortRev or null;
    };
}
