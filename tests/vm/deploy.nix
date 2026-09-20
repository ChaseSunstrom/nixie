# The headless path: one machine installs another over SSH, restarts it, and
# the machine it installed carries itself the rest of the way. The brief asks
# that `nix run .#deploy` reach the same end state as the kiosk and the LAN
# wizard, and nothing here had ever run it -- the entries for the terminal
# continuation stub gum and the phases, and the remote half was never
# exercised at all.
#
# What it takes to run a deploy inside a test, each of which is a thing the
# first runs of this died on: a site that arrives already locked
# (deploy-lock.py), every source that lock names in the runner's store, a
# system handed in rather than built here (NIXIE_TOPLEVEL), a terminal for
# gum with a size, an answer typed when the question is on the screen rather
# than queued before it, and a test that treats each restart as the step it
# is rather than as the machine failing.
#
# The host is a plain one on purpose. Encryption, a TPM and Secure Boot each
# add a secret or a restart that a person answers at the machine, and those
# are the subject of vm-encryption and vm-splash; what is proved here is the
# path between two machines.
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
  shared = {
    virtualisation.diskImage = "../target.qcow2";
    virtualisation.diskSize = 8 * 1024;
    virtualisation.memorySize = 3072;
    virtualisation.cores = 4;
    virtualisation.useEFIBoot = true;
  };
in
pkgs.testers.runNixOSTest {
  name = "vm-deploy";
  nodes = {
    # The machine a person runs the deploy from.
    runner = {
      environment.systemPackages = [
        packages.deploy
        pkgs.openssh
        pkgs.util-linux # script(1): gum asks on a terminal, and there is none
      ];
      # Everything the deploy would otherwise fetch or build. Locking the
      # site resolves the platform's own inputs -- disko, lanzaboote and the
      # rest -- and with none of them here it sat trying to reach GitHub
      # from a machine with no way out. The ISO carries them for the same
      # reason (packages/nixie-iso.nix).
      system.extraDependencies = [
        site
        self
        target.config.system.build.toplevel
        target.config.system.build.diskoScript
      ]
      ++ sources;
      # A plain machine, not a Nixie host, so it carries none of the
      # platform's own nix settings: the deploy evaluates the site with the
      # flake commands and needs them turned on.
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
      # It evaluates nixpkgs and copies a whole system's closure out.
      virtualisation.memorySize = 6144;
      virtualisation.diskSize = 24 * 1024;
      virtualisation.writableStore = true;
    };
    installer = {
      imports = [
        shared
        ../../installer/installer-system.nix
      ];
      nixie.installer = {
        inherit packages;
        # The headless path drives the phases over SSH and uses neither the
        # kiosk nor the setup service; leaving the graphical front end on
        # put a browser and a compositor beside this deploy, which is how
        # the first run of it ran the machine out of room.
        mode = "terminal";
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
      virtualisation.writableStore = true;
      virtualisation.efi.keepVariables = false;
      # The deploy arrives over SSH as root, which is how a person does it
      # after giving the image a key or a password.
      users.users.root.openssh.authorizedKeys.keyFiles = [ ../keys/client_ed25519.pub ];
      services.openssh.settings.PermitRootLogin = lib.mkForce "yes";
    };
    installed = {
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

  testScript = (import ../../lib/template.nix lib).fill ./deploy.py {
    key = ../keys/client_ed25519;
    # The site brings secrets for this host, so the deploy asks for the key
    # that reads them rather than making a new identity.
    age = ../keys/example-host.age;
    inherit site;
    # The system this deploy installs, built here rather than inside the
    # runner: what the site evaluates to is not what this test preloaded,
    # so the runner was compiling a whole NixOS from source with nothing to
    # substitute from, and ran out of the fifty minutes it was given.
    toplevel = target.config.system.build.toplevel;
    disko = target.config.system.build.diskoScript;
  };
}
