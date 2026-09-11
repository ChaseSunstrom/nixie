# Written by the installer (phase 1) for a QEMU virtual machine.
{
  nixie.disks.system = "/dev/disk/by-id/virtio-nixie-system";
  nixie.network.bridge.uplinks = [ "52:54:00:12:34:57" ];
  nixie.hardware.gpu = "none";
  nixie.hardware.tpm = true;
  networking.hostId = "d1f0c2a1";
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "xhci_pci"
    "nvme"
    "usbhid"
  ];
}
