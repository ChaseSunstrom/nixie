# Hardware change and recovery on an installed server: a USB device plugged
# in after setup is blocked, `nixie security reenroll` lets a keyboard
# through while it runs, `nixie usb` lists and allows the device in the site,
# and `nixie apply` lets it through. (The TPM-reset and recovery-key part is
# in vm-encryption, where an installed encrypted target exists.)
{
  pkgs,
  inputs,
  nixieLib,
  exampleSite,
  nixieCli,
}:
let
  template = import ../../lib/template.nix pkgs.lib;
  inherit (pkgs) lib;
  common = {
    imports = nixieLib.hostModules ../../examples/site "server" exampleSite.hosts.server ++ [
      ./qemu.nix
    ];
    virtualisation.sharedDirectories.nixie-site = {
      source = "${lib.cleanSource ../../examples/site}";
      target = "/etc/nixie/site";
    };
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
    # The test VM boots its kernel directly and has no mounted ESP, so a
    # generation switch must not try to install the boot loader.
    boot.loader.systemd-boot.enable = lib.mkForce false;
    nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:01" ];
    nixie.network.bridge.mode = "managed-nat";
    nixie.network.address = "192.168.1.1/24";
    nixie.incus.pools.default = {
      driver = "dir";
      source = "/var/lib/incus/storage-pools/default";
    };
    nixie.guests = lib.mkForce { };
    # The facts the site declares must name what this VM actually has, so
    # drift is a real signal rather than noise from the example's by-id paths.
    nixie.disks.system = lib.mkForce "/dev/vda";
    # A spare disk for `nixie hardware add-disk`.
    virtualisation.emptyDiskImages = [ 512 ];
    boot.supportedFilesystems.zfs = true;
    networking.hostId = "8425e349";
    environment.systemPackages = [
      nixieCli
      pkgs.git
      pkgs.jq
    ];
  };
  # The generation `nixie apply` switches to after `nixie usb allow`.
  allowed = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {
      inherit inputs;
    };
    modules = [
      "${inputs.nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
      "${inputs.nixpkgs}/nixos/modules/testing/test-instrumentation.nix"
      common
      { nixie.security.hardening.usbguard.allow = [ "0627:0001" ]; }
    ];
  };
in
pkgs.testers.runNixOSTest {
  name = "vm-hardware";
  nodes.host = {
    imports = [ common ];
    system.extraDependencies = [ allowed.config.system.build.toplevel ];
  };
  # A host still in setup: its kiosk needs a pointer as well as a keyboard.
  # The terminal front end keeps a browser out of a test about USB rules.
  nodes.setup = {
    imports = [ common ];
    nixie.setup.pending = true;
    nixie.setup.frontEnd = "terminal";
  };

  testScript = template.fill ./hardware.py {
    allowed_config_system_build_toplevel = allowed.config.system.build.toplevel;
  };
}
