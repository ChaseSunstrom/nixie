# Everything that exists only on a desktop.
{
  config,
  lib,
  ...
}:
{
  imports = [
    ../modules/desktop/session.nix
    ../modules/desktop/hyprland.nix
    ../modules/desktop/shell.nix
    ../modules/desktop/theme.nix
    ../modules/desktop/packages.nix
    ../modules/desktop/power.nix
    ../modules/desktop/menu.nix
  ];
  config = lib.mkIf (config.nixie.profile == "desktop") {
    networking.networkmanager.enable = true;
    # With nixie.desktop.hyde.enable the site's own HyDE owns the session, so
    # every Nixie desktop module stands down; nothing else about the host
    # changes.
    nixie.desktop.enable = !config.nixie.desktop.hyde.enable;
  };
}
