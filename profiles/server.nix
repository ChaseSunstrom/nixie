# Everything that exists only on a server. Gated on the profile so the desktop
# closure never pulls it in.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf (config.nixie.profile == "server") {
    nixie.security.hardening.usbguard.enable = lib.mkDefault true;
    # `nixie apply`, `rollback`, `doctor` and the front panel's actions. It
    # carries the Incus client and OpenTofu, so the desktop profile does not
    # get it this way.
    environment.systemPackages = [ (import ../packages/nixie-cli.nix { inherit pkgs; }) ];
  };
}
