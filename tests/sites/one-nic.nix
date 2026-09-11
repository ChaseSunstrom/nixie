{
  hosts.host = {
    secrets = ../../examples/site/secrets/server.yaml;
    hardware = {
      nixie.disks.system = "/dev/disk/by-id/nvme-generic";
      nixie.network.bridge.uplinks = [ "52:54:00:00:00:03" ];
      nixie.hardware.gpu = "nvidia";
      nixie.hardware.tpm = true;
      networking.hostId = "00000002";
    };
    settings = {
      nixie.profile = "server";
      nixie.auth.admin.name = "admin";
    };
  };
}
