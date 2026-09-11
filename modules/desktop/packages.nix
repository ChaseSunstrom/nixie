# Package categories with curated defaults; the installer offers each with a
# search box over nixpkgs and writes the choice into the site as a list.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixie.desktop;
  defaults = {
    browsers = [ "firefox" ];
    terminals = [
      "kitty"
      "fish"
      "starship"
    ];
    editors = [
      "neovim"
      "vscodium"
      "git"
      "gh"
    ];
    media = [
      "mpv"
      "imv"
      "pavucontrol"
    ];
    office = [
      "libreoffice"
      "evince"
    ];
    communication = [ "signal-desktop" ];
    gaming = [ ];
    creative = [ "gimp" ];
  };
  chosen = lib.concatLists (
    lib.mapAttrsToList (
      c: d: if cfg.packages.categories.${c} == [ ] then d else cfg.packages.categories.${c}
    ) defaults
  );
  resolve =
    name:
    lib.attrByPath (lib.splitString "." name) (throw "nixie.desktop.packages: no package named ${name}")
      pkgs;
in
{
  options.nixie.desktop.packages.defaults = lib.mkOption {
    type = lib.types.attrsOf (lib.types.listOf lib.types.str);
    default = defaults;
    readOnly = true;
    description = "Internal: the curated default set per category, shown by the installer.";
  };
  config = lib.mkIf cfg.enable {
    environment.systemPackages = map resolve (lib.unique chosen) ++ cfg.packages.extra;
    programs.fish.enable = lib.mkIf (lib.elem "fish" chosen) true;
  };
}
