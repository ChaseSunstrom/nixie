{
  hosts.server = {
    hardware = ./hosts/server/hardware.nix;
    secrets = ./secrets/server.yaml;
    guests = import ./guests.nix;
    data = import ./data.nix;
    settings = {
      nixie.profile = "server";
      nixie.auth.admin.name = "admin";
      nixie.auth.sshKeys = [ ];
    };
  };
}
