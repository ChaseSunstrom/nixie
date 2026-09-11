{
  hosts.host = {
    secrets = ../../examples/site/secrets/server.yaml;
    hardware = {
      nixie.disks.system = "/dev/disk/by-id/ata-generic";
      nixie.network.bridge.uplinks = [ "52:54:00:00:00:05" ];
      nixie.hardware.gpu = "intel";
      nixie.hardware.tpm = true;
      networking.hostId = "00000004";
    };
    settings = {
      nixie.profile = "desktop";
      nixie.auth.admin.name = "me";
      nixie.security.encryption.enable = true;
      nixie.security.tpm.enable = true;
    };
  };
}
