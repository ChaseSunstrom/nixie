{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../../lib/option.nix lib) mkOption;
  cfg = config.nixie.security.secureBoot;
  pki = "/var/lib/sbctl";
  keyFiles =
    lib.concatMap
      (k: [
        "${k}/${k}.key"
        "${k}/${k}.pem"
      ])
      [
        "PK"
        "KEK"
        "db"
      ];
in
{
  options.nixie.security.secureBoot.enable = mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Sign the boot chain with your own keys so the firmware refuses to start
      anything else. Setup walks you through putting the firmware into Setup
      Mode (on many machines: Secure Boot Mode set to Custom, then the keys
      reset) and says when to turn Secure Boot on; turned on earlier, the
      firmware answers "Access Denied" until it is turned off again. The
      installer does not start while Secure Boot is on, so turn it off before
      reinstalling. The keys live in the site's secrets.
    '';
    nixieUi = {
      section = "security";
      order = 3;
    };
  };

  config = lib.mkIf cfg.enable {
    # `nixie secure-boot` reads the firmware's keys and checks the
    # signatures with these.
    environment.systemPackages = [
      pkgs.sbctl
      pkgs.sbsigntool
    ];
    boot.lanzaboote = {
      enable = true;
      pkiBundle = pki;
      # systemd-boot enrols the keys itself when the firmware is in Setup
      # Mode, which is what phase 5 asks the person to arrange.
      autoEnrollKeys.enable = true;
    };
    # The keys are made once by setup (phase 2) and kept in the site's sops
    # file so a reinstall does not need re-enrolment.
    sops.secrets =
      lib.listToAttrs (
        map (f: {
          name = "secureboot/${f}";
          value = {
            # Phase 2 keeps the files flat under `secureboot` (`KEK.key`);
            # sops-nix reads each `/` of the name as one more level, so
            # without this the manifest is invalid and no secret installs.
            key = "secureboot/${baseNameOf f}";
            mode = "0400";
          };
        }) keyFiles
      )
      // {
        "secureboot/GUID".mode = "0400";
      };
    # Copied, not linked: sbctl confines itself with Landlock to its own
    # directory, so a key that is a link into /run/secrets cannot be opened
    # ("permission denied" even as root) and the keys are never staged for
    # enrolment.
    system.activationScripts.nixie-sbctl-keys = {
      deps = [ "setupSecrets" ];
      text =
        "install -d -m 0700 ${pki} ${pki}/keys\n"
        + lib.concatMapStrings (
          f:
          let
            src = config.sops.secrets."secureboot/${f}".path;
            dst = if f == "GUID" then "${pki}/GUID" else "${pki}/keys/${f}";
          in
          ''
            if [ -s ${src} ]; then
              install -d -m 0700 "$(dirname ${dst})" && rm -f ${dst} && install -m 0400 ${src} ${dst}
            fi
          ''
        ) (keyFiles ++ [ "GUID" ]);
    };
  };
}
