{
  hosts.host = {
    secrets = ../../examples/site/secrets/server.yaml;
    hardware = {
      nixie.disks.system = "/dev/disk/by-id/virtio-generic";
      nixie.network.bridge.uplinks = [ "52:54:00:00:00:06" ];
      nixie.hardware.gpu = "none";
      nixie.hardware.tpm = false;
      networking.hostId = "00000005";
    };
    settings = {
      nixie.profile = "server";
      nixie.auth.admin.name = "admin";
    };
  };
}
