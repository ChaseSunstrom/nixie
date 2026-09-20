# NOT REGISTERED: it does not pass here, and the bottom of this comment says
# how far it gets. The split it represents is real -- this path is a test of
# its own now, not a fourth node on vm-deploy -- and what it needs is a
# machine with more room than this one, not more code.
#
# The half of the headless path that starts from a machine already running
# something else: the deploy kexecs it into the installer and installs from
# there. vm-deploy covers the other half, from the Nixie ISO.
#
# Its own test rather than a fourth node on that one, because this machine
# wants twelve gigabytes of its own -- it holds the image, then the installer
# unpacked from it, then that installer's store with a system in it.
{
  pkgs,
  inputs,
  self,
  nixieLib,
  exampleSite,
}:
let
  inherit (pkgs) lib;
  inherit
    (import ./deploy-common.nix {
      inherit
        pkgs
        inputs
        self
        nixieLib
        exampleSite
        ;
    })
    target
    site
    sources
    packages
    ;
  plainAddress = "192.168.1.9";
  # The image carries the system it is about to install, so the deploy's copy
  # into the kexeced machine finds everything already there. Without that the
  # whole system crosses the wire into a tmpfs, which is an hour that this
  # path does not otherwise have to spend -- the ISO path never does, because
  # the image already holds every path.
  kexecImage = import ./kexec-image.nix {
    inherit pkgs inputs;
    authorizedKey = ../keys/client_ed25519.pub;
    carry = [
      target.config.system.build.toplevel
      target.config.system.build.diskoScript
      packages.nixie-cli
    ];
  };
in
pkgs.testers.runNixOSTest {
  name = "vm-deploy-kexec";
  nodes = {
    runner = {
      environment.systemPackages = [
        packages.deploy
        pkgs.openssh
        pkgs.util-linux # script(1): gum asks on a terminal, and there is none
      ];
      system.extraDependencies = [
        site
        self
        target.config.system.build.toplevel
        target.config.system.build.diskoScript
        kexecImage
      ]
      ++ sources;
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
      virtualisation.memorySize = 6144;
      virtualisation.diskSize = 24 * 1024;
      virtualisation.writableStore = true;
    };
    # Some other Linux: what the deploy looks for is /etc/nixie-iso, and a
    # plain NixOS node has none.
    plain =
      { lib, ... }:
      {
        virtualisation.diskImage = "../kexec-target.qcow2";
        virtualisation.diskSize = 8 * 1024;
        virtualisation.memorySize = 12288;
        virtualisation.cores = 4;
        virtualisation.useEFIBoot = true;
        # Fixed, so the test knows where to reach it; the image carries
        # whatever the machine has across the kexec by itself.
        networking.interfaces.eth1.ipv4.addresses = lib.mkForce [
          {
            address = plainAddress;
            prefixLength = 24;
          }
        ];
        users.users.root.openssh.authorizedKeys.keyFiles = [ ../keys/client_ed25519.pub ];
        services.openssh.enable = true;
        services.openssh.settings.PermitRootLogin = lib.mkForce "yes";
      };
  };

  testScript = (import ../../lib/template.nix lib).fill ./deploy-kexec.py {
    key = ../keys/client_ed25519;
    age = ../keys/example-host.age;
    inherit site plainAddress;
    toplevel = target.config.system.build.toplevel;
    disko = target.config.system.build.diskoScript;
    kexec = kexecImage;
  };
}

# How far it gets, on this host: the deploy takes the kexec branch, the image
# is unpacked and `kexec/run` says "machine will boot into nixos", the machine
# comes up as the installer and puts its old address back -- `nixie: carried
# 192.168.1.9/24 to eth1` on its own console. Then nixos-anywhere's reconnect
# did not complete inside forty minutes on the run that split this out, where
# the same steps inside vm-deploy had reconnected (the host key accepted again
# after the kexec) before stalling in the copy instead. Two different stalls
# on two different runs, neither reproduced twice, both on a host already
# holding a 6 GB and a 12 GB guest.
#
# So what this wants next is a machine, and a run that is allowed to take an
# hour without anything else on it -- not another guess. Everything the path
# needs is here: `carry` seeds the target's store so the copy has nothing to
# send, the address crosses the kexec, and deploy-kexecs holds the branch's
# shape in the gate meanwhile.
