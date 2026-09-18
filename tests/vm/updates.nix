# Following the site repository: one machine pushes a change, another sees
# that it is behind. "notify" says so and waits; "auto" applies it and
# confirms itself when `nixie doctor` passes. The repository is a bare one on
# each node and the machine that pushes is a second checkout beside it, so
# the transport is local; everything above it -- fetch, compare, notice,
# apply -- is what a real site runs.
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
  host =
    mode:
    { lib, ... }:
    {
      imports = nixieLib.hostModules ../../examples/site "server" exampleSite.hosts.server ++ [
        ./qemu.nix
      ];
      virtualisation.memorySize = 2048;
      virtualisation.cores = 2;
      virtualisation.diskSize = 8 * 1024;
      boot.loader.systemd-boot.enable = lib.mkForce false;
      networking.hostId = "8425e349";
      # This test is about following the repository; creating the guests a
      # site declares is the same `nixie apply`, and vm-guests covers it.
      nixie.guests = lib.mkForce { };
      # In "auto" mode the machine confirms the apply when `nixie doctor`
      # passes, so this VM has to be a machine doctor is happy with: the
      # example site's disk is not the one a test node has.
      nixie.disks.system = lib.mkForce "/dev/vda";
      # A test node's root is not ZFS, so incusd cannot make the site's
      # dataset pool and its preseed fails; a directory pool is the same to
      # everything this test is about.
      nixie.incus.pools = lib.mkForce {
        default = {
          driver = "dir";
          source = "/var/lib/incus/storage-pools/default";
        };
      };
      nixie.site.repo = "/srv/site.git";
      nixie.updates = {
        inherit mode;
        # The test starts the service itself; a timer as well would race it.
        schedule = "daily";
        confirmWithin = "2m";
      };
      environment.systemPackages = [
        nixieCli
        pkgs.jq
      ];
    };
  # What an applied update switches to: the same host with one thing more,
  # so the test can tell the two systems apart without building in the VM.
  applied =
    (inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
      };
      # The same VM modules the framework gives a node, so this is a system
      # this machine can switch to.
      modules = [
        "${inputs.nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
        "${inputs.nixpkgs}/nixos/modules/testing/test-instrumentation.nix"
        (host "notify")
        { environment.etc."nixie-applied-update".text = "yes"; }
      ];
    }).config.system.build.toplevel;
in
pkgs.testers.runNixOSTest {
  name = "vm-updates";
  nodes = {
    notify = {
      imports = [ (host "notify") ];
      # The framework builds nodes without the switch script; applying an
      # update needs it, as every real machine has it.
      system.switch.enable = true;
      system.extraDependencies = [ applied ];
    };
    auto = {
      imports = [ (host "auto") ];
      system.switch.enable = true;
      system.extraDependencies = [ applied ];
    };
  };
  testScript = template.fill ./updates.py {
    inherit applied;
    site = lib.cleanSource ../../examples/site;
  };
}
