{ self }:
{ config, lib, ... }:
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
  # What `nixie apply` pushes to, read at run time.
  config.environment.etc."nixie/site.json".text = builtins.toJSON {
    inherit (config.nixie.site) repo ref;
  };
  # The checkout is root's; the administrator can still read its history.
  config.programs.git = {
    enable = true;
    config.safe.directory = [ (toString config.nixie.site.path) ];
  };

  options.nixie.site = {
    repo = mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        A git repository that keeps a copy of the site. `nixie apply` pulls
        from it before building and pushes each change it applied, hand edits
        included, so the repository is the site's backup and its history.
        Give the repository write access for the key `nixie site key` prints.
        Empty means the checkout on this host is the only copy.
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
