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
    # Chosen without HyDE itself in the site, it left a desktop that started
    # to a text login and nothing said why.
    assertions = [
      {
        assertion =
          !config.nixie.desktop.hyde.enable
          || config.services.displayManager.enable
          || config.services.greetd.enable;
        message = "nixie.desktop.hyde.enable hands the desktop to HyDE, but nothing in this site starts a graphical session: import HyDE (the hydenix flake) in the site, or turn the option off to use the Nixie desktop";
      }
    ];
  };
}
