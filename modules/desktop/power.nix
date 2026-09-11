# Laptop and power: profiles, lid and idle, battery.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixie.desktop;
in
{
  config = lib.mkIf cfg.enable {
    services.power-profiles-daemon.enable = cfg.power.backend == "power-profiles-daemon";
    services.tlp.enable = cfg.power.backend == "tlp";
    services.upower.enable = true;
    services.logind.settings.Login = {
      HandleLidSwitch =
        if cfg.power.lid == "suspend" then
          "suspend"
        else if cfg.power.lid == "lock" then
          "lock"
        else
          "ignore";
      HandleLidSwitchExternalPower = if cfg.power.lid == "suspend" then "suspend" else "ignore";
    };
  };
}
