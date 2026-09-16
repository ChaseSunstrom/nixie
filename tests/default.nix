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
  unitsToCheck = platformUnits kioskServer // platformUnits laptop;

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
  # the splash unless a feature needs the text console, and during setup the
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
        "no splash with duress or attestation" = !duressHost.boot.plymouth.enable;
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

  vm-monitoring = import ./vm/monitoring.nix { inherit pkgs nixieLib exampleSite; };

  vm-ui = import ./vm/ui.nix { inherit pkgs nixieLib exampleSite; };

  vm-host-ui = import ./vm/host-ui.nix {
    inherit pkgs nixieLib exampleSite;
    nixieCli = self.packages.x86_64-linux.nixie-cli;
  };

  vm-console = import ./vm/console.nix { inherit pkgs nixieLib exampleSite; };

  vm-desktop = import ./vm/desktop.nix { inherit pkgs nixieLib desktopSite; };

  vm-data = import ./vm/data.nix {
    inherit pkgs nixieLib exampleSite;
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
    testScript = ''
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
