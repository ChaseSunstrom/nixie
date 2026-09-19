# A kexec image in the shape nixos-anywhere unpacks, built from nixpkgs.
#
# NOT REFERENCED BY ANY TEST YET, and the reason is at the bottom of this
# comment. It is kept because six runs went into learning the contract it
# encodes, and because the machine it makes does start -- what is missing is
# one step past that.
#
# nixos-anywhere fetches one from nix-community/nixos-images by default: it
# extracts the tarball into $HOME/kexec, runs `kexec/run`, and reads the
# words "machine will boot into nixos" back to know the machine is on its
# way. nixpkgs builds a kexec tarball of its own but lays it out differently
# -- `kexec_nixos` beside a store -- so this wraps nixpkgs' netboot
# installer in the layout that contract asks for, and the platform gains no
# input for it. `NIXIE_KEXEC` hands it to the deploy, which is what that
# escape hatch is for.
#
# Two things have to survive the kexec, which a downloaded image works out
# at runtime and this one is told outright because a test knows them: the
# key the deploy logs in with, and the address it is reached on. Nothing of
# the machine being replaced survives otherwise.
{
  pkgs,
  inputs,
  authorizedKey,
  address,
  prefixLength ? 24,
  interface ? "eth1",
}:
let
  inherit (pkgs) lib;
  installer = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      "${inputs.nixpkgs}/nixos/modules/installer/netboot/netboot-minimal.nix"
      (
        { lib, ... }:
        {
          services.openssh.enable = true;
          services.openssh.settings.PermitRootLogin = lib.mkForce "prohibit-password";
          users.users.root.openssh.authorizedKeys.keyFiles = [ authorizedKey ];
          # By pattern, not by name: this system is not the one the test
          # framework configured, and what its single NIC ends up called
          # depends on the kernel that just started. An address on a name
          # that does not exist is a machine nobody can reach.
          networking.useDHCP = false;
          networking.useNetworkd = true;
          # The installer profile brings NetworkManager, which claims the
          # NIC and leaves the address below unapplied.
          networking.networkmanager.enable = lib.mkForce false;
          # The one the machine was reached on, not every NIC it has: this
          # VM also carries a user-mode interface, and the same address on
          # both leaves neither routable. The kexec keeps the hardware in
          # the order it was, so the name is the one it had.
          systemd.network.networks."10-lan" = {
            matchConfig.Name = interface;
            address = [ "${address}/${toString prefixLength}" ];
            linkConfig.RequiredForOnline = "no";
          };
          boot.kernelParams = [ "console=ttyS0" ];
          documentation.enable = false;
        }
      )
    ];
  };
  inherit (installer.config.system.build) kernel netbootRamdisk toplevel;
  # Its own shebang, not a store path: the machine that runs this is the one
  # being replaced, and nothing of this image is in its store.
  run = pkgs.writeTextFile {
    name = "kexec-run";
    executable = true;
    text = ''
      #!/bin/sh
      set -eu
      cd "$(dirname "$0")"
      extra=
      while [ $# -gt 0 ]; do
        case $1 in
          --kexec-extra-flags) extra=$2; shift 2 ;;
          *) shift ;;
        esac
      done
      # shellcheck disable=SC2086
      ./kexec --load ./bzImage --initrd=./initrd $extra \
        --command-line "init=${toplevel}/init ${toString installer.config.boot.kernelParams}"
      # What nixos-anywhere reads back to know the machine is on its way; it
      # has to be said before the kernel it is said from goes away.
      echo "machine will boot into nixos"
      sync
      # Detached and after a moment, so the caller's ssh closes rather than
      # dying with the kernel underneath it.
      (sleep 2; ./kexec -e) >/dev/null 2>&1 &
      exit 0
    '';
  };
in
pkgs.runCommand "nixie-test-kexec-image.tar.gz"
  {
    nativeBuildInputs = [
      pkgs.gnutar
      pkgs.gzip
    ];
  }
  ''
    mkdir -p kexec
    cp ${kernel}/${installer.config.system.boot.loader.kernelFile} kexec/bzImage
    cp ${netbootRamdisk}/initrd kexec/initrd
    cp ${lib.getExe' pkgs.pkgsStatic.kexec-tools "kexec"} kexec/kexec
    cp ${run} kexec/run
    chmod +x kexec/run kexec/kexec
    tar czf $out kexec
  ''

# Where this gets to, and what it still needs.
#
# The deploy hands this to nixos-anywhere through NIXIE_KEXEC; nixos-anywhere
# unpacks it, runs `kexec/run`, reads "machine will boot into nixos" back and
# is satisfied; the machine loads the kernel and comes up as the NixOS
# installer, which its console says in as many words. Then nothing can reach
# it: `ssh: connect to host ... No route to host`, and the deploy waits.
#
# What is missing is the part a downloaded kexec-installer does at runtime
# and this one is told at build time -- carrying the machine's networking
# across the kexec. Told is not enough: the image has two NICs here, a
# user-mode one and the test's own, and the address has to land on the one
# the deploy is talking to, in a system whose interface names are decided by
# the kernel that just started rather than by the one that was configured.
# Matching every NIC gives neither a route; matching the name it had leaves
# it unreachable a different way. nix-community/nixos-images solves this by
# reading the running machine's addresses and routes before the kexec and
# replaying them after, which is the piece to write next -- or to take as an
# input, which costs the platform a dependency and is the user's call.
