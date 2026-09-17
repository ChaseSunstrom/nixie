# Installs the example server with every boot-time security feature on, from
# an installer VM onto a blank disk, then boots the disk under OVMF (Secure
# Boot capable, Setup Mode) with swtpm, and walks phases 4 to 7 exactly as a
# front end would: remote unlock over SSH, Secure Boot enrolment, TPM + PIN
# enrolment, attestation, verification, and finally the duress passphrase.
{
  pkgs,
  inputs,
  nixieLib,
  exampleSite,
  nixieInstaller,
  nixieCli,
}:
let
  template = import ../../lib/template.nix pkgs.lib;
  inherit (pkgs) lib;
  clientKey = ../keys/client_ed25519;
  clientPub = lib.fileContents ../keys/client_ed25519.pub;

  # The system that ends up on the disk. Not a test node: it boots from its
  # own boot loader with its own initrd. test-instrumentation adds the
  # backdoor the driver talks to.
  target = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {
      inherit inputs;
    };
    modules = nixieLib.hostModules ../../examples/site "server" exampleSite.hosts.server ++ [
      "${inputs.nixpkgs}/nixos/modules/testing/test-instrumentation.nix"
      (
        { lib, ... }:
        {
          nixie.security = {
            encryption.enable = true;
            tpm.enable = true;
            attestation.enable = true;
            duress.enable = true;
            remoteUnlock.enable = true;
            secureBoot.enable = true;
          };
          nixie.auth.sshKeys = [ clientPub ];
          # Auto-enrolment stages a systemd-boot key-enrol EFI that, in this
          # OVMF, enrols the keys and reboots but then cannot complete a
          # Secure Boot verified boot of the signed loader, hanging the VM.
          # lanzaboote still signs the whole chain; we assert that instead.
          boot.lanzaboote.autoEnrollKeys.enable = lib.mkForce false;
          # Node "target" is the third node, so the framework gives it this
          # address and hardware address on the test network.
          nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:03" ];
          nixie.network.address = "192.168.1.3/24";
          nixie.disks.system = lib.mkForce "/dev/vda";
          boot.initrd.availableKernelModules = [ "virtio_net" ];
          # Prompts must land on the serial console the driver reads and types on.
          boot.kernelParams = lib.mkAfter [ "console=ttyS0" ];
          environment.systemPackages = [
            nixieInstaller
            nixieCli
            pkgs.sbsigntool
            pkgs.age # the test decrypts the header backup to verify it
          ];
        }
      )
    ];
  };
  inherit (target.config.system.build) toplevel;
  disko = target.config.system.build.diskoScript;

  state = pkgs.writeText "state.json" (
    builtins.toJSON {
      host = "server";
      profile = "server";
      systemDisk = "/dev/vda";
      dataDisk = null;
      uplinks = [ "52:54:00:12:01:03" ];
      gpu = "none";
      tpm = true;
      hostId = "8425e349";
      options.secureBoot = true;
    }
  );
  siteSrc = lib.cleanSource ../../examples/site;

  # Both VMs use one disk.
  shared = {
    # Relative paths resolve inside each node's own state directory; one level
    # up is the driver's directory, which both nodes share.
    virtualisation.diskImage = "../target.qcow2";
    virtualisation.diskSize = 8 * 1024;
    virtualisation.memorySize = 3072;
    virtualisation.cores = 4;
    virtualisation.useEFIBoot = true;
    virtualisation.useSecureBoot = true;
    virtualisation.tpm.enable = true;
  };
in
pkgs.testers.runNixOSTest {
  name = "vm-encryption";
  nodes = {
    client = {
      environment.systemPackages = [ pkgs.openssh ];
    };
    installer = {
      imports = [ shared ];
      # The installer's own root lives on a second small disk so the target
      # disk is /dev/vda both during and after the install.
      virtualisation.emptyDiskImages = [ 1024 ];
      # Drive order: target disk, then this empty disk.
      virtualisation.rootDevice = "/dev/vdb";
      virtualisation.fileSystems."/".autoFormat = true;
      # nixos-install copies the closure out of this store by hash, and the
      # path registration at boot needs the store to be writable.
      virtualisation.writableStore = true;
      boot.supportedFilesystems.zfs = true;
      networking.hostId = "deadbeef";
      environment.systemPackages = [
        nixieInstaller
        pkgs.cryptsetup
      ];
      # Registered in the installer's own store, so
      # nixos-install can copy them by hash.
      system.extraDependencies = [
        toplevel
        disko
        siteSrc
      ];
      virtualisation.efi.keepVariables = false;
    };
    target = {
      imports = [ shared ];
      virtualisation.useBootLoader = true;
      virtualisation.useDefaultFilesystems = false;
      virtualisation.efi.keepVariables = false;
      virtualisation.fileSystems."/" = {
        device = "/dev/disk/by-label/never-used";
        fsType = "ext4";
      };
    };
  };

  testScript = template.fill ./encryption.py {
    inherit clientKey;
    inherit disko;
    keys_example_host_age = ../keys/example-host.age;
    inherit siteSrc;
    inherit state;
    inherit toplevel;
  };
}
