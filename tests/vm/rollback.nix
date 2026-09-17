# Rollback: a second, broken generation is undone from the front panel;
# `apply --confirm-within` without a confirmation reverts on its own; a guest
# snapshot restore leaves the guest's /data/state alone; a data snapshot
# restores beside and in place.
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
  # What both the test node and the alternative generation share: the host
  # itself plus the VM settings the framework's qemu-vm module understands.
  common =
    { config, ... }:
    {
      imports = nixieLib.hostModules ../../examples/site "server" exampleSite.hosts.server ++ [
        ./qemu.nix
      ];
      virtualisation.sharedDirectories.nixie-site = {
        source = "${lib.cleanSource ../../examples/site}";
        target = "/etc/nixie/site";
      };
      virtualisation.memorySize = 3072;
      virtualisation.cores = 4;
      # A dir pool snapshots a guest by copying its whole root file system;
      # several copies need room.
      virtualisation.diskSize = 16 * 1024;
      virtualisation.resolution = {
        x = 1280;
        y = 800;
      };
      # The test VM boots its kernel directly and has no mounted ESP, so a
      # generation switch must not try to install the boot loader. Real hosts
      # keep it; `--boot-previous` (bootctl) is therefore not exercised here.
      boot.loader.systemd-boot.enable = lib.mkForce false;
      # A second disk becomes the ZFS pool for the data root (data snapshots).
      virtualisation.emptyDiskImages = [ 1024 ];
      boot.supportedFilesystems.zfs = true;
      networking.hostId = "8425e349";
      nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:01" ];
      nixie.network.bridge.mode = "managed-nat";
      nixie.network.address = "192.168.1.1/24";
      nixie.incus.pools.default = {
        driver = "dir";
        source = "/var/lib/incus/storage-pools/default";
      };
      nixie.guests = lib.mkForce {
        web = (import ../../examples/site/guests.nix).web // {
          ip = "10.90.0.10/24";
        };
      };
      environment.systemPackages = [
        nixieCli
        pkgs.curl
      ];
      environment.etc."nixie-test-alias".text = config.nixie.build.guestImages.web.alias;
    };
  # The "broken" generation: the control panel moves to another port, so the
  # usual address stops answering. Built with the same VM modules the test
  # node gets, so it is a valid system for this machine.
  broken = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {
      inherit inputs;
    };
    modules = [
      "${inputs.nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
      "${inputs.nixpkgs}/nixos/modules/testing/test-instrumentation.nix"
      common
      { nixie.incus.ui.port = lib.mkForce 8444; }
    ];
  };
in
pkgs.testers.runNixOSTest {
  name = "vm-rollback";
  enableOCR = true;
  nodes.host = {
    imports = [ common ];
    # The framework builds nodes without the switch script; a rollback to this
    # generation needs it, as every real generation has it.
    system.switch.enable = true;
    system.extraDependencies = [ broken.config.system.build.toplevel ];
  };

  testScript = template.fill ./rollback.py {
    broken_config_system_build_toplevel = broken.config.system.build.toplevel;
  };
}
