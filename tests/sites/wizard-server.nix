# Everything the installer's wizard offers a server, turned on at once: each
# of these once stopped an install at phase 3 on its own.
{
  hosts.host = {
    secrets = ../../examples/site/secrets/server.yaml;
    hardware = {
      nixie.disks.system = "/dev/disk/by-id/virtio-generic";
      nixie.network.bridge.uplinks = [ "52:54:00:00:00:07" ];
      nixie.hardware.gpu = "none";
      nixie.hardware.tpm = true;
      networking.hostId = "00000007";
    };
    settings = {
      imports = [ { nixie.setup.pending = true; } ];
      nixie.profile = "server";
      nixie.auth.admin.name = "admin";
      nixie.auth.sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHV0ZXN0a2V5dGVzdGtleXRlc3RrZXl0ZXN0a2V5dGVz test"
      ];
      nixie.auth.secondFactor = "totp";
      nixie.auth.ssh.passwordLogin = true;
      nixie.security.encryption.enable = true;
      nixie.security.tpm.enable = true;
      nixie.security.tpm.pcrs = [
        7
        11
      ];
      nixie.security.attestation.enable = true;
      nixie.security.duress.enable = true;
      nixie.security.remoteUnlock.enable = true;
      nixie.security.secureBoot.enable = true;
      nixie.security.hardening.usbguard.enable = true;
      nixie.security.hardening.memoryEncryption.enable = true;
      nixie.security.hardening.remoteJournal.enable = true;
      nixie.security.hardening.remoteJournal.url = "https://logs.example:19532";
      nixie.host.timezone = "Europe/Berlin";
      nixie.network.address = "192.168.1.10/24";
      nixie.network.gateway = "192.168.1.1";
      nixie.network.dns = [ "192.168.1.1" ];
      nixie.network.bridge.mode = "managed-nat";
      nixie.network.bridge.vlanAware = true;
      nixie.network.tailscale.enable = true;
      nixie.network.tailscale.authKeyFile = "/var/lib/nixie/tailscale.key";
      nixie.network.egress = "exit-node";
      nixie.network.exitNode = "exit";
      nixie.network.exitNodeAllowLan = true;
      nixie.incus.ui.listen = "lan+tailnet";
      nixie.ui.theme = "umber";
    };
  };
}
