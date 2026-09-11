# Everything that exists only on a desktop.
{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf (config.nixie.profile == "desktop") {
    networking.networkmanager.enable = true;
  };
}
