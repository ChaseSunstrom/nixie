# The whole `nixie.*` option tree. Each file below owns one concern and is a
# plain NixOS module a site can override.
{ inputs, self }:
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops
    inputs.lanzaboote.nixosModules.lanzaboote
    ./base.nix
    ./splash.nix
    ./profile.nix
    ./hardware.nix
    ./host.nix
    ./auth.nix
    ./disks.nix
    ./security
    ./network
    (import ./incus.nix { inherit (inputs) terranix; })
    ./guests.nix
    ./data.nix
    ./backups.nix
    ./monitoring.nix
    ./ui.nix
    ./secrets.nix
    (import ./site.nix { inherit self; })
    ./updates.nix
    ./host-ui.nix
    ./console.nix
    (import ./setup.nix { inherit inputs self; })
    ./desktop
  ];
}
