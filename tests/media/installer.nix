# Media: the installer. The ISO console banner (tty2), the kiosk wizard on
# the installer's own screen, and every wizard step from a LAN browser
# through Playwright, then the continuation steps after the reboot.
{
  pkgs,
  inputs,
  self,
  nixieLib,
  exampleSite,
}:
let
  template = import ../../lib/template.nix pkgs.lib;
  packages = self.packages.x86_64-linux;
  py = pkgs.python3.withPackages (p: [ p.playwright ]);
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
          nixie.security.encryption.enable = true;
          nixie.setup.pending = true;
          nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:03" ];
          nixie.network.address = "192.168.1.3/24";
          nixie.disks.system = lib.mkForce "/dev/vda";
          boot.kernelParams = lib.mkAfter [ "console=ttyS0" ];
        }
      )
    ];
  };
  shared = {
    # Relative paths resolve inside each node's own state directory; one level
    # up is the driver's directory, which both nodes share.
    virtualisation.diskImage = "../target.qcow2";
    virtualisation.diskSize = 8 * 1024;
    # Phase 3 evaluates and copies the whole system here; at 3 GB with the
    # installer's compressed swap the kernel fell over mid-copy.
    virtualisation.memorySize = 6144;
    virtualisation.cores = 4;
    virtualisation.useEFIBoot = true;
    virtualisation.tpm.enable = true;
  };
  wizard = pkgs.writeText "wizard.py" (builtins.readFile ./installer-wizard.py);
in
pkgs.testers.runNixOSTest {
  name = "media-installer";
  enableOCR = true;
  nodes = {
    client = {
      environment.systemPackages = [
        py
        pkgs.curl
      ];
      environment.variables.PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
      environment.variables.PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "1";
    };
    installer = {
      imports = [
        shared
        ../../installer/installer-system.nix
      ];
      nixie.installer = {
        inherit packages;
        toplevel = "${target.config.system.build.toplevel}";
        disko = "${target.config.system.build.diskoScript}";
      };
      system.extraDependencies = [
        target.config.system.build.toplevel
        target.config.system.build.diskoScript
      ];
      virtualisation.emptyDiskImages = [ 1024 ];
      virtualisation.rootDevice = "/dev/vdb";
      virtualisation.fileSystems."/".autoFormat = true;
      # nixos-install copies the closure out of this store by hash, and the
      # path registration at boot needs the store to be writable.
      virtualisation.writableStore = true;
      virtualisation.efi.keepVariables = false;
      virtualisation.resolution = {
        x = 1280;
        y = 800;
      };
      networking.firewall.allowedTCPPorts = [ 9443 ];
    };
    target = {
      imports = [ shared ];
      virtualisation.useBootLoader = true;
      virtualisation.useDefaultFilesystems = false;
      virtualisation.efi.keepVariables = false;
      virtualisation.resolution = {
        x = 1280;
        y = 800;
      };
      virtualisation.fileSystems."/" = {
        device = "/dev/disk/by-label/never-used";
        fsType = "ext4";
      };
    };
  };
  testScript = template.fill ./installer.py {
    inherit wizard;
  };
}
