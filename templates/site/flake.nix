{
  description = "My Nixie site";
  inputs.nixie.url = "github:OWNER/nixie";
  outputs = { nixie, ... }: nixie.lib.mkSite ./site.nix;
}
