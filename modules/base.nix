# Settings every Nixie host shares regardless of profile.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  # A site is applied with `nixie apply`, never by hand-editing channels.
  nix.channel.enable = false;

  boot.initrd.systemd.enable = true;
  boot.loader.systemd-boot.enable = lib.mkDefault (!config.boot.lanzaboote.enable);
  boot.loader.efi.canTouchEfiVariables = true;
  # Setup selects the setup generation with `bootctl set-default`; keeping the
  # editor off stops a console user from changing kernel parameters.
  boot.loader.systemd-boot.editor = false;

  time.timeZone = config.nixie.host.timezone;
  networking.hostName = config.nixie.host.name;

  environment.defaultPackages = lib.mkDefault [ ];
  documentation.nixos.enable = lib.mkDefault false;

  # Guest tarballs and the site checkout are the only things that need git on
  # the host; keeping it in the base means `nixie apply` works on both profiles.
  environment.systemPackages = [ pkgs.git ];

  system.stateVersion = lib.mkDefault "26.05";
}
