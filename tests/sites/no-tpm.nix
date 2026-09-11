{
  hosts.host = {
    secrets = ../../examples/site/secrets/server.yaml;
    hardware = {
      nixie.disks.system = "/dev/disk/by-id/ata-generic";
      nixie.network.bridge.uplinks = [ "52:54:00:00:00:04" ];
      nixie.hardware.gpu = "amd";
      nixie.hardware.tpm = false;
      networking.hostId = "00000003";
    };
    settings = {
      nixie.profile = "server";
      nixie.auth.admin.name = "admin";
      nixie.security.encryption.enable = true;
    };
  };
}
