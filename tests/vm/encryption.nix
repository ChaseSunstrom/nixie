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
          # Auto-enrolment stages a systemd-boot key-enrol EFI that, in this
          # OVMF, enrols the keys and reboots but then cannot complete a
          # Secure Boot verified boot of the signed loader, hanging the VM.
          # lanzaboote still signs the whole chain; we assert that instead.
          boot.lanzaboote.autoEnrollKeys.enable = lib.mkForce false;
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
            pkgs.sbsigntool
            pkgs.age # the test decrypts the header backup to verify it
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

  # Both VMs use one disk.
  shared = {
    # Relative paths resolve inside each node's own state directory; one level
    # up is the driver's directory, which both nodes share.
    virtualisation.diskImage = "../target.qcow2";
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
      # Drive order: target disk, then this empty disk.
      virtualisation.rootDevice = "/dev/vdb";
      virtualisation.fileSystems."/".autoFormat = true;
      # nixos-install copies the closure out of this store by hash, and the
      # path registration at boot needs the store to be writable.
      virtualisation.writableStore = true;
      boot.supportedFilesystems.zfs = true;
      networking.hostId = "deadbeef";
      environment.systemPackages = [
        nixieInstaller
        pkgs.cryptsetup
      ];
      # Registered in the installer's own store, so
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
    # Keepalives: after a duress wipe the peer powers off mid-session and the
    # relay must notice instead of hanging on the dead connection.
    ssh = "ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 -i /root/client_ed25519 -p 2222 root@192.168.1.3"

    def remote_unlock(answers, gap=25):
        # The relay shell in the initrd feeds each answer to the pending prompt
        # in order. The gap must outlast the TPM unseal of the outer layer
        # (about 15 s) so the session is still open when the inner prompt comes.
        # A stale neighbour entry from the previous boot makes the port poll
        # crawl; the initrd panics if the first prompt waits much past 60 s.
        client.succeed("ip neigh flush all")
        client.wait_until_succeeds("nc -z 192.168.1.3 2222", timeout=120)
        feed = "; ".join(f"sleep {2 if i == 0 else gap}; printf '%s\\n' '{a}'" for i, a in enumerate(answers))
        client.succeed("timeout 120 sh -c \"(" + feed + "; sleep 5) | " + ssh + "\" || true")

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
        # The attestation code prints on the console (asserted by the boot media
        # run); here remote_unlock waits for the initrd SSH port and answers
        # both passphrase prompts, and reaching multi-user proves the unlock.
        remote_unlock(["hunter2", "hunter2"])
        target.wait_for_unit("multi-user.target")
        target.succeed("mount | grep -q 'rpool/root on / '")
        target.succeed("test -e /dev/mapper/rpool-outer && test -e /dev/mapper/rpool")
        target.succeed("test -e /var/lib/nixie/setup/3.done")
        target.succeed("nixie-phase 4 >&2")

    with subtest("phase 5: the boot chain is signed and phase 5 detects Setup Mode"):
        # The site's own keys are in place and lanzaboote signed the loader,
        # the stub and every generation's UKI with the db key.
        target.succeed("test -e /var/lib/sbctl/keys/db/db.key && test -e /var/lib/sbctl/keys/db/db.pem")
        target.succeed("ls /boot/EFI/Linux/*.efi >/dev/null")
        signed = target.succeed(
            "for f in /boot/EFI/systemd/systemd-boot*.efi /boot/EFI/BOOT/BOOT*.EFI /boot/EFI/Linux/*.efi; do "
            "sbverify --cert /var/lib/sbctl/keys/db/db.pem \"$f\" || exit 1; done; echo all-signed"
        )
        assert "all-signed" in signed, signed
        # In Setup Mode phase 5 stages enrolment and asks for the reboot (exit 10).
        rc, out = target.execute("nixie-phase 5 2>&1")
        print(out)
        assert rc == 10, f"expected the enrol-reboot request, got {rc}: {out}"
        # The firmware enrolling the keys and then booting the signed chain is
        # exercised on real hardware; this OVMF build enrols the keys (the
        # console shows "successfully enrolled") but will not complete a Secure
        # Boot verified boot afterwards, so it is not driven here. See
        # VERIFICATION.md.

    with subtest("phase 6: TPM + PIN enrolment, attestation init, header backups"):
        target.succeed(keys)
        target.succeed("nixie-phase 6 --backup-dest /root >&2")
        target.succeed("cryptsetup luksDump /dev/vda2 | grep -q systemd-tpm2")
        target.succeed("cryptsetup luksDump /dev/vda2 | grep -q systemd-recovery")
        target.succeed("test -s /root/nixie-server-headers.tar.age")
        target.succeed("test -s /run/nixie/keys/attestation-qr")
        target.succeed("test -s /var/lib/nixie/tpm-lockout-auth")
        # The recovery key is shown once (here: the key file the front end
        # reads) and is not in the bundle on the host; the install passphrase
        # slot is gone.
        recovery = target.succeed("cat /run/nixie/keys/recovery-key").strip()
        assert len(recovery) > 40, recovery
        target.fail("cryptsetup luksDump /dev/vda2 | grep -q '^  0: luks2'")
        # Restoring a header from the bundle must work with the host key.
        target.succeed("mkdir /root/hb && age -d -i /var/lib/nixie/age.key /root/nixie-server-headers.tar.age | tar -C /root/hb -xf - && test -s /root/hb/rpool-outer.header && grep -q 'recovery key' /root/hb/RECOVERY.txt")
        target.fail(f"grep -q '{recovery}' /root/hb/RECOVERY.txt")
        target.shutdown()

    with subtest("phase 7: the TPM and PIN open the outer layer and the code is shown"):
        target.start()
        # The passphrase slot was wiped in phase 6; the outer layer now opens
        # only with the TPM2 token PIN (1234) or the recovery key.
        remote_unlock(["1234", "hunter2"])
        target.wait_for_unit("multi-user.target")
        target.succeed("cryptsetup luksDump /dev/vda2 | grep -q systemd-tpm2 && test -e /dev/mapper/rpool-outer")
        rc, out = target.execute("nixie-phase 7 2>&1")
        print(out)
        assert "outer layer is open and bound to the TPM" in out, out
        assert "attestation code computes" in out, out
        # Secure Boot cannot be enrolled/enforced in this OVMF VM (see phase 5
        # and VERIFICATION.md), so phase 7 and `nixie doctor` report it
        # not-enabled here; every other check passes.
        doc = target.succeed("nixie doctor || true")
        print(doc)
        assert "RESEAL NEEDED" not in doc, doc
        target.succeed("nixie reseal")
        # The sealed generation label on the ESP matches the running system.
        target.succeed("diff <(cat /boot/nixie/attestation-generation) /run/current-system/nixos-version")
        doc = target.succeed("nixie doctor || true")
        assert "unlock" in doc and "RECOVERY KEY" not in doc, doc
        target.shutdown()

    with subtest("reenroll after a board change rebinds the TPM and rotates the recovery key"):
        # The board/TPM/firmware change itself (the recovery key unlocking a
        # fresh TPM at the prompt) rides on systemd-cryptsetup's own fallback,
        # which is exercised on hardware; here the target boots normally with
        # the TPM and PIN, then `nixie security reenroll` does the work an
        # operator would run afterwards. The outer layer still has exactly one
        # recovery slot, the TPM binding, and a fresh key that differs.
        target.start()
        remote_unlock(["1234", "hunter2"])
        target.wait_for_unit("multi-user.target")
        # Secure Boot cannot be enrolled in this OVMF (phase 5 above), so the
        # first phase is marked done the way its enrolment reboot would leave it.
        target.succeed("mkdir -p /var/lib/nixie/reenroll && date -Is >/var/lib/nixie/reenroll/5.done")
        target.succeed(f"mkdir -p /run/nixie/keys && chmod 700 /run/nixie/keys && printf 1234 >/run/nixie/keys/pin && printf '%s' '{recovery}' >/run/nixie/keys/recovery-key")
        # Phases 6 and 7 run; 7 reports Secure Boot not enabled (this OVMF, see
        # phase 5), so the command exits 1 and keeps its markers for a resume.
        rc, out = target.execute("nixie security reenroll 2>&1")
        print(out)
        assert "old TPM binding removed" in out and "outer layer bound to TPM" in out, out
        assert "outer layer is open and bound to the TPM" in out and "attestation code computes" in out, out
        assert rc == 1 and "Secure Boot not enabled" in out, (rc, out)
        new = target.succeed("cat /run/nixie/keys/recovery-key").strip()
        assert new != recovery and len(new) > 40, new
        assert target.succeed("cryptsetup luksDump /dev/vda2 | grep -c systemd-recovery").strip() == "1"
        target.succeed("cryptsetup luksDump /dev/vda2 | grep -q systemd-tpm2")
        target.succeed("test -e /var/lib/nixie/reenroll/6.done && test -s /var/lib/nixie/setup/header-backup.tar.age && test -e /var/lib/nixie/setup/6.done")
        target.succeed("test \"$(stat -c %Y /var/lib/nixie/setup/header-backup.tar.age)\" -ge \"$(stat -c %Y /var/lib/nixie/setup/6.done)\"")
        doc = target.succeed("nixie doctor || true")
        print(doc)
        assert "RESEAL NEEDED" not in doc, doc
        # The new recovery key opens the outer layer (what a real recovery boot
        # relies on); --test-passphrase checks it without unlocking or enrolling.
        target.succeed(f"printf '%s' '{new}' | cryptsetup open --test-passphrase /dev/vda2")
        target.fail(f"printf '%s' '{recovery}' | cryptsetup open --test-passphrase /dev/vda2")
        target.shutdown()

    with subtest("duress passphrase wipes every key slot and powers off"):
        # The PIN opening the outer layer here proves the new TPM binding.
        target.start()
        # The PIN opens the outer layer; the duress passphrase, typed at the
        # inner layer's prompt where slot 7 holds it, wipes every slot and
        # powers off.
        remote_unlock(["1234", "wipe-me"])
        target.wait_for_shutdown()
        installer.start()
        installer.wait_for_unit("multi-user.target")
        dump = installer.succeed("cryptsetup luksDump /dev/vda2")
        assert not re.search(r"^ +[0-9]+: luks2", dump, re.M), dump
        installer.shutdown()
  '';
}
