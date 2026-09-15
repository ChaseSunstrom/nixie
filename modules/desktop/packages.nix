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
  picked = lib.concatLists (lib.attrValues cfg.packages.categories);
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
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      environment.systemPackages = map resolve (lib.unique chosen) ++ cfg.packages.extra;
      programs.fish.enable = lib.mkIf (lib.elem "fish" chosen) true;
      # Steam needs its 32-bit graphics stack, which only the program module sets up.
      programs.steam.enable = lib.mkIf (lib.elem "steam" chosen) true;
      programs.starship = {
        enable = true;
        settings = { };
      };
      # The prompt and the greeting read the finish's colours from /etc/xdg.
      environment.variables.STARSHIP_CONFIG = "/etc/xdg/starship.toml";
      programs.fish.interactiveShellInit = lib.mkIf cfg.terminal.greeting ''
        set -g fish_greeting
        if status is-interactive; and test -z "$NIXIE_NO_GREETING"
          fastfetch --config /etc/xdg/fastfetch/config.jsonc
        end
      '';
      programs.bash.interactiveShellInit = lib.mkIf cfg.terminal.greeting ''
        [ -n "$NIXIE_NO_GREETING" ] || [ ! -t 1 ] || fastfetch --config /etc/xdg/fastfetch/config.jsonc
      '';
    })
    # HyDE brings its own terminal, shell and editor, so the curated defaults
    # stay out; what the installer's Apps picked still installs.
    (lib.mkIf (config.nixie.profile == "desktop" && cfg.hyde.enable) {
      environment.systemPackages = map resolve (lib.unique picked) ++ cfg.packages.extra;
      programs.steam.enable = lib.mkIf (lib.elem "steam" picked) true;
    })
  ];
}
