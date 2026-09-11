{
  hosts.host = {
    secrets = ../../examples/site/secrets/server.yaml;
    hardware = {
      nixie.disks.system = "/dev/disk/by-id/ata-generic";
      nixie.disks.data = "/dev/disk/by-id/ata-generic-data";
      nixie.network.bridge.uplinks = [
        "52:54:00:00:00:01"
        "52:54:00:00:00:02"
      ];
      nixie.hardware.gpu = "none";
      nixie.hardware.tpm = true;
      networking.hostId = "00000001";
    };
    settings = {
      nixie.profile = "server";
      nixie.auth.admin.name = "admin";
    };
  };
}
