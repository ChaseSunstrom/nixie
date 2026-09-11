{
  hosts.laptop = {
    hardware = ./hosts/laptop/hardware.nix;
    secrets = ./secrets/laptop.yaml;
    settings = {
      nixie.profile = "desktop";
      nixie.auth.admin.name = "me";
      nixie.desktop.finish = "umber";
    };
  };
}
