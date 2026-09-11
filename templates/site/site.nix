# Plain data. One entry per machine.
{
  hosts.example = {
    hardware = ./hosts/example/hardware.nix; # written by the installer
    secrets = ./secrets/example.yaml; # sops; admin-password at least
    guests = import ./guests.nix;
    data = import ./data.nix;
    settings = {
      nixie.profile = "server";
      nixie.auth.admin.name = "admin";
      nixie.auth.sshKeys = [ ];
      nixie.security.encryption.enable = true;
    };
  };
}
