# Media: the boot chain on screen. Passphrase prompt, attestation code and
# PIN prompt on the VGA console of an installed, fully enabled system, plus
# screendump frames at 10 fps of one boot for a short video.
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
            # The prompts are answered over the initrd's SSH, the way
            # vm-encryption does it: they are drawn on tty0 for the pictures
            # (console=tty0 below) and nothing types on that console.
            remoteUnlock.enable = true;
          };
          nixie.auth.sshKeys = [ clientPub ];
          # The client node is first, so the target is machine 3: its interface
          # is 52:54:00:12:01:03 and the initrd needs the address statically,
          # there being no DHCP server in the test network.
          nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:03" ];
          nixie.network.address = "192.168.1.3/24";
          # The committed hardware.nix of the example site lists storage
          # drivers only; on a real install phase 1 adds the wired ports'
          # drivers, without which the initrd's SSH has no network to listen
          # on and the passphrase can never be answered.
          boot.initrd.availableKernelModules = lib.mkAfter [ "virtio_net" ];
          nixie.disks.system = lib.mkForce "/dev/vda";
          # Prompts on the screen for the camera; the serial console stays for the driver.
          boot.kernelParams = lib.mkAfter [ "console=tty0" ];
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
      uplinks = [ "52:54:00:12:01:02" ];
      gpu = "none";
      tpm = true;
      hostId = "8425e349";
      options.secureBoot = false;
    }
  );
  siteSrc = lib.cleanSource ../../examples/site;
  shared = {
    # Relative paths resolve inside each node's own state directory; one level
    # up is the driver's directory, which both nodes share.
    virtualisation.diskImage = "../target.qcow2";
    virtualisation.diskSize = 8 * 1024;
    virtualisation.memorySize = 3072;
    virtualisation.cores = 4;
    virtualisation.useEFIBoot = true;
    virtualisation.tpm.enable = true;
    virtualisation.resolution = {
      x = 1280;
      y = 800;
    };
  };
in
pkgs.testers.runNixOSTest {
  name = "media-boot";
  nodes = {
    client = {
      environment.systemPackages = [ pkgs.openssh ];
    };
    installer = {
      imports = [ shared ];
      virtualisation.emptyDiskImages = [ 1024 ];
      virtualisation.rootDevice = "/dev/vdb";
      virtualisation.fileSystems."/".autoFormat = true;
      # nixos-install copies the closure out of this store by hash, and the
      # path registration at boot needs the store to be writable.
      virtualisation.writableStore = true;
      boot.supportedFilesystems.zfs = true;
      networking.hostId = "deadbeef";
      environment.systemPackages = [ nixieInstaller ];
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
    keys = "mkdir -p /run/nixie/keys && chmod 700 /run/nixie/keys && printf hunter2 >/run/nixie/keys/passphrase && printf 1234 >/run/nixie/keys/pin && printf wipe-me >/run/nixie/keys/duress && printf nixie >/run/nixie/keys/admin-password"
    installer.start(); installer.wait_for_unit("multi-user.target")
    installer.succeed("mkdir -p /var/lib/nixie/setup && cp ${state} /var/lib/nixie/setup/state.json")
    installer.succeed(keys + " && cp ${../keys/example-host.age} /run/nixie/keys/age.key")
    installer.succeed("cp -r ${siteSrc} /tmp/site && chmod -R u+w /tmp/site")
    env = "NIXIE_SITE=/tmp/site NIXIE_TOPLEVEL=${toplevel} NIXIE_DISKO=${disko}"
    installer.succeed(f"{env} nixie-phase 1 >&2 && {env} nixie-phase 2 >&2 && {env} nixie-phase 3 >&2")
    installer.shutdown()

    client.start(); client.wait_for_unit("multi-user.target")
    client.succeed("cp ${clientKey} /root/client_ed25519 && chmod 600 /root/client_ed25519")
    ssh = "ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 -i /root/client_ed25519 -p 2222 root@192.168.1.3"

    def remote_unlock(answers, gap=25):
        # Same relay as vm-encryption: each answer is fed to the prompt that
        # is pending, in order. The prompts themselves are drawn on tty0 for
        # the pictures, and nothing in the driver can type on that console.
        client.succeed("ip neigh flush all")
        client.wait_until_succeeds("nc -z 192.168.1.3 2222", timeout=300)
        feed = "; ".join(f"sleep {2 if i == 0 else gap}; printf %s\\n '{a}'" for i, a in enumerate(answers))
        client.succeed("timeout 180 sh -c \"(" + feed + "; sleep 5) | " + ssh + "\" || true")

    target.start()
    # The prompt is drawn on tty0, so the serial console the driver reads does
    # not carry it: waiting for its text there never returns. The initrd's SSH
    # port opening is the signal that the prompt is up, the same one
    # vm-encryption uses.
    client.succeed("ip neigh flush all")
    # Two VMs and a recording share the host; the initrd needs longer here
    # than the encryption check does.
    client.wait_until_succeeds("nc -z 192.168.1.3 2222", timeout=420)
    # The driver's own clock: the guest is in the initrd at the passphrase
    # prompt, where machine.sleep() would wait for a shell that only stage 2
    # starts.
    import time
    time.sleep(3); target.screenshot("boot-passphrase-first")
    remote_unlock(["hunter2", "hunter2"])
    target.wait_for_unit("multi-user.target")
    target.succeed(keys)
    # Bounded: succeed() waits for ever by default, and a phase that stops for
    # input would hang the whole run with nothing on screen to say so.
    target.succeed("nixie-phase 4 >&2", timeout=900)
    target.succeed("nixie-phase 6 >&2", timeout=900)
    target.succeed("cat /run/nixie/keys/attestation-qr | head -40 > /tmp/attestation-qr.txt || true")
    target.copy_from_vm("/tmp/attestation-qr.txt", "attestation-qr.txt")
    target.shutdown()

    target.start()
    # The relay answers in the background so the frames keep coming while the
    # PIN and passphrase prompts are on the screen being photographed. It is
    # detached with its pipes closed: a child holding them open would make
    # the driver wait for EOF instead of returning.
    client.succeed("ip neigh flush all")
    client.succeed(
        "systemd-run --collect --unit=nixie-unlock /bin/sh -c "
        "'until nc -z 192.168.1.3 2222; do sleep 1; done; "
        "{ sleep 2; printf \"1234\\n\"; sleep 25; printf \"hunter2\\n\"; sleep 5; } | " + ssh + "'"
    )
    import os
    os.makedirs("frames", exist_ok=True)
    i = 0
    t0 = time.time()
    while time.time() - t0 < 45:
        target.screenshot(f"frames/frame-{i:05d}")
        i += 1
        time.sleep(0.1)
        if i == 60: target.screenshot("boot-attestation-code")
        if i == 120: target.screenshot("boot-pin-prompt")
        if i == 220: target.screenshot("boot-passphrase-prompt")
    target.wait_for_unit("multi-user.target")
    target.screenshot("boot-front-panel")
  '';
}
