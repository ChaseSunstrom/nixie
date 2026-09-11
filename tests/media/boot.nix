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
          };
          nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:02" ];
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
    system.name = "nixie-media-boot";
    virtualisation.diskImage = "./target.qcow2";
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
    installer = {
      imports = [ shared ];
      virtualisation.emptyDiskImages = [ 1024 ];
      virtualisation.rootDevice = "/dev/vdc";
      virtualisation.fileSystems."/".autoFormat = true;
      virtualisation.useNixStoreImage = true;
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

    target.start()
    target.wait_for_console_text("Please enter passphrase")
    target.sleep(1); target.screenshot("boot-passphrase-first")
    target.send_chars("hunter2\n"); target.wait_for_console_text("Please enter passphrase for disk.*rpool"); target.send_chars("hunter2\n")
    target.wait_for_unit("multi-user.target")
    target.succeed(keys); target.succeed("nixie-phase 4 >&2 && nixie-phase 6 >&2")
    target.succeed("cat /run/nixie/keys/attestation-qr | head -40 > /tmp/attestation-qr.txt || true")
    target.copy_from_vm("/tmp/attestation-qr.txt", "attestation-qr.txt")
    target.shutdown()

    target.start()
    import os, time
    os.makedirs("frames", exist_ok=True)
    i = 0
    t0 = time.time()
    while time.time() - t0 < 45:
        target.screenshot(f"frames/frame-{i:05d}")
        i += 1
        time.sleep(0.1)
        if i == 60: target.screenshot("boot-attestation-code")
        if i == 120: target.screenshot("boot-pin-prompt"); target.send_chars("1234\n")
        if i == 220: target.screenshot("boot-passphrase-prompt"); target.send_chars("hunter2\n")
    target.wait_for_unit("multi-user.target")
    target.screenshot("boot-front-panel")
  '';
}
