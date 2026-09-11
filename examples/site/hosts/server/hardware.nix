# Written by the installer (phase 1) for a QEMU virtual machine. Hardware
# facts only; nothing here is platform policy.
{
  nixie.disks.system = "/dev/disk/by-id/virtio-nixie-system";
  nixie.disks.data = null;
  nixie.network.bridge.uplinks = [ "52:54:00:12:34:56" ];
  nixie.hardware.gpu = "none";
  nixie.hardware.tpm = true;
  networking.hostId = "8425e349";
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "sd_mod"
  ];
}
