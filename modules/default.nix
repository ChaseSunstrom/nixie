# The whole `nixie.*` option tree. Each file below owns one concern and is a
# plain NixOS module a site can override.
{ inputs }:
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops
    inputs.lanzaboote.nixosModules.lanzaboote
    ./base.nix
    ./profile.nix
    ./hardware.nix
    ./host.nix
    ./auth.nix
    ./disks.nix
    ./security
    ./network
    ./incus.nix
    ./guests.nix
    ./data.nix
    ./backups.nix
    ./monitoring.nix
    ./ui.nix
    ./secrets.nix
    ./site.nix
    ./host-ui.nix
    ./setup.nix
    ./desktop
  ];
}
