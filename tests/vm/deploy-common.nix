# What both deploy tests need: the system they install, the site they install
# it from, and every source that site's lock names.
#
# The two are separate tests because they are separate machines -- the ISO
# path runs three nodes and the kexec path runs one that wants twelve
# gigabytes, and one test holding both at once is how a host with room for
# either ends up with room for neither.
{
  pkgs,
  inputs,
  self,
  nixieLib,
  exampleSite,
}:
let
  inherit (pkgs) lib;
  packages = self.packages.x86_64-linux;
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
          nixie.security.encryption.enable = lib.mkForce false;
          nixie.setup.pending = true;
          nixie.guests = lib.mkForce { };
          nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:03" ];
          nixie.network.address = "192.168.1.3/24";
          nixie.disks.system = lib.mkForce "/dev/vda";
          boot.kernelParams = lib.mkAfter [ "console=ttyS0" ];
          environment.systemPackages = [ packages.nixie-cli ];
        }
      )
    ];
  };
  # The site the runner deploys from: the example one with its platform
  # input pointed at this tree in the store, and carrying the lock file it
  # would have got from a machine with a network (deploy-lock.py says why).
  site =
    pkgs.runCommand "deploy-site"
      {
        nativeBuildInputs = [
          pkgs.nix
          pkgs.python3
        ];
      }
      ''
        cp -r ${lib.cleanSource ../../examples/site} $out
        chmod -R u+w $out
        substituteInPlace $out/flake.nix --replace 'github:OWNER/nixie' 'path:${self}'
        # The disk this site names, for the machine it is installed on here: a
        # test's virtio drive has no serial and so no by-id link (D18), and the
        # deploy reads the disk from the site rather than from the system it is
        # handed.
        substituteInPlace $out/hosts/server/hardware.nix \
          --replace '/dev/disk/by-id/virtio-nixie-system' '/dev/vda'
        hash=$(nix --extra-experimental-features nix-command hash path ${self})
        python3 ${./deploy-lock.py} ${self} "$hash" $out/flake.lock
      '';
  # Every source the platform's lock names, as the ISO does.
  sources =
    let
      walk = i: [ i.outPath ] ++ builtins.concatMap walk (builtins.attrValues (i.inputs or { }));
    in
    lib.unique (builtins.concatMap walk (builtins.attrValues inputs));
in
{
  inherit
    target
    site
    sources
    packages
    ;
}
