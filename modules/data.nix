{ lib, ... }:
let
  inherit (import ../lib/option.nix lib) mkOption;
in
{
  options.nixie.data = {
    root = mkOption {
      type = lib.types.path;
      default = "/data";
      description = ''
        Where state/, cache/ and media/ live. state/ is irreplaceable and is
        backed up. cache/ is never backed up because `nixie fetch` can rebuild
        it from the manifest. They never share a directory.
      '';
    };
    mediaBackup = mkOption {
      type = lib.types.bool;
      default = false;
      description = "Include media/ in backups. It can be large.";
    };
    manifest = mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf (lib.types.attrsOf lib.types.anything));
      default = { };
      description = "What lives in cache/, by fetcher kind and name. See the data guide.";
    };
    fetch.timer = mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "daily";
      description = "Also run `nixie fetch` on this schedule.";
    };
    kinds = mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = "Extra fetcher kinds provided by the site, name to file.";
    };
  };
}
