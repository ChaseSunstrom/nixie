# The boot splash on a machine with every prompt: the attestation code, the
# TPM PIN (a wrong one first), a security key's PIN, and finally the duress
# passphrase, all typed on the keyboard into the splash the way a person at
# the machine does, with nothing relayed over SSH. The security key is
# QEMU's CanoKey, which confirms presence by itself.
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
            fido2.enable = true;
          };
          nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:02" ];
          nixie.disks.system = lib.mkForce "/dev/vda";
          # The splash stays on the screen; the serial console, last so it is
          # /dev/console, carries the attestation code and the agent's notes
          # for the driver to wait on.
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
    virtualisation.efi.keepVariables = false;
  };
in
pkgs.testers.runNixOSTest {
  name = "vm-splash";
  enableOCR = true;
  qemu.package = pkgs.qemu_test.override { canokeySupport = true; };
  nodes = {
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
      environment.systemPackages = [
        nixieInstaller
        nixieCli
        pkgs.cryptsetup
        pkgs.expect
      ];
      system.extraDependencies = [
        toplevel
        disko
        siteSrc
      ];
    };
    # The same disk on a machine with no TPM at all, which is where the
    # attestation code used to hold the passphrase prompt behind a device
    # unit for a TPM that never appears.
    notpm = {
      imports = [ shared ];
      virtualisation.tpm.enable = lib.mkForce false;
      virtualisation.useBootLoader = true;
      virtualisation.useDefaultFilesystems = false;
      virtualisation.fileSystems."/" = {
        device = "/dev/disk/by-label/never-used";
        fsType = "ext4";
      };
    };
    target = {
      imports = [ shared ];
      # The key's state lives next to the disk, so it keeps its PIN and
      # credential across the restarts.
      virtualisation.qemu.options = [
        "-device pci-ohci,id=fido-bus"
        "-device canokey,bus=fido-bus.0,file=../canokey"
      ];
      virtualisation.useBootLoader = true;
      virtualisation.useDefaultFilesystems = false;
      virtualisation.fileSystems."/" = {
        device = "/dev/disk/by-label/never-used";
        fsType = "ext4";
      };
    };
  };
  testScript = template.fill ./splash.py {
    inherit disko;
    keys_example_host_age = ../keys/example-host.age;
    inherit siteSrc;
    inherit state;
    inherit toplevel;
  };
}
