# Installs the example server with every boot-time security feature on, from
# an installer VM onto a blank disk, then boots the disk under OVMF (Secure
# Boot capable, Setup Mode) with swtpm, and walks phases 4 to 7 exactly as a
# front end would: remote unlock over SSH, Secure Boot enrolment, TPM + PIN
# enrolment, attestation, verification, and finally the duress passphrase.
{
  pkgs,
  inputs,
  nixieLib,
  exampleSite,
  nixieInstaller,
  nixieCli,
}:
let
  inherit (pkgs) lib;
  clientKey = ../keys/client_ed25519;
  clientPub = lib.fileContents ../keys/client_ed25519.pub;

  # The system that ends up on the disk. Not a test node: it boots from its
  # own boot loader with its own initrd. test-instrumentation adds the
  # backdoor the driver talks to.
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
          nixie.security = {
            encryption.enable = true;
            tpm.enable = true;
            attestation.enable = true;
            duress.enable = true;
            remoteUnlock.enable = true;
            secureBoot.enable = true;
          };
          nixie.auth.sshKeys = [ clientPub ];
          # Node "target" is the third node, so the framework gives it this
          # address and hardware address on the test network.
          nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:03" ];
          nixie.network.address = "192.168.1.3/24";
          nixie.disks.system = lib.mkForce "/dev/vda";
          boot.initrd.availableKernelModules = [ "virtio_net" ];
          # Prompts must land on the serial console the driver reads and types on.
          boot.kernelParams = lib.mkAfter [ "console=ttyS0" ];
          environment.systemPackages = [
            nixieInstaller
            nixieCli
          ];
        }
      )
    ];
  };
  toplevel = target.config.system.build.toplevel;
  disko = target.config.system.build.diskoScript;

  state = pkgs.writeText "state.json" (
    builtins.toJSON {
      host = "server";
      profile = "server";
      systemDisk = "/dev/vda";
      dataDisk = null;
      uplinks = [ "52:54:00:12:01:03" ];
      gpu = "none";
      tpm = true;
      hostId = "8425e349";
      options.secureBoot = true;
    }
  );
  siteSrc = lib.cleanSource ../../examples/site;

  # Both VMs use one disk, one TPM state and one EFI variable store; the
  # framework keys those files on system.name.
  shared = {
    system.name = "nixie-target";
    virtualisation.diskImage = "./target.qcow2";
    virtualisation.diskSize = 8 * 1024;
    virtualisation.memorySize = 3072;
    virtualisation.cores = 4;
    virtualisation.useEFIBoot = true;
    virtualisation.useSecureBoot = true;
    virtualisation.tpm.enable = true;
  };
in
pkgs.testers.runNixOSTest {
  name = "vm-encryption";
  nodes = {
    client = {
      environment.systemPackages = [ pkgs.openssh ];
    };
    installer = {
      imports = [ shared ];
      # The installer's own root lives on a second small disk so the target
      # disk is /dev/vda both during and after the install.
      virtualisation.emptyDiskImages = [ 1024 ];
      # Drive order: target disk, store image, then this empty disk.
      virtualisation.rootDevice = "/dev/vdc";
      virtualisation.fileSystems."/".autoFormat = true;
      # nixos-install copies the closure by hash; a store image gives exact
      # bytes where the shared host store does not.
      virtualisation.useNixStoreImage = true;
      boot.supportedFilesystems.zfs = true;
      networking.hostId = "deadbeef";
      environment.systemPackages = [
        nixieInstaller
        pkgs.cryptsetup
      ];
      # Registered in the installer's own store (and its store image), so
      # nixos-install can copy them by hash.
      system.extraDependencies = [
        toplevel
        disko
        siteSrc
      ];
      virtualisation.efi.keepVariables = false;
    };
    target = {
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

  testScript = ''
    import re

    keys = "mkdir -p /run/nixie/keys && chmod 700 /run/nixie/keys && printf hunter2 >/run/nixie/keys/passphrase && printf 1234 >/run/nixie/keys/pin && printf wipe-me >/run/nixie/keys/duress && printf nixie >/run/nixie/keys/admin-password"
    ssh = "ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -i /root/client_ed25519 -p 2222 root@192.168.1.3"

    def remote_unlock(answers):
        # The relay shell in the initrd feeds each answer to the pending prompt in order.
        client.wait_until_succeeds("nc -z 192.168.1.3 2222", timeout=120)
        client.succeed("(" + "; ".join(f"sleep 2; printf '%s\\n' '{a}'" for a in answers) + "; sleep 3) | " + ssh + " || true")

    client.start()
    client.succeed("cp ${clientKey} /root/client_ed25519 && chmod 600 /root/client_ed25519")

    with subtest("phases 1-3 install the target from the installer VM"):
        installer.start()
        installer.wait_for_unit("multi-user.target")
        installer.succeed("mkdir -p /var/lib/nixie/setup && cp ${state} /var/lib/nixie/setup/state.json")
        installer.succeed(keys + " && cp ${../keys/example-host.age} /run/nixie/keys/age.key")
        installer.succeed("cp -r ${siteSrc} /tmp/site && chmod -R u+w /tmp/site")
        env = "NIXIE_SITE=/tmp/site NIXIE_TOPLEVEL=${toplevel} NIXIE_DISKO=${disko}"
        installer.succeed(f"{env} nixie-phase 1 >&2")
        hw = installer.succeed("cat /tmp/site/hosts/server/hardware.nix")
        assert 'nixie.disks.system = "/dev/vda"' in hw and "52:54:00:12:01:03" in hw, hw
        installer.succeed(f"{env} nixie-phase 2 >&2")
        installer.succeed("test -s /var/lib/nixie/setup/age.pub")
        installer.succeed(f"{env} nixie-phase 3 >&2")
        installer.succeed(f"{env} nixie-phase 3 >&2")  # idempotent: marker short-circuits
        installer.shutdown()

    with subtest("first boot: attestation warns, both passphrase prompts answered over SSH"):
        target.start()
        target.wait_for_console_text("ATTESTATION FAILED|Attestation code")
        remote_unlock(["hunter2", "hunter2"])
        target.wait_for_unit("multi-user.target")
        target.succeed("mount | grep -q 'rpool/root on / '")
        target.succeed("test -e /dev/mapper/rpool-outer && test -e /dev/mapper/rpool")
        target.succeed("test -e /var/lib/nixie/setup/3.done")
        target.succeed("nixie-phase 4 >&2")

    with subtest("phase 5: Secure Boot keys are enrolled by systemd-boot from Setup Mode"):
        target.succeed("test -e /var/lib/sbctl/keys/db/db.key")
        target.wait_for_unit("prepare-sb-auto-enroll.service")
        rc, out = target.execute("nixie-phase 5 2>&1")
        print(out)
        assert rc == 10, f"expected reboot request, got {rc}"
        target.shutdown()
        target.start()
        target.wait_for_console_text("Please enter passphrase")
        remote_unlock(["hunter2", "hunter2"])
        target.wait_for_unit("multi-user.target")
        print(target.succeed("bootctl status 2>&1 | head -20"))
        target.succeed("nixie-phase 5 >&2")

    with subtest("phase 6: TPM + PIN enrolment, attestation init, header backups"):
        target.succeed(keys)
        target.succeed("nixie-phase 6 --backup-dest /root >&2")
        target.succeed("cryptsetup luksDump /dev/vda2 | grep -q systemd-tpm2")
        target.succeed("cryptsetup luksDump /dev/vda2 | grep -q systemd-recovery")
        target.succeed("test -s /root/nixie-server-headers.tar.age")
        target.succeed("test -s /run/nixie/keys/attestation-qr")
        target.succeed("test -s /var/lib/nixie/tpm-lockout-auth")
        # Restoring a header from the bundle must work with the host key.
        target.succeed("mkdir /root/hb && age -d -i /var/lib/nixie/age.key /root/nixie-server-headers.tar.age | tar -C /root/hb -xf - && test -s /root/hb/rpool-outer.header && grep -q 'recovery key' /root/hb/RECOVERY.txt")
        target.shutdown()

    with subtest("phase 7: the outer layer opens with the TPM and PIN, the code is shown"):
        target.start()
        target.wait_for_console_text("Attestation code: [0-9]{6}")
        remote_unlock(["1234", "hunter2"])
        target.wait_for_unit("multi-user.target")
        target.succeed("nixie-phase 7 >&2")
        print(target.succeed("nixie doctor"))
        target.succeed("nixie reseal")
        target.succeed("ls /var/lib/nixie/setup/")
        target.shutdown()

    with subtest("duress passphrase wipes every key slot and powers off"):
        target.start()
        target.wait_for_console_text("Attestation code")
        remote_unlock(["1234", "wipe-me"])
        target.wait_for_shutdown()
        installer.start()
        installer.wait_for_unit("multi-user.target")
        dump = installer.succeed("cryptsetup luksDump /dev/vda2")
        assert not re.search(r"^ +[0-9]+: luks2", dump, re.M), dump
        installer.shutdown()
  '';
}
