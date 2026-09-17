# A boot splash theme from a directory of its own, as a flake input pointing
# at any theme repository would bring it, on a host with every prompt.
{
  hosts.host = {
    secrets = ../../examples/site/secrets/server.yaml;
    hardware = {
      nixie.disks.system = "/dev/disk/by-id/ata-generic";
      nixie.network.bridge.uplinks = [ "52:54:00:00:00:08" ];
      nixie.hardware.gpu = "none";
      nixie.hardware.tpm = true;
      networking.hostId = "00000008";
    };
    settings = {
      nixie.profile = "server";
      nixie.auth.admin.name = "admin";
      nixie.security.encryption.enable = true;
      nixie.security.tpm.enable = true;
      nixie.security.attestation.enable = true;
      nixie.security.duress.enable = true;
      nixie.host.splashTheme = {
        name = "demo";
        source = ./splash-theme-source;
      };
    };
  };
}
