# Everything the installer's wizard offers a desktop, turned on at once,
# including packages with an unfree licence chosen by name. HyDE is left out:
# it replaces the desktop these settings configure.
{
  hosts.host = {
    secrets = ../../examples/desktop-site/secrets/laptop.yaml;
    hardware = {
      nixie.disks.system = "/dev/disk/by-id/virtio-generic";
      nixie.hardware.gpu = "none";
      nixie.hardware.tpm = true;
      networking.hostId = "00000008";
    };
    settings = {
      imports = [ { nixie.setup.pending = true; } ];
      nixie.profile = "desktop";
      nixie.auth.admin.name = "me";
      nixie.auth.sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHV0ZXN0a2V5dGVzdGtleXRlc3RrZXl0ZXN0a2V5dGVz test"
      ];
      nixie.auth.secondFactor = "totp";
      nixie.security.encryption.enable = true;
      nixie.security.tpm.enable = true;
      nixie.security.attestation.enable = true;
      # Without duress, whose own shell for remote unlock hid a conflict.
      nixie.security.remoteUnlock.enable = true;
      nixie.security.secureBoot.enable = true;
      nixie.security.hardening.usbguard.enable = true;
      nixie.network.tailscale.enable = true;
      nixie.desktop.finish = "paper";
      nixie.desktop.flatpak.enable = true;
      nixie.desktop.keyboard.layout = "de";
      nixie.desktop.keyboard.variant = "nodeadkeys";
      nixie.desktop.wallpaper = "/etc/nixie/wall.png";
      nixie.desktop.packages.categories.gaming = [ "steam" ];
      nixie.desktop.packages.categories.editors = [
        "vscode"
        "git"
      ];
    };
  };
}
