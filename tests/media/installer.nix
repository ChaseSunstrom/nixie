# Media: the installer. The ISO console banner (tty2), the kiosk wizard on
# the installer's own screen, and every wizard step from a LAN browser
# through Playwright, then the continuation steps after the reboot.
{
  pkgs,
  inputs,
  self,
  nixieLib,
  exampleSite,
}:
let
  packages = self.packages.x86_64-linux;
  py = pkgs.python3.withPackages (p: [ p.playwright ]);
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
          nixie.security.encryption.enable = true;
          nixie.setup.pending = true;
          nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:03" ];
          nixie.network.address = "192.168.1.3/24";
          nixie.disks.system = lib.mkForce "/dev/vda";
          boot.kernelParams = lib.mkAfter [ "console=ttyS0" ];
        }
      )
    ];
  };
  shared = {
    # Relative paths resolve inside each node's own state directory; one level
    # up is the driver's directory, which both nodes share.
    virtualisation.diskImage = "../target.qcow2";
    virtualisation.diskSize = 8 * 1024;
    # Phase 3 evaluates and copies the whole system here; at 3 GB with the
    # installer's compressed swap the kernel fell over mid-copy.
    virtualisation.memorySize = 6144;
    virtualisation.cores = 4;
    virtualisation.useEFIBoot = true;
    virtualisation.tpm.enable = true;
  };
  wizard = pkgs.writeText "wizard.py" ''
    import asyncio, os, re, sys
    from playwright.async_api import async_playwright
    OUT = "/tmp/media"; os.makedirs(OUT, exist_ok=True)
    base = sys.argv[1]; code = sys.argv[2]; mode = sys.argv[3]
    async def shot(page, name): await page.wait_for_timeout(1200); await page.screenshot(path=f"{OUT}/installer-{name}.png")
    async def main():
        async with async_playwright() as p:
            b = await p.chromium.launch(args=["--ignore-certificate-errors"])
            page = await (await b.new_context(viewport={"width": 1280, "height": 900}, ignore_https_errors=True)).new_page()
            page.on("response", lambda r: print("RESP", r.status, r.url, flush=True) if "/api/" in r.url else None)
            await page.goto(base); await shot(page, "pair" if mode != "continuation" else "continuation-pair")
            await page.fill("input", code)
            # "text=Pair" matches the panel's own heading, "Pair this browser",
            # and clicking a heading does nothing: name the button.
            await page.click("button:has-text(\"Pair\")")
            # Pairing is done when its own input is gone: the continuation view
            # returns before the step heading, so waiting for an h1 hangs there.
            await page.wait_for_selector("input[placeholder=\"123456\"]", state="detached", timeout=30000)
            await page.wait_for_timeout(1500)
            if mode == "continuation":
                await shot(page, "continuation"); await b.close(); return
            await shot(page, "profile")
            await page.click("button:has-text(\"Next\")"); await shot(page, "hardware")
            # Say which step the wizard is actually on if the disks are not there.
            try:
                await page.wait_for_selector("input[name=disk]", timeout=20000)
            except Exception:
                body = await page.evaluate("document.body.innerText")
                print("WIZARD STUCK, page says:", repr(body)[:1500], flush=True)
                raise
            # The first radio is whatever the kernel lists first, which here is
            # a 4 KB floppy; name the disk this VM is meant to be installed on.
            await page.click("label:has-text(\"virtio-root\") input[name=disk]")
            await page.click("input[type=checkbox]"); await page.click("button:has-text(\"Next\")"); await shot(page, "name")
            await page.fill("input[placeholder*=lowercase]", "server"); await page.click("button:has-text(\"Next\")"); await shot(page, "security")
            # Security holds the administrator as well: without the name and
            # both secrets its Next button stays disabled.
            await page.fill(".field:has-text(\"Administrator name\") input", "admin")
            await page.fill(".field:has-text(\"Administrator password\") input", "nixie")
            await page.fill(".field:has-text(\"Disk passphrase\") input", "hunter2")
            await page.click("button:has-text(\"Next\")"); await shot(page, "network")
            await page.click("button:has-text(\"Next\")"); await shot(page, "services")
            # Review writes the site and evaluates the host before Install unlocks.
            await page.click(".wizard-foot .btn.primary")
            await page.wait_for_selector(".status.ok", timeout=900000); await shot(page, "review")
            await page.click("button:has-text(\"Continue to install\")"); await shot(page, "install-ready")
            # The stepper names its last step Install too; the action is the primary button.
            await page.click("button.btn.primary:has-text(\"Install\")"); await page.wait_for_timeout(4000); await shot(page, "install-streaming")
            done = False
            for _ in range(120):
                if await page.query_selector("button:has-text(\"Restart now\")"):
                    done = True
                    break
                await page.wait_for_timeout(5000)
            await shot(page, "install-done")
            # Carrying on regardless left the target with nothing to boot and
            # the run hanging at its passphrase prompt half an hour later.
            if not done:
                print("INSTALL DID NOT FINISH:",
                      repr(await page.evaluate("document.body.innerText"))[-2500:], flush=True)
                raise SystemExit("the wizard never reported phase 3 done")
            await b.close()
    asyncio.run(main())
  '';
in
pkgs.testers.runNixOSTest {
  name = "media-installer";
  enableOCR = true;
  nodes = {
    client = {
      environment.systemPackages = [
        py
        pkgs.curl
      ];
      environment.variables.PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
      environment.variables.PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "1";
    };
    installer = {
      imports = [
        shared
        ../../installer/installer-system.nix
      ];
      nixie.installer = {
        inherit packages;
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
      # nixos-install copies the closure out of this store by hash, and the
      # path registration at boot needs the store to be writable.
      virtualisation.writableStore = true;
      virtualisation.efi.keepVariables = false;
      virtualisation.resolution = {
        x = 1280;
        y = 800;
      };
      networking.firewall.allowedTCPPorts = [ 9443 ];
    };
    target = {
      imports = [ shared ];
      virtualisation.useBootLoader = true;
      virtualisation.useDefaultFilesystems = false;
      virtualisation.efi.keepVariables = false;
      virtualisation.resolution = {
        x = 1280;
        y = 800;
      };
      virtualisation.fileSystems."/" = {
        device = "/dev/disk/by-label/never-used";
        fsType = "ext4";
      };
    };
  };
  testScript = ''
    import re
    client.start(); installer.start()
    installer.wait_for_unit("nixie-setup.service"); installer.wait_for_open_port(9443)
    installer.wait_for_unit("cage-tty1.service")
    installer.wait_for_text("(Profile|Pair|nixie)", timeout=300)
    installer.screenshot("installer-kiosk-wizard")
    installer.send_key("ctrl-alt-f2"); installer.sleep(3); installer.screenshot("installer-console-banner"); installer.send_key("ctrl-alt-f1")
    # What the wizard's hardware step will be given, straight from the source.
    print("DISCOVER:", installer.succeed("nixie-discover 2>&1 || true")[:1200])
    banner = installer.succeed("cat /var/lib/nixie/setup/banner.txt")
    code = re.findall(r"Pairing code: (\d{6})", banner)[0]
    client.wait_until_succeeds("curl -sk https://192.168.1.2:9443/api/pair | grep -q needsCode", timeout=120)
    client.succeed(f"python3 ${wizard} https://192.168.1.2:9443/ {code} iso >&2")
    client.copy_from_vm("/tmp/media", "media-lan")
    installer.screenshot("installer-kiosk-after-install")
    installer.shutdown()
    target.start()
    target.wait_for_console_text("Please enter passphrase"); target.screenshot("installer-target-passphrase")
    target.send_console("hunter2\n")
    target.wait_for_unit("nixie-setup.service"); target.wait_for_open_port(9443)
    target.wait_for_unit("cage-tty1.service"); target.wait_for_text("(First boot|Finished|nixie)", timeout=300)
    target.screenshot("installer-continuation-kiosk")
    banner = target.succeed("cat /var/lib/nixie/setup/banner.txt")
    code = re.findall(r"Pairing code: (\d{6})", banner)[0]
    client.succeed(f"python3 ${wizard} https://192.168.1.3:9443/ {code} continuation >&2")
    client.copy_from_vm("/tmp/media", "media-continuation")
  '';
}
