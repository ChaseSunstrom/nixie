# A site with more than one machine: what the control panel's Machines page
# lists, and the only place `lib.mkSite` derives that list from.
{
  hosts.alpha = {
    secrets = ../../../examples/site/secrets/server.yaml;
    hardware = {
      nixie.disks.system = "/dev/disk/by-id/ata-generic";
      nixie.network.bridge.uplinks = [ "52:54:00:00:00:10" ];
      nixie.hardware.tpm = true;
      networking.hostId = "00000010";
    };
    settings = {
      nixie.profile = "server";
      nixie.auth.admin.name = "admin";
      nixie.network.address = "192.0.2.10/24";
    };
  };
  hosts.beta = {
    secrets = ../../../examples/desktop-site/secrets/laptop.yaml;
    hardware = {
      nixie.disks.system = "/dev/disk/by-id/ata-generic";
      nixie.network.bridge.uplinks = [ "52:54:00:00:00:11" ];
      networking.hostId = "00000011";
    };
    settings = {
      nixie.profile = "desktop";
      nixie.auth.admin.name = "me";
    };
  };
}
