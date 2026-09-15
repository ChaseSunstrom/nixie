{ self }:
{ lib, ... }:
let
  inherit (import ../lib/option.nix lib) mkOption;
in
{
  # A site started on the installer names the platform by its store path, and
  # `nixie apply` evaluates that site here, often offline; keeping the source
  # in the system closure keeps the path valid. It also resolves
  # `nix run nixie#deploy`.
  config.nix.registry.nixie.to = {
    type = "path";
    path = self.outPath;
  };

  options.nixie.site = {
    repo = mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Git URL of the site repository. When set, `nixie apply` pulls it
        before building; when empty, the checkout on the host is the only
        copy.
      '';
      nixieUi = {
        section = "site";
        order = 0;
      };
    };
    ref = mkOption {
      type = lib.types.str;
      default = "main";
      description = "Branch of the site repository to follow.";
      nixieUi = {
        section = "site";
        order = 1;
      };
    };
    path = mkOption {
      type = lib.types.path;
      default = "/etc/nixie/site";
      description = "Where the site checkout lives on this host. `nixie apply` runs from here.";
    };
  };
}
