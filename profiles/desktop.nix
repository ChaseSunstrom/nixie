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
    nixie.desktop.enable = true;
  };
}
