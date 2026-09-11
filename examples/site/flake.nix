{
  description = "Example Nixie site: one server with generic guests";
  # Inside the platform repo, build with: --override-input nixie path:../..
  inputs.nixie.url = "github:OWNER/nixie";
  outputs = { nixie, ... }: nixie.lib.mkSite ./site.nix;
}
