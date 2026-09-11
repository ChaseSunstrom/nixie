{ lib, ... }:
let
  inherit (import ../lib/option.nix lib) mkOption;
in
{
  options.nixie.ui = {
    theme = mkOption {
      type = lib.types.enum [
        "graphite"
        "umber"
        "paper"
      ];
      default = "graphite";
      description = ''
        The finish used by the control panel and the installer. Graphite and
        Umber are dark; Paper is light. On a desktop the same finish colours
        the whole environment.
      '';
      nixieUi = {
        section = "desktop";
        order = 0;
      };
    };
    tokens = mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "A JSON file overriding any design token, for a site that wants its own colours.";
    };
    links = mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            label = mkOption {
              type = lib.types.str;
              description = "Text shown in the navigation.";
            };
            url = mkOption {
              type = lib.types.str;
              description = "Where the entry leads.";
            };
          };
        }
      );
      default = [ ];
      description = "Extra entries in the control panel navigation, for a site's own pages.";
    };
    allowSiteEdits = mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Let the control panel commit to the site checkout on this host
        ("Declare") and run `nixie apply`. Off means the panel can only show
        you text to paste into the site yourself.
      '';
    };
  };
}
