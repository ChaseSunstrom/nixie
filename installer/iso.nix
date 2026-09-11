# The bootable installer image: the minimal NixOS CD plus the installer system.
{
  modulesPath,
  lib,
  ...
}:
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ./installer-system.nix
  ];
  isoImage.isoName = lib.mkForce "nixie.iso";
  isoImage.volumeID = "NIXIE";
  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;
  # The ISO is a UEFI-only platform; there is nothing to gain from BIOS boot.
  isoImage.makeBiosBootable = false;
  networking.hostName = "nixie-installer";
  # The CD profile enables things a kiosk installer has no use for.
  services.getty.autologinUser = lib.mkForce null;
  documentation.enable = false;
}
