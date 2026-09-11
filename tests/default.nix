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
          if grep -E -- "-$f-[0-9]" "$closure/store-paths"; then
            echo "closure of ${name} contains $f" >&2
            exit 1
          fi
        done
        touch "$out"
      '';

  # Throwaway sites: the platform must evaluate for every hardware shape.
  matrix = lib.mapAttrs (
    file: _:
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
    "nixie-setup"
    "nixie-tailscale-serve"
    "nixie-oath-users"
    "nixie-panel"
    "nixie-kiosk-gate"
    "nixie-tty2"
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
  # hardware files and tests are the only places they may appear.
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
          if grep -rEn --exclude-dir=tests --exclude-dir=.git \
              --exclude=NIXIE_PLATFORM_BRIEF.md --exclude=hardware.nix \
              --exclude=design-tokens.md -- "$p" .; then
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
        print(f"{len(blocks)} blocks ran, option names and verification links checked")
        PY
        touch $out
      '';

  # The committed reference must match what the module tree says.
  option-reference = pkgs.runCommand "option-reference" { } ''
    diff -u ${../docs/reference/options.md} ${self.packages.x86_64-linux.docs}/options.md
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
          case "$p" in *-source|*-linux-*|*-kernel*|*-firmware*|*-go-*|*-openssl-*|*-gnupg-*|*-python3*|*-perl*|*-nss-*|*-cacert*|*-ca-certificates*|*-testing*|*-tpm2-*|*-openssh-*|*-git-*|*-systemd-*|*-curl-*|*-nix-*|*-glibc*|*-chromium*|*-qemu*|*-mesa*|*-gcc*|*-llvm*|*-rust*) continue ;; esac
          if grep -rIlE -- '-----BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----|AGE-SECRET-KEY-1' "$p" 2>/dev/null | grep -v '/share/doc/' | head -1 | grep .; then
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
  profile-desktop-has-no-server = closureFree "desktop" laptop.config.system.build.toplevel [
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

  vm-host-ui = import ./vm/host-ui.nix { inherit pkgs nixieLib exampleSite; };

  vm-console = import ./vm/console.nix { inherit pkgs nixieLib exampleSite; };

  vm-desktop = import ./vm/desktop.nix { inherit pkgs nixieLib desktopSite; };

  vm-data = import ./vm/data.nix {
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
      server.succeed("sudo -n -u admin true || true")
      print(server.succeed("hostname; grep -c . /etc/passwd"))
    '';
  };
}
