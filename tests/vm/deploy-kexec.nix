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

# The stalls this once put down to the host were the path's own: the
# kexeced installer did not trust the key nixos-anywhere reconnects with, so
# it sat at a password prompt; and past that, the deploy sent the site with
# rsync and ran the phase commands by name, neither of which a minimal
# installer has. See VERIFICATION.md, 2026-09-22.
