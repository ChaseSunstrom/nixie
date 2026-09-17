# Hardware change and recovery on an installed server: a USB device plugged
# in after setup is blocked, `nixie security reenroll` lets a keyboard
# through while it runs, `nixie usb` lists and allows the device in the site,
# and `nixie apply` lets it through. (The TPM-reset and recovery-key part is
# in vm-encryption, where an installed encrypted target exists.)
{
  pkgs,
  inputs,
  nixieLib,
  exampleSite,
  nixieCli,
}:
let
  inherit (pkgs) lib;
  common = {
    imports = nixieLib.hostModules ../../examples/site "server" exampleSite.hosts.server ++ [
      ./qemu.nix
    ];
    virtualisation.sharedDirectories.nixie-site = {
      source = "${lib.cleanSource ../../examples/site}";
      target = "/etc/nixie/site";
    };
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
    # The test VM boots its kernel directly and has no mounted ESP, so a
    # generation switch must not try to install the boot loader.
    boot.loader.systemd-boot.enable = lib.mkForce false;
    nixie.network.bridge.uplinks = lib.mkForce [ "52:54:00:12:01:01" ];
    nixie.network.bridge.mode = "managed-nat";
    nixie.network.address = "192.168.1.1/24";
    nixie.incus.pools.default = {
      driver = "dir";
      source = "/var/lib/incus/storage-pools/default";
    };
    nixie.guests = lib.mkForce { };
    # The facts the site declares must name what this VM actually has, so
    # drift is a real signal rather than noise from the example's by-id paths.
    nixie.disks.system = lib.mkForce "/dev/vda";
    # A spare disk for `nixie hardware add-disk`.
    virtualisation.emptyDiskImages = [ 512 ];
    boot.supportedFilesystems.zfs = true;
    networking.hostId = "8425e349";
    environment.systemPackages = [
      nixieCli
      pkgs.git
      pkgs.jq
    ];
  };
  # The generation `nixie apply` switches to after `nixie usb allow`.
  allowed = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {
      inherit inputs;
    };
    modules = [
      "${inputs.nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
      "${inputs.nixpkgs}/nixos/modules/testing/test-instrumentation.nix"
      common
      { nixie.security.hardening.usbguard.allow = [ "0627:0001" ]; }
    ];
  };
in
pkgs.testers.runNixOSTest {
  name = "vm-hardware";
  nodes.host = {
    imports = [ common ];
    system.extraDependencies = [ allowed.config.system.build.toplevel ];
  };
  # A host still in setup: its kiosk needs a pointer as well as a keyboard.
  # The terminal front end keeps a browser out of a test about USB rules.
  nodes.setup = {
    imports = [ common ];
    nixie.setup.pending = true;
    nixie.setup.frontEnd = "terminal";
  };

  testScript = ''
    import json
    allowed = "${allowed.config.system.build.toplevel}"

    host.wait_for_unit("multi-user.target")
    host.wait_for_unit("usbguard.service")
    host.wait_for_unit("incus.service")
    host.succeed("nix-env --profile /nix/var/nix/profiles/system --set \"$(readlink -f /run/current-system)\"")
    host.succeed("cp -r /etc/nixie/site /tmp/site && chmod -R u+w /tmp/site && cd /tmp/site && git init -q && git config user.name t && git config user.email t@t && git add -A && git commit -qm init")

    with subtest("during setup a mouse and a touchscreen plugged in later are allowed"):
        setup.wait_for_unit("usbguard.service")
        # The root hub has two ports and the tablet, QEMU's absolute pointer,
        # holds the first; each device is plugged into the second in turn.
        setup.send_monitor_command("device_add usb-mouse,id=mouse1,bus=usb-bus.0,port=2")
        setup.wait_until_succeeds("usbguard list-devices -a | grep -q 'QEMU USB Mouse'", timeout=60)
        setup.send_monitor_command("device_del mouse1")
        setup.wait_until_succeeds("! usbguard list-devices | grep -q 'QEMU USB Mouse'", timeout=60)
        setup.send_monitor_command("device_add usb-kbd,id=kbd0,bus=usb-bus.0,port=2")
        setup.wait_until_succeeds("usbguard list-devices -a | grep -q 'QEMU USB Keyboard'", timeout=60)
        out = setup.succeed("usbguard list-devices")
        print(out)
        assert "block" not in out, out

    with subtest("devices present at the first start are allowed; one plugged in later is blocked"):
        host.succeed("test -s /var/lib/usbguard/setup-rules.conf")
        host.succeed("usbguard list-devices -a | grep -q 'QEMU USB Tablet'")
        # On a free port of the root hub: without a port QEMU inserts a hub first,
        # and a blocked hub hides everything behind it.
        host.send_monitor_command("device_add usb-kbd,id=kbd1,bus=usb-bus.0,port=2")
        host.wait_until_succeeds("usbguard list-devices -b | grep -q 'QEMU USB Keyboard'", timeout=60)

    with subtest("reenroll lets a waiting keyboard through and cleans up after itself"):
        # Nothing is enabled on this host, so the phases have nothing to do;
        # the keyboard handling around them is what is under test.
        out = host.succeed("nixie security reenroll 2>&1")
        print(out)
        assert "re-enrolment complete" in out, out
        host.succeed("usbguard list-devices -a | grep -q 'QEMU USB Keyboard'")
        host.succeed("test ! -e /var/lib/nixie/reenroll")
        host.fail("usbguard list-rules | grep -q '03:00:01'")
        host.send_monitor_command("device_del kbd1")
        host.send_monitor_command("device_add usb-kbd,id=kbd2,bus=usb-bus.0,port=2")
        host.wait_until_succeeds("usbguard list-devices -b | grep -q 'QEMU USB Keyboard'", timeout=60)

    with subtest("the rescue network, hardware scan, drift and add-disk"):
        # A card whose address is not in hardware.nix still gets an address.
        host.succeed("test -e /etc/systemd/network/90-nixie-rescue.network")
        host.succeed("grep -q 'DHCP=yes' /etc/systemd/network/90-nixie-rescue.network")
        host.succeed("grep -q 'RouteMetric=2048' /etc/systemd/network/90-nixie-rescue.network")
        scan = host.succeed("nixie hardware scan 2>&1")
        print(scan)
        assert "uplinks" in scan and "gpu" in scan and "/dev/vda present" in scan, scan
        assert "matches" in scan, scan
        doc = host.succeed("nixie doctor || true")
        print(doc)
        assert "hardware" in doc and "matches the site" in doc, doc
        # A disk the site already declares is never reformatted.
        rc, out = host.execute("nixie hardware add-disk /dev/vda spare 2>&1")
        print(rc, out)
        assert rc == 3 and "already declared" in out, (rc, out)
        # A new one is formatted and mounted.
        # A name ZFS keeps for itself is refused before anything is destroyed.
        rc, out = host.execute("printf 'vdb\n' | nixie hardware add-disk /dev/vdb spare 2>&1")
        print(rc, out)
        assert rc == 2 and "keeps for itself" in out, (rc, out)
        # It asks for the disk's name before destroying anything.
        host.succeed("printf 'vdb\n' | nixie hardware add-disk /dev/vdb scratch >&2")
        host.succeed("zpool list scratch >/dev/null && mountpoint -q /data/scratch")
        host.succeed("touch /data/scratch/it-works")

    with subtest("the machine having moved on shows up as drift"):
        # A generation that declares a card this machine does not have.
        host.succeed("cp /etc/nixie/hardware.json /tmp/facts.json")
        host.succeed("jq '.uplinks = [\"02:00:00:00:00:99\"]' /tmp/facts.json > /tmp/drift.json")
        host.succeed("mount --bind /tmp/drift.json /etc/nixie/hardware.json")
        doc = host.succeed("nixie doctor || true")
        print(doc)
        assert "DRIFT" in doc and "uplink:02:00:00:00:00:99" in doc, doc
        scan = host.succeed("nixie hardware scan 2>&1")
        assert "missing: 02:00:00:00:00:99" in scan or "missing:02:00:00:00:00:99" in scan or "02:00:00:00:00:99" in scan, scan
        host.succeed("umount /etc/nixie/hardware.json")

    with subtest("nixie usb lists the block, allow writes the site, apply lets it through"):
        out = host.succeed("nixie usb")
        print(out)
        assert "0627:0001" in out and "QEMU USB Keyboard" in out, out
        j = json.loads(host.succeed("nixie usb --json"))
        assert j[0]["device"] == "0627:0001" and j[0]["name"] == "QEMU USB Keyboard", j
        doc = host.succeed("nixie doctor || true")
        print(doc)
        assert "BLOCKED" in doc, doc
        host.succeed("NIXIE_SITE=/tmp/site nixie usb allow 0627:0001 >&2")
        host.succeed("grep -q '\"0627:0001\"' /tmp/site/hosts/server/usb.nix")
        host.succeed("git -C /tmp/site log -1 --format=%s | grep -q 'usb: allow 0627:0001'")
        # A second allow of the same device changes nothing.
        host.succeed("NIXIE_SITE=/tmp/site nixie usb allow 0627:0001 >&2")
        assert host.succeed("grep -c 0627:0001 /tmp/site/hosts/server/usb.nix").strip() == "1"
        host.succeed(f"NIXIE_SITE=/tmp/site NIXIE_TOPLEVEL={allowed} nixie apply --yes >&2")
        host.wait_until_succeeds("usbguard list-devices -a | grep -q 'QEMU USB Keyboard'", timeout=60)
        doc = host.succeed("nixie doctor || true")
        print(doc)
        assert "BLOCKED" not in doc, doc
  '';
}
