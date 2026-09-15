# Everything that exists only on a server. Gated on the profile so the desktop
# closure never pulls it in.
{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf (config.nixie.profile == "server") {
    nixie.security.hardening.usbguard.enable = lib.mkDefault true;
  };
}
