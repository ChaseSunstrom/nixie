# Every check. VM tests live under vm/, evaluation-only sites under sites/.
{
  pkgs,
  self,
  inputs,
}:
let
  inherit (pkgs) lib;
  nixieLib = import ../lib { inherit inputs self; };
  src = lib.cleanSource ../.;

  exampleSite = import ../examples/site/site.nix;
  desktopSite = import ../examples/desktop-site/site.nix;

  testHost =
    siteDir: site: name:
    inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
      };
      modules = nixieLib.hostModules siteDir name site.hosts.${name};
    };

  server = testHost ../examples/site exampleSite "server";
  laptop = testHost ../examples/desktop-site desktopSite "laptop";
  # A desktop fresh from the installer, with the setup generation still in
  # its closure: that is where the setup tools' own copies would show.
  laptopInSetup = testHost ../examples/desktop-site {
    hosts.laptop = desktopSite.hosts.laptop // {
      settings = {
        imports = [ desktopSite.hosts.laptop.settings ];
        nixie.setup.pending = true;
      };
    };
  } "laptop";

  # A closure must not contain any of the given package name fragments.
  closureFree =
    name: toplevel: forbidden:
    pkgs.runCommand "profile-${name}"
      {
        closure = pkgs.closureInfo { rootPaths = [ toplevel ]; };
        inherit forbidden;
      }
      ''
        set -euo pipefail
        for f in $forbidden; do
          # Suffixed names count too: incus-lts-client-7.0.1 is Incus.
          if grep -E -- "-$f(-[a-z]+)*-[0-9]" "$closure/store-paths"; then
            echo "closure of ${name} contains $f" >&2
            exit 1
          fi
        done
        touch "$out"
      '';

  # Throwaway sites: the platform must evaluate for every hardware shape.
  matrix = lib.mapAttrs (
    file: _:
    # The check is that every combination evaluates; the context is dropped so
    # writing the paths does not pull each host's whole build closure.
    builtins.unsafeDiscardStringContext
      (testHost ./sites (import (./sites + "/${file}")) "host").config.system.build.toplevel.drvPath
  ) (lib.filterAttrs (n: _: lib.hasSuffix ".nix" n) (builtins.readDir ./sites));

  # Units the platform authors, taken from the built systems: every one must
  # analyse at "OK" or better, or carry a `# exposure:` comment in its module
  # naming why it needs more. The documented list is checked against the
  # sources so a comment cannot go missing silently.
  platformUnits =
    sys:
    lib.filterAttrs (
      n: u: lib.hasPrefix "nixie-" n && lib.hasSuffix ".service" n && (u.enable or true)
    ) sys.config.systemd.units;
  documentedExposure = [
    "nixie-egress"
    "nixie-attestation-reseal"
    "nixie-notices"
    "nixie-update"
    "nixie-backup-check"
    "nixie-gc"
    "nixie-fetch"
    "nixie-setup"
    "nixie-tailscale-serve"
    "nixie-oath-users"
    "nixie-panel"
    "nixie-kiosk-gate"
    "nixie-terminal"
    "nixie-banner"
  ];
  kioskServer = testHost ../examples/site {
    hosts.server = exampleSite.hosts.server // {
      settings = {
        imports = [ exampleSite.hosts.server.settings ];
        nixie.console.kiosk.enable = true;
        nixie.hostUi.enable = true;
        nixie.auth.secondFactor = "totp";
        nixie.monitoring.enable = true;
        nixie.backups = {
          enable = true;
          repository = "/var/backup";
          passwordFile = "/etc/none";
        };
        nixie.network.tailscale.enable = true;
      };
    };
  } "server";
  # The wizard's every-feature server adds the security units (attestation
  # among them) that the kiosk server does not turn on.
  unitsToCheck =
    platformUnits kioskServer
    // platformUnits laptop
    // platformUnits (testHost ./sites (import ./sites/wizard-server.nix) "host");

  nixieOptions = lib.filterAttrs (n: _: n != "_module") server.options.nixie;
  undocumented = lib.filter (o: (o.description or "") == "") (lib.collect lib.isOption nixieOptions);
  # The wizard shows options by label (lib/wizard.nix); one without an entry
  # would appear as a bare option path, and a stale entry hides a rename.
  wizardLabels = import ../lib/wizard.nix;
  wizardPaths = map (o: lib.showOption o.loc) (
    lib.filter (o: o ? nixieUi.section) (lib.collect lib.isOption nixieOptions)
  );
  unlabelled = lib.filter (p: !(wizardLabels ? ${p})) wizardPaths;
  staleLabels = lib.filter (p: !(lib.elem p wizardPaths)) (lib.attrNames wizardLabels);
  # The hardened setup's list lives in the wizard's own source; a typo there
  # would quietly turn nothing on.
  hardenedPaths = lib.filter (p: p != "") (
    map (m: lib.head (m ++ [ "" ])) (
      builtins.filter lib.isList (
        builtins.split ''"(nixie\.[a-zA-Z0-9_.]+)": '' (
          lib.elemAt (lib.splitString "};" (lib.elemAt (lib.splitString "const HARDENED" (builtins.readFile ../ui/src/setup/main.tsx)) 1)) 0
        )
      )
    )
  );
  unknownHardened = lib.filter (p: !(lib.elem p wizardPaths)) hardenedPaths;
  # That list names the TPM, so it must only be applied to a machine that has
  # one. Applying it whole turned the TPM on where there is none, which gives
  # the disk a layer nothing can open: the install finishes and the machine
  # stops in emergency mode at its first start. Two things keep that shut --
  # the setup filters the list by what this machine is offered, and the
  # Security step refuses the combination however else it was reached.
  wizardSource = builtins.readFile ../ui/src/setup/main.tsx;
  filtersHardened = lib.hasInfix "Object.entries(HARDENED).filter(([path]) => offeredPath(path))" wizardSource;
  refusesAbsentTpm = lib.hasInfix "This machine has no TPM, so these cannot work" wizardSource;
in
{
  fmt = pkgs.runCommand "fmt" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
    cd ${src}
    find . -name '*.nix' -print0 | xargs -0 nixfmt --check
    touch $out
  '';
  statix = pkgs.runCommand "statix" { nativeBuildInputs = [ pkgs.statix ]; } ''
    cd ${src}
    statix check .
    touch $out
  '';
  deadnix = pkgs.runCommand "deadnix" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
    deadnix --fail ${src}
    touch $out
  '';

  # The platform holds no hardware facts; the brief, the examples' generated
  # hardware files and tests are the only places they may appear. The
  # discovery script is code that enumerates by-id to write hardware.nix.
  no-hardware-facts =
    pkgs.runCommand "no-hardware-facts"
      {
        patterns = [
          "([0-9a-f]{2}:){5}[0-9a-f]{2}"
          "/dev/disk/by-(id|path|uuid)"
          "/dev/(sd|nvme|vd|mmcblk)[a-z0-9]"
          "[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\\.[0-9]"
          "\\b(enp[0-9]+s[0-9]+|eno[0-9]+|wlp[0-9]+s[0-9]+|wlan[0-9]|eth[0-9])\\b"
          "\\b(ThinkPad|Framework|Supermicro|ASRock|Gigabyte|MSI|ASUS)\\b"
        ];
      }
      ''
        cd ${src}
        status=0
        for p in $patterns; do
          # The gallery is generated screenshots and video: not source, and a
          # byte sequence in a PNG matching a pattern would read as a fact.
          if grep -rEn --binary-files=without-match \
              --exclude-dir=tests --exclude-dir=.git --exclude-dir=media \
              --exclude=NIXIE_PLATFORM_BRIEF.md --exclude=hardware.nix \
              --exclude=design-tokens.md --exclude=discover.sh -- "$p" .; then
            echo "hardware fact matching '$p' outside tests/ or hardware.nix" >&2
            status=1
          fi
        done
        [ $status = 0 ]
        touch $out
      '';

  option-docs =
    assert lib.assertMsg (undocumented == [ ])
      "undocumented nixie.* options: ${toString (map (o: lib.showOption o.loc) undocumented)}";
    assert lib.assertMsg (
      unlabelled == [ ]
    ) "wizard options without a label in lib/wizard.nix: ${toString unlabelled}";
    assert lib.assertMsg (
      staleLabels == [ ]
    ) "lib/wizard.nix labels options the wizard does not show: ${toString staleLabels}";
    assert lib.assertMsg (
      unknownHardened == [ ]
    ) "the wizard's hardened setup names options it does not show: ${toString unknownHardened}";
    assert lib.assertMsg (
      lib.length hardenedPaths > 5
    ) "the wizard's hardened setup list could not be read from main.tsx";
    assert lib.assertMsg filtersHardened
      "the wizard's hardened setup is applied unfiltered: on a machine with no TPM it would turn the TPM on, and the disk would get a layer nothing can open";
    assert lib.assertMsg refusesAbsentTpm
      "the wizard's Security step no longer refuses a TPM that is not there";
    pkgs.writeText "option-docs" (toString (lib.length (lib.collect lib.isOption nixieOptions)));

  # Every fenced block tagged `sh test` in the README runs against the
  # example site; a command that fails takes the README claim with it.
  readme =
    pkgs.runCommand "readme"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.bash
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.jq
        ];
        readme = ../README.md;
        site = lib.cleanSource ../examples/site;
        optionsJson = self.packages.x86_64-linux.nixie-setup.passthru.optionsJson;
        verification = ../VERIFICATION.md;
        # Names only: the check needs to know which gallery files exist, not
        # what is in them. Empty until `nix run .#media` has produced a
        # gallery and it has been committed.
        mediaFiles = toString (
          lib.optionals (builtins.pathExists ../docs/media) (lib.attrNames (builtins.readDir ../docs/media))
        );
      }
      ''
        python3 - <<'PY'
        import os, re, subprocess, sys, json
        readme = open(os.environ["readme"]).read()
        blocks = re.findall(r"```sh test\n(.*?)```", readme, re.S)
        assert blocks, "README has no `sh test` blocks"
        env = dict(os.environ, SITE=os.environ["site"])
        for b in blocks:
            r = subprocess.run(["bash", "-euo", "pipefail", "-c", b], env=env, capture_output=True, text=True, cwd=os.environ["site"])
            if r.returncode:
                sys.exit(f"README block failed:\n{b}\n{r.stdout}{r.stderr}")
        opts = {o["path"] for o in json.load(open(os.environ["optionsJson"]))}
        for m in set(re.findall(r"`(nixie\.[a-zA-Z0-9_.]+)`", readme)):
            base = m.rstrip(".")
            if base not in opts and not any(o.startswith(base + ".") for o in opts):
                sys.exit(f"README names an option that does not exist: {m}")
        ver = open(os.environ["verification"]).read()
        for anchor in re.findall(r"\]\(VERIFICATION\.md#([a-z0-9-]+)\)", readme):
            heading = " ".join(anchor.split("-"))
            if not re.search(r"^#+ .*" + re.escape(heading.split(" ")[0]), ver, re.M | re.I):
                sys.exit(f"README links to a VERIFICATION.md section that does not exist: {anchor}")
        media = set(os.environ["mediaFiles"].split())
        shown = set(re.findall(r"docs/media/([A-Za-z0-9._-]+)", readme))
        if media:
            missing = sorted(shown - media)
            if missing:
                sys.exit(f"README shows gallery files that are not in docs/media: {missing}")
        print(f"{len(blocks)} blocks ran, option names, verification links and {len(shown)} gallery files checked")
        PY
        touch $out
      '';

  # The wizard's drive picker offers what this check describes: a person must
  # not be offered swap or a locked container as a place to put a backup.
  setup-devices = pkgs.runCommand "setup-devices" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    cp ${../packages/nixie-setup/nixie-setup.py} setup.py
    python3 - <<'PY'
    import setup
    tree = {"blockdevices": [
        {"path": "/dev/sda", "type": "disk", "size": 500107862016, "model": "SYSTEM DISK", "rm": False, "children": [
            {"path": "/dev/sda1", "type": "part", "fstype": "vfat", "size": 536870912, "mountpoint": "/boot", "rm": False},
            {"path": "/dev/sda2", "type": "part", "fstype": "swap", "size": 8589934592, "rm": False},
            {"path": "/dev/sda3", "type": "part", "fstype": "crypto_LUKS", "size": 400000000000, "rm": False, "children": [
                {"path": "/dev/mapper/root", "type": "crypt", "fstype": "ext4", "size": 400000000000, "mountpoint": "/", "rm": False}]}]},
        {"path": "/dev/sdb", "type": "disk", "fstype": None, "size": 31000000000, "model": " Cruzer ", "rm": True, "children": [
            {"path": "/dev/sdb1", "type": "part", "fstype": "exfat", "label": "BACKUP", "size": 31000000000, "rm": True}]},
        {"path": "/dev/sdc", "type": "disk", "fstype": "iso9660", "label": "NIXIE", "size": 2000000000, "rm": True},
    ]}
    got = setup.block_devices(tree)
    assert [d["path"] for d in got] == ["/dev/sdb1", "/dev/mapper/root", "/dev/sda1"], got
    assert got[0]["label"] == "BACKUP" and got[0]["removable"], got[0]
    assert setup.block_devices({}) == []
    print("device listing checked")
    PY
    touch $out
  '';

  # The attestation code has to scan. tpm2-totp draws its own in ANSI colour,
  # which a browser prints as escape codes, so the page shows a QR made from
  # the URI tpm2-totp prints under it; this decodes that image again.
  # Still the design file's tokens: the brief calls that file the visual
  # source of truth, and this is the part of "matches the design" a machine
  # can hold.
  tokens-from-design =
    pkgs.runCommand "tokens-from-design" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        python3 ${./tokens-from-design.py} "${../design}/Nixie Front Panel.html" \
          ${../ui/src/tokens/tokens.json} | tee $out
      '';

  # One token set: what the design file gave, and the hex beside each one
  # that a toolkit, a terminal or a boot theme can read.
  tokens-agree =
    let
      tokens = import ../lib/tokens.nix { inherit lib; };
      resolved = pkgs.writeText "resolved-tokens.json" (
        builtins.toJSON (lib.genAttrs tokens.finishes tokens.forFinish)
      );
    in
    pkgs.runCommand "tokens-agree" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python3 ${./tokens-agree.py} ${../ui/src/tokens/tokens.json} ${resolved} | tee $out
    '';

  # The panel's own half of Declare, in demo mode: a page on a port, no
  # daemon and no VM, so it can run in the gate beside the evaluations.
  panel-declare =
    pkgs.runCommand "panel-declare"
      {
        nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.playwright ])) ];
        PLAYWRIGHT_BROWSERS_PATH = pkgs.playwright-driver.browsers;
      }
      ''
        cp -r ${self.packages.x86_64-linux.nixie-ui} bundle
        chmod -R u+w bundle
        python3 ${./panel-declare.py} bundle | tee $out
      '';

  setup-qr =
    pkgs.runCommand "setup-qr"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.qrencode
          pkgs.zbar
          pkgs.librsvg
        ];
      }
      ''
        cp ${../packages/nixie-setup/nixie-setup.py} setup.py
        python3 - <<'PY'
        import base64, subprocess, setup
        uri = "otpauth://totp/TPM2-TOTP?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP"
        printed = "\x1b[47m      \x1b[0m\n\x1b[47m  \x1b[40m  \x1b[47m  \x1b[0m\n\n" + uri + "\n"
        assert setup.otpauth_uri(printed) == uri, setup.otpauth_uri(printed)
        assert setup.otpauth_uri("no code here") == ""
        img = setup.qr_svg(uri)
        assert img.startswith("data:image/svg+xml;base64,"), img[:40]
        open("qr.svg", "wb").write(base64.b64decode(img.split(",", 1)[1]))
        subprocess.run(["rsvg-convert", "-w", "400", "-o", "qr.png", "qr.svg"], check=True)
        read = subprocess.run(["zbarimg", "-q", "--raw", "qr.png"], capture_output=True, text=True, check=True).stdout.strip()
        assert read == uri, read
        print("the attestation QR scans back to", read)
        PY
        touch $out
      '';

  # Phase 5 must never tell someone to turn Secure Boot on while the firmware
  # holds other keys: the machine then refuses to start ("Access Denied").
  # bootctl reports "disabled" alike for the vendor's keys and for ours, so
  # the phase looks for this machine's certificate in the PK variable.
  secure-boot-states =
    pkgs.runCommand "secure-boot-states"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.jq
          pkgs.openssl
          pkgs.coreutils
          pkgs.gnugrep
        ];
      }
      ''
        cp -r ${../installer} installer
        chmod -R u+w installer
        mkdir -p top/etc/nixie bin sb/keys/PK efivars
        echo '{"features":{"secureBoot":true}}' >top/etc/nixie/layout.json
        openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=ours -keyout /dev/null -out sb/keys/PK/PK.pem 2>/dev/null
        openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=vendor -keyout /dev/null -out vendor.pem 2>/dev/null
        pkvar=efivars/PK-8be4df61-93ca-11d2-aa0d-00e098032b8c
        # An EFI signature list: attributes, the list header, the certificate.
        pk() { { printf '\x27\x00\x00\x00'; head -c 44 /dev/zero; openssl x509 -in "$1" -outform DER; } >$pkvar; }
        printf '#!/bin/sh\ncat %s\n' "$PWD/status.txt" >bin/bootctl
        chmod +x bin/bootctl
        n=0
        run() { # expected exit, bootctl's Secure Boot line; a fresh state each time
          n=$((n + 1))
          st=state$n
          mkdir "$st"
          printf '%s\n' "$2" >status.txt
          rc=0
          PATH=$PWD/bin:$PATH NIXIE_SETUP_DIR=$PWD/$st NIXIE_TOPLEVEL=$PWD/top \
            NIXIE_EFIVARS=$PWD/efivars NIXIE_SBCTL=$PWD/sb \
            bash installer/phases/05-secure-boot.sh 2>log || rc=$?
          [ "$rc" = "$1" ] || { cat log; echo "'$2' with $3: expected $1, got $rc"; exit 1; }
          echo "'$2' with $3 -> $rc"
        }
        run 0 "  Secure Boot: enabled (user)" "any keys"
        test -e state1/5.done
        run 10 "  Secure Boot: disabled (setup)" "no keys"
        pk sb/keys/PK/PK.pem
        run 12 "  Secure Boot: disabled (disabled)" "this machine's PK"
        grep -q "turn Secure Boot on" log
        pk vendor.pem
        run 11 "  Secure Boot: disabled (disabled)" "the vendor's PK"
        grep -q "Custom" log && grep -q "Access Denied" log
        : >$pkvar
        run 11 "  Secure Boot: disabled (disabled)" "an empty PK variable"
        touch $out
      '';

  # `nixie secure-boot` on a machine whose start says "Access Denied": each
  # firmware state, and an unsigned boot file, said in its own words.
  secure-boot-report =
    pkgs.runCommand "secure-boot-report"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.jq
          pkgs.openssl
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.findutils
        ];
        cli = "${self.packages.x86_64-linux.nixie-cli}/bin/nixie";
      }
      ''
        mkdir -p top/etc/nixie bin sb/keys/PK sb/keys/db efivars boot/EFI/Linux boot/loader/keys/auto
        echo '{"features":{"secureBoot":true},"luks":[]}' >top/etc/nixie/layout.json
        openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=ours -keyout /dev/null -out sb/keys/PK/PK.pem 2>/dev/null
        openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=vendor -keyout /dev/null -out vendor.pem 2>/dev/null
        pkvar=efivars/PK-8be4df61-93ca-11d2-aa0d-00e098032b8c
        pk() { { printf '\x27\x00\x00\x00'; head -c 44 /dev/zero; openssl x509 -in "$1" -outform DER; } >$pkvar; }
        printf '#!/bin/sh\ncat %s\n' "$PWD/status.txt" >bin/bootctl
        chmod +x bin/bootctl
        answers() { # bootctl's line, what to expect in the answer
          printf '%s\n' "$1" >status.txt
          NIXIE_BOOTCTL=$PWD/bin/bootctl NIXIE_EFIVARS=$PWD/efivars NIXIE_SBCTL=$PWD/sb \
            NIXIE_ESP=$PWD/boot $cli secure-boot >out 2>&1 || true
          grep -q "$2" out || { cat out; echo "expected: $2"; exit 1; }
        }
        # Nothing enrolled and nothing staged: the keys have to be put there.
        answers "  Secure Boot: disabled (setup)" "no keys are staged"
        touch boot/loader/keys/auto/db.auth
        answers "  Secure Boot: disabled (setup)" "restart, and the boot loader enrols them"
        pk sb/keys/PK/PK.pem
        answers "  Secure Boot: disabled (disabled)" "turn Secure Boot on"
        pk vendor.pem
        answers "  Secure Boot: disabled (disabled)" "Custom"
        grep -q "Access Denied" out
        grep -q "installer stick" out
        # The same report about a machine that will not start, from
        # somewhere else: its disk opened, its own firmware still this one's.
        mkdir -p machine/var/lib
        ln -s "$PWD/sb" machine/var/lib/sbctl
        ln -s "$PWD/boot" machine/boot
        NIXIE_BOOTCTL=$PWD/bin/bootctl NIXIE_EFIVARS=$PWD/efivars \
          $cli secure-boot --at "$PWD/machine" >out 2>&1 || true
        grep -q "the system opened under $PWD/machine" out || { cat out; exit 1; }
        grep -q "Custom" out || { cat out; exit 1; }
        $cli secure-boot --at "$PWD/nowhere" >out 2>&1 && { cat out; exit 1; }
        grep -q "open the disk first" out || { cat out; exit 1; }
        touch $out
      '';

  # The committed reference must match what the module tree says.
  option-reference = pkgs.runCommand "option-reference" { } ''
    diff -u ${../docs/reference/options.md} ${self.packages.x86_64-linux.docs}/options.md
    touch $out
  '';

  # What someone meets before any VM test can: the file name, a boot entry for
  # each way of installing, both firmware kinds, and what the installer needs
  # to evaluate a site and draw text.
  iso-config =
    let
      iso = self.packages.x86_64-linux.nixie-iso.config;
      entry = n: iso.specialisation.${n}.configuration;
      facts = {
        "file name is nixie_<version>_<platform>.iso" =
          iso.image.fileName == "nixie_${self.lib.version}_x86_64-linux.iso"
          && self.packages.x86_64-linux.nixie-iso.name == iso.image.fileName;
        "boots on UEFI and BIOS" = iso.isoImage.makeEfiBootable && iso.isoImage.makeBiosBootable;
        "menu says Nixie" = iso.system.nixos.distroName == "Nixie";
        "graphical is the default entry" =
          iso.nixie.installer.mode == "graphical" && iso.nixie.kiosk.enable;
        "web and terminal entries" =
          lib.attrNames iso.specialisation == [
            "terminal"
            "web"
          ]
          && (entry "web").nixie.installer.mode == "web"
          && (entry "terminal").nixie.installer.mode == "terminal";
        "web entry has no kiosk" =
          !(entry "web").nixie.kiosk.enable && (entry "web").systemd.services ? nixie-setup;
        "terminal entry has no kiosk and no listener" =
          !(entry "terminal").nixie.kiosk.enable && !((entry "terminal").systemd.services ? nixie-setup);
        "nix can evaluate the site flake" = lib.all (f: lib.elem f iso.nix.settings.experimental-features) [
          "nix-command"
          "flakes"
        ];
        "the kiosk has fonts" = iso.fonts.fontconfig.enable;
        "phase 3 has swap to evaluate in" = iso.zramSwap.enable;
        "the platform's flake inputs are on the image" =
          let
            onImage = map toString iso.system.extraDependencies;
          in
          lib.all (i: lib.elem (toString i.outPath) onImage) (lib.attrValues inputs);
      };
      failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) facts);
    in
    assert lib.assertMsg (failed == [ ]) "iso-config: ${lib.concatStringsSep "; " failed}";
    pkgs.writeText "iso-config" (lib.concatStringsSep "\n" (lib.attrNames facts));

  # What an installed machine shows from power-on to Finish: no loader menu,
  # the splash with every prompt on it, and during setup the
  # front end chosen at the image's boot menu, on a desktop as on a server.
  boot-and-setup =
    let
      withSetup =
        frontEnd:
        (testHost ../examples/desktop-site {
          hosts.laptop = desktopSite.hosts.laptop // {
            settings = {
              imports = [ desktopSite.hosts.laptop.settings ];
              nixie.setup.pending = true;
              nixie.setup.frontEnd = frontEnd;
            };
          };
        } "laptop").config;
      setupOf = frontEnd: (withSetup frontEnd).specialisation.nixie-setup.configuration;
      duressHost = (testHost ./sites (import ./sites/wizard-server.nix) "host").config;
      tty = u: u.serviceConfig.TTYPath;
      facts = {
        "no loader menu" = laptop.config.boot.loader.timeout == 0 && server.config.boot.loader.timeout == 0;
        "the Nixie splash" =
          laptop.config.boot.plymouth.enable && laptop.config.boot.plymouth.theme == "nixie";
        # The code comes from the TPM, but this unit runs in front of every
        # disk prompt: ordered after a device unit for a TPM that never
        # appears, it would hold the prompt for the device timeout.
        "the attestation code never waits for a TPM in front of the prompt" =
          let
            unit = duressHost.boot.initrd.systemd.services.nixie-attestation;
          in
          !(lib.elem "dev-tpmrm0.device" (unit.after or [ ]))
          && !(lib.elem "dev-tpmrm0.device" (unit.wants or [ ]))
          && lib.elem "cryptsetup-pre.target" unit.before;
        "the splash with duress and attestation, asked by one agent" =
          let
            initrd = duressHost.boot.initrd.systemd;
          in
          duressHost.boot.plymouth.enable
          && initrd.services ? nixie-unlock
          && initrd.paths ? nixie-unlock
          && !initrd.services.systemd-ask-password-plymouth.enable
          && !initrd.paths.systemd-ask-password-plymouth.enable
          && lib.elem "systemd-ask-password-console.service" initrd.suppressedUnits
          && initrd.services.nixie-attestation.serviceConfig.Type == "simple"
          && lib.hasSuffix "/nixie-unlock" initrd.users.root.shell;
        "no text under the splash" =
          lib.elem "quiet" laptop.config.boot.kernelParams && !laptop.config.boot.initrd.verbose;
        "a theme Plymouth ships, by name" =
          (testHost ../examples/desktop-site {
            hosts.laptop = desktopSite.hosts.laptop // {
              settings = {
                imports = [ desktopSite.hosts.laptop.settings ];
                nixie.host.splashTheme.name = "spinner";
              };
            };
          } "laptop").config.boot.plymouth.theme == "spinner";
        "the splash and the greeter follow the finish" =
          let
            paper =
              (testHost ../examples/desktop-site {
                hosts.laptop = desktopSite.hosts.laptop // {
                  settings = {
                    imports = [ desktopSite.hosts.laptop.settings ];
                    nixie.desktop.finish = lib.mkForce "paper";
                  };
                };
              } "laptop").config;
            theme = c: (lib.head c.boot.plymouth.themePackages).drvPath;
          in
          theme paper != theme laptop.config
          && lib.hasInfix paper.nixie.desktop.tokens.s1 paper.programs.regreet.extraCss;
        "graphical setup: the wizard on screen, no desktop session yet" =
          (setupOf "graphical").nixie.kiosk.enable && !(setupOf "graphical").services.greetd.enable;
        "the desktop session after Finish" = laptop.config.services.greetd.enable;
        "web setup: the address on tty1" =
          !(setupOf "web").nixie.kiosk.enable
          && (setupOf "web").systemd.services ? nixie-banner
          && (setupOf "web").systemd.services ? nixie-setup;
        "terminal setup: the text wizard on tty1, nothing listening" =
          tty (setupOf "terminal").systemd.services.nixie-terminal == "/dev/tty1"
          && !((setupOf "terminal").systemd.services ? nixie-setup);
        "the plain entry says setup is unfinished" = lib.hasInfix "not finished" (withSetup "graphical")
        .services.getty.greetingLine;
        "the installer offers HyDE on the Desktop step" =
          (lib.findFirst (o: o.path == "nixie.desktop.hyde.enable") { } (
            lib.importJSON self.packages.x86_64-linux.nixie-setup.passthru.optionsJson
          )).section or null == "desktop";
      };
      failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) facts);
    in
    assert lib.assertMsg (failed == [ ]) "boot-and-setup: ${lib.concatStringsSep "; " failed}";
    pkgs.writeText "boot-and-setup" (lib.concatStringsSep "\n" (lib.attrNames facts));

  # Security keys: FIDO2 on the passphrase layer, which the passphrase still
  # opens, and SSH asking for the password after the key.
  hardware-keys =
    let
      withSettings =
        extra:
        (testHost ../examples/site {
          hosts.server = exampleSite.hosts.server // {
            settings = {
              imports = [
                exampleSite.hosts.server.settings
                extra
              ];
            };
          };
        } "server").config;
      host = withSettings {
        nixie.security.encryption.enable = true;
        nixie.security.fido2.enable = true;
        nixie.auth.ssh.keyAndPassword = true;
        nixie.auth.sshKeys = [ "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29t test" ];
      };
      pasted = withSettings { nixie.auth.sshKeys = [ "-----BEGIN OPENSSH PRIVATE KEY-----" ]; };
      sshd = host.services.openssh.settings;
      facts = {
        "the security key opens the passphrase layer" =
          lib.elem "fido2-device=auto" host.boot.initrd.luks.devices.rpool.crypttabExtraOpts
          && host.boot.initrd.systemd.fido2.enable;
        "phase 6 is told to enrol it" =
          (builtins.fromJSON host.environment.etc."nixie/layout.json".text).features.fido2;
        "SSH asks for the password after the key" =
          sshd.AuthenticationMethods == "publickey,password" && sshd.PasswordAuthentication;
        "a pasted private key is refused with the reason" = lib.any (
          a: !a.assertion && lib.hasInfix "private key" a.message
        ) pasted.assertions;
      };
      failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) facts);
    in
    assert lib.assertMsg (failed == [ ]) "hardware-keys: ${lib.concatStringsSep "; " failed}";
    pkgs.writeText "hardware-keys" (lib.concatStringsSep "\n" (lib.attrNames facts));

  # The headless install does not stop at the reboot: it waits for the
  # machine and hands over to the setup generation's own front end. The run
  # itself needs two machines (see VERIFICATION.md); this is the shape of the
  # script that does it.
  # The kexec branch's shape, cheaply: vm-deploy-kexec takes the branch end
  # to end, and this holds three things that were wrong until a test took it.
  deploy-kexecs = pkgs.runCommand "deploy-kexecs" { } ''
    s=${self.packages.x86_64-linux.deploy}/bin/nixie-deploy
    # It asks the target what it is, and only kexecs a machine that is not
    # already the ISO.
    grep -q 'test -e /etc/nixie-iso' "$s"
    # nixos-anywhere refuses to run at all without one of these, so the
    # branch aborted the moment anyone took it.
    grep -q 'nixos-anywhere --phases kexec --store-paths' "$s"
    # Which means the system has to be built before the kexec, not after.
    b=$(grep -n 'toplevel=''${NIXIE_TOPLEVEL' "$s" | head -1 | cut -d: -f1)
    k=$(grep -n 'nixos-anywhere --phases kexec' "$s" | head -1 | cut -d: -f1)
    [ "$b" -lt "$k" ] || { echo "the kexec comes before the system it hands over"; exit 1; }
    # A kexec gives the machine a new host key, and `accept-new` takes a key
    # it has never seen, not one that changed.
    f=$(grep -n 'ssh-keygen -R' "$s" | head -1 | cut -d: -f1)
    [ "$f" -gt "$k" ] || { echo "nothing forgets the host key the kexec replaced"; exit 1; }
    # And an image can be handed in, for a deploy host with no way out.
    grep -q 'NIXIE_KEXEC' "$s"
    touch $out
  '';

  deploy-continues = pkgs.runCommand "deploy-continues" { } ''
    s=${self.packages.x86_64-linux.deploy}/bin/nixie-deploy
    # In this order: reboot, forget the installer's host key, wait, hand over.
    grep -n 'systemctl reboot' "$s" >/dev/null
    grep -q 'ssh-keygen -R' "$s"
    grep -q 'exec ssh .* -t "$target" nixie-deploy --continue' "$s"
    r=$(grep -n 'systemctl reboot' "$s" | head -1 | cut -d: -f1)
    h=$(grep -n 'nixie-deploy --continue' "$s" | tail -1 | cut -d: -f1)
    [ "$h" -gt "$r" ] || { echo "the hand-over comes before the reboot"; exit 1; }
    # And the instruction that could not work is gone: the phases after the
    # first ran on the operator's own machine, not the target.
    ! grep -q 'nixie-phase 4; nixie-phase 5' "$s"
    touch $out
  '';

  # The one host service the guests are meant to reach.
  registry =
    let
      server =
        settings:
        (testHost ../examples/site {
          hosts.server = exampleSite.hosts.server // {
            settings = {
              imports = [
                exampleSite.hosts.server.settings
                settings
              ];
            };
          };
        } "server").config;
      on = server { nixie.data.registry.enable = true; };
      off = server { nixie.data.registry.enable = false; };
      rules = c: c.networking.nftables.tables.nixie.content;
      facts = {
        "it serves what the cache holds" =
          on.services.dockerRegistry.enable
          && on.services.dockerRegistry.storagePath == "${on.nixie.data.root}/cache/registry";
        "the guests are let through to it, and to nothing else new" =
          lib.hasInfix "tcp dport 5000 accept" (rules on)
          && !(lib.hasInfix "tcp dport 5000 accept" (rules off));
        "off, nothing serves them" = !off.services.dockerRegistry.enable;
        "a manifest with images turns it on by itself" =
          (server {
            nixie.data.manifest.oci.thing = {
              image = "example.invalid/thing";
              digest = "sha256:0";
            };
          }).services.dockerRegistry.enable;
      };
      failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) facts);
    in
    assert lib.assertMsg (failed == [ ]) "registry: ${lib.concatStringsSep "; " failed}";
    pkgs.writeText "registry" (lib.concatStringsSep "\n" (lib.attrNames facts));

  # Stillness reaches the applications, not only the compositor: GTK's own
  # switch follows nixie.desktop.look.animations.
  desktop-motion =
    let
      laptopWith =
        settings:
        (testHost ../examples/desktop-site {
          hosts.laptop = desktopSite.hosts.laptop // {
            settings = {
              imports = [
                desktopSite.hosts.laptop.settings
                settings
              ];
            };
          };
        } "laptop").config;
      gtk = c: c.environment.etc."xdg/gtk-3.0/settings.ini".text;
      still = laptopWith { nixie.desktop.look.animations = "none"; };
      moving = laptopWith { nixie.desktop.look.animations = "full"; };
      facts = {
        "none stops GTK's animations too" = lib.hasInfix "gtk-enable-animations=0" (gtk still);
        "full leaves them" = lib.hasInfix "gtk-enable-animations=1" (gtk moving);
        "and GTK 4 is told the same thing" =
          still.environment.etc."xdg/gtk-4.0/settings.ini".text == gtk still;
      };
      failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) facts);
    in
    assert lib.assertMsg (failed == [ ]) "desktop-motion: ${lib.concatStringsSep "; " failed}";
    pkgs.writeText "desktop-motion" (lib.concatStringsSep "\n" (lib.attrNames facts));

  # Which exporters run, and that what is scraped follows them.
  exporters =
    let
      server =
        settings:
        (testHost ../examples/site {
          hosts.server = exampleSite.hosts.server // {
            settings = {
              imports = [
                exampleSite.hosts.server.settings
                settings
              ];
            };
          };
        } "server").config;
      on = server { nixie.monitoring.enable = true; };
      off = server {
        nixie.monitoring.enable = true;
        nixie.monitoring.exporters.node.enable = false;
      };
      extra = server {
        nixie.monitoring.enable = true;
        nixie.monitoring.exporters.smartctl.enable = true;
      };
      jobs = c: map (j: j.job_name) c.services.prometheus.scrapeConfigs;
      facts = {
        "this machine's own figures by default" =
          on.services.prometheus.exporters.node.enable && builtins.elem "node" (jobs on);
        "a site can turn one off, and then nothing scrapes it" =
          !off.services.prometheus.exporters.node.enable && !(builtins.elem "node" (jobs off));
        "and turn another of nixpkgs' own on, which is then scraped" =
          extra.services.prometheus.exporters.smartctl.enable && builtins.elem "smartctl" (jobs extra);
        # Named, not swept: reading every exporter option throws on the
        # ones nixpkgs has removed.
        "every exporter answers on this host alone" =
          lib.all (n: extra.services.prometheus.exporters.${n}.listenAddress == "127.0.0.1")
            [
              "node"
              "smartctl"
            ];
      };
      failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) facts);
    in
    assert lib.assertMsg (failed == [ ]) "exporters: ${lib.concatStringsSep "; " failed}";
    pkgs.writeText "exporters" (lib.concatStringsSep "\n" (lib.attrNames facts));

  # The three modes for following the site, and the surfaces that show it.
  updates =
    let
      server =
        settings:
        (testHost ../examples/site {
          hosts.server = exampleSite.hosts.server // {
            settings = {
              imports = [
                exampleSite.hosts.server.settings
                settings
              ];
            };
          };
        } "server").config;
      # A machine of a site that keeps a repository, which is what following
      # it needs.
      off = server {
        nixie.updates.mode = "off";
        nixie.site.repo = "git@example:site.git";
      };
      auto = server {
        nixie.updates.mode = "auto";
        nixie.updates.schedule = "*:0/30";
        nixie.site.repo = "git@example:site.git";
      };
      alone = server { nixie.updates.mode = "notify"; };
      # A machine that never mentions following anything: the default is not
      # a mistake there, and nothing is said about it.
      plain = server { };
      saidSo = c: lib.any (w: lib.hasInfix "nixie.updates.mode" w) c.warnings;
      notify = server {
        nixie.updates.mode = "notify";
        nixie.site.repo = "git@example:site.git";
      };
      desktop = (testHost ../examples/desktop-site desktopSite "laptop").config;
      facts = {
        "off does not look" =
          !(off.systemd.timers ? nixie-update) && !(off.systemd.services ? nixie-update);
        "nor does a machine with no repository to follow, and it says why" =
          !(alone.systemd.timers ? nixie-update) && saidSo alone;
        "a machine that never asked to follow one is not warned about it" =
          !(plain.systemd.timers ? nixie-update) && !(saidSo plain);
        "notify and auto look on their own schedule" =
          notify.systemd.timers.nixie-update.timerConfig.OnCalendar == "hourly"
          && auto.systemd.timers.nixie-update.timerConfig.OnCalendar == "*:0/30"
          && auto.systemd.timers.nixie-update.timerConfig.Persistent;
        "what the machine wants you to know is collected either way" =
          off.systemd.timers ? nixie-notices && auto.systemd.timers ? nixie-notices;
        "the mode reaches the command through the site file" =
          (builtins.fromJSON auto.environment.etc."nixie/site.json".text).updates.mode == "auto";
        "a login says it" = lib.hasInfix "notices.json" off.environment.interactiveShellInit;
        "a desktop shows it as a notification" =
          desktop.systemd.user.paths.nixie-notify.pathConfig.PathChanged == "/run/nixie/notices.json"
          && desktop.systemd.user.services ? nixie-notify;
        "a server has no desktop notifier to run" = !(off.systemd.user.services ? nixie-notify);
      };
      failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) facts);
    in
    assert lib.assertMsg (failed == [ ]) "updates: ${lib.concatStringsSep "; " failed}";
    pkgs.writeText "updates" (lib.concatStringsSep "\n" (lib.attrNames facts));

  # A theme found at any depth of its source and installed into the initrd
  # with its paths pointed at the copy.
  splash-theme =
    let
      host = (testHost ./sites (import ./sites/splash-theme.nix) "host").config;
    in
    assert host.boot.plymouth.theme == "demo";
    pkgs.runCommand "splash-theme"
      {
        themes = host.boot.initrd.systemd.contents."/etc/plymouth/themes".source;
      }
      ''
        grep -qx "ScriptFile=$themes/demo/demo.script" "$themes/demo/demo.plymouth"
        test -s "$themes/demo/demo.script"
        touch "$out"
      '';

  # GRUB reads PNGs with 8 or 16 bits per channel only and otherwise stops at
  # "Press any key to continue", which shows on UEFI boots and nowhere else.
  iso-grub-theme =
    pkgs.runCommand "iso-grub-theme"
      {
        theme = self.packages.x86_64-linux.nixie-iso.config.isoImage.grubTheme;
        nativeBuildInputs = [ pkgs.file ];
      }
      ''
        find "$theme" -name '*.png' | while read -r f; do
          file "$f" | grep -Eq '(8|16)-bit/color RGB' || { file "$f" >&2; exit 1; }
        done
        touch $out
      '';

  # The panel's Machines page is only as right as this list: `lib.mkSite`
  # reads it from the site's own data, so every host of a site knows the
  # others without evaluating them.
  site-machines =
    let
      machines =
        (nixieLib.mkSite ./sites/two-hosts/site.nix).nixosConfigurations.alpha.config.nixie.ui.machines;
      want = [
        {
          name = "alpha";
          profile = "server";
          url = "https://192.0.2.10:8443";
        }
        {
          name = "beta";
          profile = "desktop";
          url = null;
        }
      ];
    in
    assert lib.assertMsg (machines == want) "mkSite derived ${builtins.toJSON machines}";
    pkgs.writeText "site-machines" (builtins.toJSON machines);

  eval-matrix = pkgs.writeText "eval-matrix" (lib.concatStringsSep "\n" (lib.attrValues matrix));

  systemd-security =
    pkgs.runCommand "systemd-security"
      {
        nativeBuildInputs = [
          pkgs.systemd
          pkgs.gnugrep
        ];
        units = lib.mapAttrsToList (n: u: "${lib.removeSuffix ".service" n}=${u.unit}/${n}") unitsToCheck;
        documented = documentedExposure;
        sources = lib.cleanSource ../.;
      }
      ''
        status=0
        for entry in $units; do
          name=''${entry%%=*}; file=''${entry#*=}
          if systemd-analyze security --offline=true --no-pager --threshold=3 "$file" >/dev/null 2>&1; then
            echo "OK       $name"; continue
          fi
          if printf '%s\n' $documented | grep -qx "$name" && grep -rq "exposure:" "$sources/modules" "$sources/installer"; then
            echo "EXPOSED  $name (documented)"; continue
          fi
          echo "FAIL     $name: exposure above OK and no documented reason" >&2; status=1
        done
        [ $status = 0 ]
        touch $out
      '';

  # Nothing key-like may end up in the store: private keys, age identities,
  # sops-decrypted material, passphrases the tests use.
  no-secrets-in-store =
    pkgs.runCommand "no-secrets-in-store"
      {
        closure = pkgs.closureInfo { rootPaths = [ kioskServer.config.system.build.toplevel ]; };
        nativeBuildInputs = [ pkgs.gnugrep ];
      }
      ''
        status=0
        while read -r p; do
          case "$p" in *-source|*-linux-*|*-kernel*|*-firmware*|*-go-*|*-openssl-*|*-gnupg-*|*-python3*|*-perl*|*-ruby-*|*-nss-*|*-cacert*|*-ca-certificates*|*-testing*|*-tpm2-*|*-openssh-*|*-git-*|*-systemd-*|*-curl-*|*-nix-*|*-glibc*|*-chromium*|*-qemu*|*-mesa*|*-gcc*|*-llvm*|*-rust*) continue ;; esac
          # Upstream packages ship fixture keys with their installed tests.
          if grep -rIlE -- '-----BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----|AGE-SECRET-KEY-1' "$p" 2>/dev/null | grep -v -e '/share/doc/' -e '/installed-tests/' | head -1 | grep .; then
            echo "key-like material in $p" >&2; status=1
          fi
        done < "$closure/store-paths"
        [ $status = 0 ]
        touch $out
      '';

  profile-server-has-no-desktop = closureFree "server" server.config.system.build.toplevel [
    "hyprland"
    "cage"
    "chromium"
    "firefox"
    "quickshell"
    "greetd"
  ];
  # With the kiosk on, exactly the kiosk stack may appear and nothing else.
  profile-server-kiosk-only =
    closureFree "server-kiosk"
      (testHost ../examples/site {
        hosts.server = exampleSite.hosts.server // {
          settings = {
            imports = [ exampleSite.hosts.server.settings ];
            nixie.console.kiosk.enable = true;
          };
        };
      } "server").config.system.build.toplevel
      [
        "hyprland"
        "firefox"
        "quickshell"
        "greetd"
        "regreet"
      ];
  profile-desktop-has-no-server = closureFree "desktop" laptopInSetup.config.system.build.toplevel [
    "incus"
    "opentofu"
    "prometheus"
    "grafana"
    "restic"
    "cockpit"
  ];

  vm-egress = import ./vm/egress.nix { inherit pkgs nixieLib exampleSite; };
  vm-exits = import ./vm/exits.nix { inherit pkgs nixieLib exampleSite; };

  vm-monitoring = import ./vm/monitoring.nix { inherit pkgs nixieLib exampleSite; };

  vm-ui = import ./vm/ui.nix {
    inherit pkgs nixieLib exampleSite;
    nixieCli = self.packages.x86_64-linux.nixie-cli;
  };

  vm-host-ui = import ./vm/host-ui.nix {
    inherit pkgs nixieLib exampleSite;
    nixieCli = self.packages.x86_64-linux.nixie-cli;
  };

  vm-console = import ./vm/console.nix { inherit pkgs nixieLib exampleSite; };

  vm-desktop = import ./vm/desktop.nix { inherit pkgs nixieLib desktopSite; };

  vm-deploy = import ./vm/deploy.nix {
    inherit
      pkgs
      inputs
      self
      nixieLib
      exampleSite
      ;
  };

  vm-deploy-kexec = import ./vm/deploy-kexec.nix {
    inherit
      pkgs
      inputs
      self
      nixieLib
      exampleSite
      ;
  };

  vm-data = import ./vm/data.nix {
    inherit pkgs nixieLib exampleSite;
    nixieCli = self.packages.x86_64-linux.nixie-cli;
  };

  vm-updates = import ./vm/updates.nix {
    inherit
      pkgs
      inputs
      nixieLib
      exampleSite
      ;
    nixieCli = self.packages.x86_64-linux.nixie-cli;
  };

  vm-rollback = import ./vm/rollback.nix {
    inherit
      pkgs
      inputs
      nixieLib
      exampleSite
      ;
    nixieCli = self.packages.x86_64-linux.nixie-cli;
  };
  vm-hardware = import ./vm/hardware.nix {
    inherit
      pkgs
      inputs
      nixieLib
      exampleSite
      ;
    nixieCli = self.packages.x86_64-linux.nixie-cli;
  };
  vm-backup = import ./vm/backup.nix {
    inherit pkgs nixieLib exampleSite;
    nixieCli = self.packages.x86_64-linux.nixie-cli;
  };
  vm-guests = import ./vm/guests.nix {
    inherit pkgs nixieLib exampleSite;
    nixieCli = self.packages.x86_64-linux.nixie-cli;
  };

  vm-installer-lan = import ./vm/installer-lan.nix {
    inherit
      pkgs
      inputs
      self
      nixieLib
      exampleSite
      ;
  };

  vm-encryption = import ./vm/encryption.nix {
    inherit
      pkgs
      inputs
      nixieLib
      exampleSite
      ;
    nixieInstaller = self.packages.x86_64-linux.nixie-installer;
    nixieCli = self.packages.x86_64-linux.nixie-cli;
  };

  vm-splash = import ./vm/splash.nix {
    inherit
      pkgs
      inputs
      nixieLib
      exampleSite
      ;
    nixieInstaller = self.packages.x86_64-linux.nixie-installer;
    nixieCli = self.packages.x86_64-linux.nixie-cli;
  };

  vm-boot-plain = pkgs.testers.runNixOSTest {
    name = "vm-boot-plain";
    nodes.server = {
      imports = nixieLib.hostModules ../examples/site "server" exampleSite.hosts.server ++ [
        ./vm/qemu.nix
      ];
      # The site checkout the host reads its secrets from.
      virtualisation.sharedDirectories.nixie-site = {
        source = "${lib.cleanSource ../examples/site}";
        target = "/etc/nixie/site";
      };
    };
    # A machine whose initrd gives up: it is told to go straight to the
    # initrd's emergency target, which is where a disk that never opens
    # lands a person. The prompt there cannot be used -- root is locked --
    # so what matters is that the screen says which part gave up.
    nodes.stuck = {
      imports = nixieLib.hostModules ../examples/site "server" exampleSite.hosts.server ++ [
        ./vm/qemu.nix
      ];
      virtualisation.vlans = [ ];
      boot.kernelParams = [ "rd.systemd.unit=emergency.target" ];
    };
    testScript = ''
      stuck.start()
      # It never reaches a shell the driver can use, so the console is the
      # only thing to read -- and read by polling the log, not with
      # wait_for_console_text, which takes about a second a line: this
      # machine is told to panic on a failed start and is gone in under two.
      # What is waited for is the kernel-log copy at error level, which is
      # what a quiet console shows and a serial console keeps; /dev/console
      # is the screen here, not the serial port.
      import time

      said = ""
      for _ in range(120):
          said = stuck.get_console_log()
          if "nixie-emergency: The disk is still locked" in said:
              break
          time.sleep(1)
      assert "nixie-emergency: Nixie could not finish starting" in said, said[-3000:]
      assert "nixie-emergency: The disk is still locked" in said, said[-3000:]
      # And it got out before the panic that a failed start triggers here.
      assert said.index("nixie-emergency: The disk is still locked") < said.index("Kernel panic"), said[-3000:]

      server.wait_for_unit("multi-user.target")
      server.succeed("id admin")
      server.succeed("test -s /run/secrets-for-users/admin-password")
      server.succeed("systemctl is-active sshd")
      # The bridge carries the uplink's MAC, so DHCP gives the installed host
      # the lease the installer had (a generated MAC got a new address).
      server.succeed("ip -br link show nixie-br | grep -qi 52:54:00:12:34:56")
      server.succeed("sudo -n -u admin true || true")
      print(server.succeed("hostname; grep -c . /etc/passwd"))
    '';
  };
}
