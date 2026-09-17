# Media: the boot chain on screen. The splash with the attestation code, the
# PIN and the passphrase of an installed, fully enabled system, plus
# screendump frames at 10 fps of one boot for a short video.
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
            # The prompts are answered over the initrd's SSH, the way
            # vm-encryption does it, while the splash shows them for the
            # pictures (vm-splash types into the splash itself).
            remoteUnlock.enable = true;
          };
          nixie.auth.sshKeys = [ clientPub ];
          # The client node is first, so the target is machine 3: its interface
          # is 52:54:00:12:01:03 and the initrd needs the address statically,
          # there being no DHCP server in the test network.
          nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:03" ];
          nixie.network.address = "192.168.1.3/24";
          # The committed hardware.nix of the example site lists storage
          # drivers only; on a real install phase 1 adds the wired ports'
          # drivers, without which the initrd's SSH has no network to listen
          # on and the passphrase can never be answered.
          boot.initrd.availableKernelModules = lib.mkAfter [ "virtio_net" ];
          nixie.disks.system = lib.mkForce "/dev/vda";
          # The serial console, last so it is /dev/console, carries the
          # agent's notes the pictures are timed by; the splash is on the screen.
          boot.kernelParams = lib.mkAfter [
            "console=ttyS0"
            "loglevel=7"
            # Or Plymouth shows its text view everywhere, the screen included.
            "plymouth.ignore-serial-consoles"
          ];
          environment.systemPackages = [
            nixieInstaller
            nixieCli
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
      uplinks = [ "52:54:00:12:01:02" ];
      gpu = "none";
      tpm = true;
      hostId = "8425e349";
      options.secureBoot = false;
    }
  );
  siteSrc = lib.cleanSource ../../examples/site;
  shared = {
    # Relative paths resolve inside each node's own state directory; one level
    # up is the driver's directory, which both nodes share.
    virtualisation.diskImage = "../target.qcow2";
    virtualisation.diskSize = 8 * 1024;
    virtualisation.memorySize = 3072;
    virtualisation.cores = 4;
    virtualisation.useEFIBoot = true;
    virtualisation.tpm.enable = true;
    virtualisation.resolution = {
      x = 1280;
      y = 800;
    };
  };
in
pkgs.testers.runNixOSTest {
  name = "media-boot";
  nodes = {
    client = {
      environment.systemPackages = [ pkgs.openssh ];
    };
    installer = {
      imports = [ shared ];
      virtualisation.emptyDiskImages = [ 1024 ];
      virtualisation.rootDevice = "/dev/vdb";
      virtualisation.fileSystems."/".autoFormat = true;
      # nixos-install copies the closure out of this store by hash, and the
      # path registration at boot needs the store to be writable.
      virtualisation.writableStore = true;
      boot.supportedFilesystems.zfs = true;
      networking.hostId = "deadbeef";
      environment.systemPackages = [ nixieInstaller ];
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
  testScript = template.fill ./boot.py {
    inherit clientKey;
    inherit disko;
    keys_example_host_age = ../keys/example-host.age;
    inherit siteSrc;
    inherit state;
    inherit toplevel;
  };
}
