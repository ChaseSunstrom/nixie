# NOT A CHECK YET, and tests/default.nix does not register it. What stops it
# is written at the bottom of this comment; it is kept because it is nine
# iterations of a harness that works up to that point, and because whoever
# finishes it should not start again.
#
# The headless path: one machine installs another over SSH, restarts it,
# waits for it and carries on where the wizard's front ends carry on. The
# brief asks that `nix run .#deploy` reach the same end state as they do, and
# nothing here had ever run it: the entries for the terminal continuation
# stub gum and the phases, and the remote half -- install, restart, forget
# the installer's host key, reconnect -- was never exercised at all.
#
# The host is a plain one on purpose. Encryption, a TPM and Secure Boot each
# add a secret or a restart that a person answers at the machine, and those
# are the subject of vm-encryption and vm-splash; what is proved here is the
# path between two machines.
#
# Where it gets to: the runner reaches the installer over SSH with the
# repository's own test key, the deploy recognises the machine as running the
# Nixie ISO and needs no kexec, and with NIXIE_TOPLEVEL and NIXIE_DISKO handed
# in it does not build a system inside the VM. Where it stops: before anything
# is evaluated, nix locks the site's flake, and locking resolves the
# platform's transitive inputs -- disko, lanzaboote, crane, pre-commit-hooks
# and the rest. Having every source in the store is not enough, because nix
# fetches each `github:` reference to check it against the lock, and the VM
# has no way out. Finishing it wants a site that arrives already locked, which
# means generating that lock where the network is: in the derivation that
# builds the site, not inside the machine.
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
  # input pointed at this tree in the store, so the runner can evaluate it
  # with no network.
  site = pkgs.runCommand "deploy-site" { } ''
    cp -r ${lib.cleanSource ../../examples/site} $out
    chmod -R u+w $out
    substituteInPlace $out/flake.nix --replace 'github:OWNER/nixie' 'path:${self}'
  '';
  # Every source the platform's lock names, as the ISO does.
  sources =
    let
      walk = i: [ i.outPath ] ++ builtins.concatMap walk (builtins.attrValues (i.inputs or { }));
    in
    lib.unique (builtins.concatMap walk (builtins.attrValues inputs));
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
    inherit site;
    # The system this deploy installs, built here rather than inside the
    # runner: what the site evaluates to is not what this test preloaded,
    # so the runner was compiling a whole NixOS from source with nothing to
    # substitute from, and ran out of the fifty minutes it was given.
    toplevel = target.config.system.build.toplevel;
    disko = target.config.system.build.diskoScript;
  };
}
