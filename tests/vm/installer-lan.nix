# The graphical path over the LAN: an installer VM (the ISO's system) with
# the setup service and the kiosk, driven from a second VM through the paired
# HTTPS API exactly as the wizard does; the kiosk's screen is read back with
# OCR. The installed disk then boots into the setup generation and the
# continuation phases run through the same API.
{
  pkgs,
  inputs,
  self,
  nixieLib,
  exampleSite,
}:
let
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
          nixie.security.encryption.enable = true;
          nixie.setup.pending = true;
          nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:03" ];
          nixie.network.address = "192.168.1.3/24";
          nixie.disks.system = lib.mkForce "/dev/vda";
          boot.kernelParams = lib.mkAfter [ "console=ttyS0" ];
          environment.systemPackages = [ packages.nixie-cli ];
        }
      )
    ];
  };
  shared = {
    # Relative paths resolve inside each node's own state directory; one level
    # up is the driver's directory, which both nodes share.
    virtualisation.diskImage = "../target.qcow2";
    virtualisation.diskSize = 8 * 1024;
    virtualisation.memorySize = 3072;
    virtualisation.cores = 4;
    virtualisation.useEFIBoot = true;
    virtualisation.tpm.enable = true;
  };
in
pkgs.testers.runNixOSTest {
  name = "vm-installer-lan";
  enableOCR = true;
  nodes = {
    client = {
      environment.systemPackages = [
        pkgs.curl
        pkgs.jq
      ];
    };
    installer = {
      imports = [
        shared
        ../../installer/installer-system.nix
      ];
      nixie.installer = {
        inherit packages;
        platform = self;
        toplevel = "${target.config.system.build.toplevel}";
        disko = "${target.config.system.build.diskoScript}";
      };
      system.extraDependencies = [
        target.config.system.build.toplevel
        target.config.system.build.diskoScript
      ];
      virtualisation.emptyDiskImages = [ 1024 ];
      # Drive order: target disk, then this empty disk.
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
      virtualisation.fileSystems."/" = {
        device = "/dev/disk/by-label/never-used";
        fsType = "ext4";
      };
    };
  };

  testScript = ''
    import json, re

    def api(method, path, data=None, raw=False):
        body = f"-d '{json.dumps(data)}'" if data is not None else ""
        out = client.succeed(f"curl -sk -b /tmp/c -c /tmp/c -X {method} -H 'Content-Type: application/json' {body} https://192.168.1.2:9443{path}")
        return out if raw else json.loads(out)

    def phase(n, data=None):
        out = api("POST", f"/api/phase/{n}", data or {}, raw=True)
        print(out[-2000:])
        m = re.search(r'event: done\ndata: (.*)', out)
        return json.loads(m.group(1))["rc"] if m else 1

    def pair():
        banner = installer.succeed("cat /var/lib/nixie/setup/banner.txt")
        code = re.findall(r"Pairing code: (\d{6})", banner)[0]
        assert "Certificate fingerprint" in banner and "https://192.168.1.2:9443" in banner, banner
        assert api("POST", "/api/pair", {"code": code})["ok"]
        client.fail(f"curl -sk -X POST -H 'Content-Type: application/json' -d '{{\"code\": \"{code}\"}}' https://192.168.1.2:9443/api/pair | grep -q ok")  # single use

    client.start()
    installer.start()
    installer.wait_for_unit("nixie-setup.service")
    installer.wait_for_open_port(9443)
    client.wait_until_succeeds("curl -sk https://192.168.1.2:9443/api/pair | grep -q needsCode", timeout=120)

    with subtest("the kiosk shows the wizard on the installer's own screen"):
        installer.wait_for_unit("cage-tty1.service")
        installer.wait_for_text("(Profile|Pair|nixie)", timeout=300)
        installer.screenshot("kiosk-wizard")

    with subtest("pair from the LAN with the single-use code"):
        pair()
        hw = api("GET", "/api/hardware")
        assert any(d["path"] == "/dev/vda" for d in hw["disks"]), hw
        # Every disk the kernel has must be offered. A disk with no
        # /dev/disk/by-id link used to be dropped from this list entirely,
        # which leaves the wizard with nothing to install on.
        disks = installer.succeed("lsblk -d -n -o TYPE,PATH").splitlines()
        paths = sorted(ln.split()[1] for ln in disks if ln.split()[0] == "disk")
        assert sorted(d["path"] for d in hw["disks"]) == paths, (hw["disks"], paths)
        opts = api("GET", "/api/options")
        assert any(o["path"] == "nixie.security.encryption.enable" and o["section"] == "security" for o in opts)

    with subtest("configure, plan, install"):
        api("POST", "/api/secrets", {"passphrase": "hunter2", "admin-password": "nixie"})
        api("POST", "/api/config", {"host": "server", "profile": "server", "systemDisk": "/dev/vda", "uplinks": ["52:54:00:12:01:03"], "settings": {"nixie.auth.admin.name": "admin", "nixie.security.encryption.enable": True}})
        assert phase(1) == 0
        plan = api("GET", "/api/plan")
        assert 'nixie.disks.system = "/dev/vda"' in plan["hardware"] and "nixie.security.encryption.enable = true" in plan["site"], plan
        assert phase(2) == 0
        assert phase(3) == 0
        installer.succeed("test -e /var/lib/nixie/setup/3.done")
        installer.shutdown()

    with subtest("first boot lands in the setup generation and continues over the same URL"):
        target.start()
        target.wait_for_console_text("Please enter passphrase")
        target.send_console("hunter2\n")
        target.wait_for_unit("nixie-setup.service")
        target.succeed("test -e /var/lib/nixie/setup/3.done && test -e /var/lib/nixie/age.key")
        # nixie-setup.service exists only in the setup generation, so being active proves the boot entry.
        target.wait_for_open_port(9443)
        banner = target.succeed("cat /var/lib/nixie/setup/banner.txt")
        code = re.findall(r"Pairing code: (\d{6})", banner)[0]
        client.succeed(f"curl -sk -c /tmp/c2 -X POST -H 'Content-Type: application/json' -d '{{\"code\": \"{code}\"}}' https://192.168.1.3:9443/api/pair | grep -q ok")
        for n in (4, 5, 6, 7):
            if n == 6:  # the wizard asks for the passphrase again before TPM enrolment
                client.succeed("curl -sk -b /tmp/c2 -X POST -H 'Content-Type: application/json' -d '{\"passphrase\": \"hunter2\"}' https://192.168.1.3:9443/api/secrets")
            out = client.succeed(f"curl -sk -b /tmp/c2 -X POST -H 'Content-Type: application/json' -d '{{}}' https://192.168.1.3:9443/api/phase/{n}")
            assert '"rc": 0' in out, out
        target.succeed("test -e /var/lib/nixie/setup/7.done")
        st = json.loads(client.succeed("curl -sk -b /tmp/c2 https://192.168.1.3:9443/api/state"))
        assert st["mode"] == "continuation" and 7 in st["done"], st
  '';
}
