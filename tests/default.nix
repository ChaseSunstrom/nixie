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
    site: name:
    inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
      };
      modules = nixieLib.hostModules name site.hosts.${name};
    };

  server = testHost exampleSite "server";
  laptop = testHost desktopSite "laptop";

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
    file: _: (testHost (import (./sites + "/${file}")) "host").config.system.build.toplevel.drvPath
  ) (lib.filterAttrs (n: _: lib.hasSuffix ".nix" n) (builtins.readDir ./sites));

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

  eval-matrix = pkgs.writeText "eval-matrix" (lib.concatStringsSep "\n" (lib.attrValues matrix));

  profile-server-has-no-desktop = closureFree "server" server.config.system.build.toplevel [
    "hyprland"
    "cage"
    "chromium"
    "firefox"
    "quickshell"
    "greetd"
  ];
  profile-desktop-has-no-server = closureFree "desktop" laptop.config.system.build.toplevel [
    "incus"
    "opentofu"
    "prometheus"
    "grafana"
    "restic"
    "cockpit"
  ];

  vm-boot-plain = pkgs.testers.runNixOSTest {
    name = "vm-boot-plain";
    nodes.server.imports = nixieLib.hostModules "server" exampleSite.hosts.server ++ [ ./vm/qemu.nix ];
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
