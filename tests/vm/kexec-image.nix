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
  # Paths the installer should already have when it comes up. A kexeced
  # machine's store is a tmpfs with nothing in it, so without these the
  # deploy pushes a whole system across the wire before it can do anything;
  # the netboot image is itself a store, and anything in its closure arrives
  # with it.
  carry ? [ ],
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
          # Nothing static here: the address comes across on the kernel
          # command line, worked out on the machine being replaced (see the
          # run script below). Names are the plain ethN the old kernel used,
          # so the one named there is the one meant here.
          networking.usePredictableInterfaceNames = false;
          networking.useDHCP = false;
          # The installer profile brings NetworkManager, which would claim
          # the interface the kernel has just configured.
          networking.networkmanager.enable = lib.mkForce false;
          networking.useNetworkd = false;
          # The address the machine had, put back by hand. The kernel's own
          # `ip=` is not enough: whether it is compiled in varies, and
          # anything that brings the link down afterwards takes it with it.
          # The NIC is found by its hardware address, so nothing here
          # depends on what this kernel decided to call it.
          systemd.services.nixie-carry-network = {
            description = "The address this machine had before the kexec";
            wantedBy = [ "multi-user.target" ];
            before = [ "sshd.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            path = [ pkgs.iproute2 ];
            script = ''
              carry=
              for word in $(cat /proc/cmdline); do
                case $word in
                  nixie.carry=*) carry=''${word#nixie.carry=} ;;
                esac
              done
              [ -n "$carry" ] || { echo "nothing to carry"; exit 0; }
              cidr=''${carry%%,*}
              rest=''${carry#*,}
              gw=''${rest%%,*}
              mac=''${rest#*,}
              # Waited for rather than assumed present: this runs early
              # enough that udev may not have the interface yet, and an
              # address put nowhere is a machine nobody can reach.
              dev=
              tries=0
              while [ -z "$dev" ] && [ $tries -lt 60 ]; do
                for path in /sys/class/net/*; do
                  [ "$(cat "$path/address" 2>/dev/null)" = "$mac" ] || continue
                  dev=''${path##*/}
                done
                [ -n "$dev" ] || sleep 1
                tries=$((tries + 1))
              done
              [ -n "$dev" ] || { echo "no interface with address $mac"; exit 1; }
              ip link set "$dev" up
              ip addr add "$cidr" dev "$dev" || true
              [ -z "$gw" ] || ip route add default via "$gw" dev "$dev" || true
              echo "carried $cidr to $dev ($mac)"
              echo "nixie: carried $cidr to $dev" >/dev/console || true
            '';
          };
          boot.kernelParams = [ "console=ttyS0" ];
          documentation.enable = false;
          system.extraDependencies = carry;
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

      # Carry this machine's networking across, because nothing else does.
      # The kernel takes an address on its command line and brings the
      # interface up with it before any of the new system runs, which is
      # what lets whoever started this keep talking to the machine. The
      # alternative is the new system guessing, and it has nothing to guess
      # from: a kexec leaves it no state and no DHCP answer here.
      netmask_for() {
        full=$(($1 / 8))
        rest=$(($1 % 8))
        out=
        i=0
        while [ $i -lt 4 ]; do
          if [ $i -lt $full ]; then part=255
          elif [ $i -eq $full ]; then
            case $rest in
              0) part=0 ;; 1) part=128 ;; 2) part=192 ;; 3) part=224 ;;
              4) part=240 ;; 5) part=248 ;; 6) part=252 ;; *) part=254 ;;
            esac
          else part=0
          fi
          out="''${out:+$out.}$part"
          i=$((i + 1))
        done
        echo "$out"
      }

      # The address this very session arrived on, which is the one whoever
      # started the kexec can still reach: SSH_CONNECTION's third field is
      # the server address the client connected to. A machine can have
      # several -- this one also has a user-mode interface that goes
      # nowhere -- and carrying the wrong one strands the deploy.
      want=
      [ -z "''${SSH_CONNECTION:-}" ] || want=$(echo "''${SSH_CONNECTION}" | awk '{print $3}')
      line=
      [ -z "$want" ] || line=$(ip -4 -o addr show scope global up | grep " $want/" || true)
      [ -n "$line" ] || line=$(ip -4 -o addr show scope global up | head -1)
      ipcmd=
      if [ -n "$line" ]; then
        dev=$(echo "$line" | awk '{print $2}')
        cidr=$(echo "$line" | awk '{print $4}')
        host=''${cidr%%/*}
        bits=''${cidr##*/}
        gw=$(ip -4 route show default | awk '{print $3; exit}')
        mac=$(cat "/sys/class/net/$dev/address")
        # Both ways: the kernel's, for anything that reads it early, and
        # this image's own, which is what actually puts the address back.
        ipcmd="ip=$host::$gw:$(netmask_for "$bits")::$dev:off nixie.carry=$cidr,$gw,$mac"
        echo "carrying $cidr on $dev ($mac) across the kexec"
      fi

      # shellcheck disable=SC2086
      ./kexec --load ./bzImage --initrd=./initrd $extra \
        --command-line "init=${toplevel}/init ${toString installer.config.boot.kernelParams} $ipcmd"
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
# installer. The address it had comes with it -- the run script reads the one
# this very SSH session arrived on (SSH_CONNECTION names it, which is how the
# right interface is picked out of the several a machine has), hands it over
# on the kernel command line, and the service above puts it back, waiting for
# udev to produce the interface with that hardware address first. Its own
# words on the console of a run:
#
#   carrying 192.168.1.9/24 on eth1 (52:54:00:12:01:03) across the kexec
#   nixie: carried 192.168.1.9/24 to eth1
#
# What is left is not this file's doing. The machine answers, sshd is up and
# the deploy reconnects -- a run's log shows the host key accepted after the
# kexec. What follows is the copy: the store of a kexeced machine is a tmpfs
# with nothing in it, and two runs sat in that copy for fifty and fifty-five
# minutes, the second until the test process was terminated.
#
# `carry` is the answer to that, and it works: the netboot image is itself a
# store, so the system being installed rides along in it and the deploy's
# copy finds everything already there. What stopped the run that proved it
# was the other half of vm-deploy -- the setup generation reached only phase
# 3 that time, where four runs before it had reached 8 -- so the test in the
# tree is the one that has never flaked, and finishing this wants the two
# halves apart: a test of its own, on a machine with room for a 12 GB guest
# beside the rest.
