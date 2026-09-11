# What runs on the installer, ISO or kexec image: the phase engine, the
# setup service with the wizard, the kiosk on the local display and the
# terminal wizard on tty2. The ISO module wraps this in the CD image.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../lib/option.nix lib) mkOption;
  cfg = config.nixie.installer;
in
{
  imports = [ ./kiosk.nix ];

  options.nixie.installer = {
    packages = mkOption {
      type = lib.types.attrsOf lib.types.package;
      description = "Internal: nixie-setup, nixie-installer, nixie-cli and deploy as built by the platform flake.";
    };
    platform = mkOption {
      type = lib.types.path;
      description = "Internal: the platform source, bundled so a new site can point at it.";
    };
    toplevel = mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Internal (tests): a prebuilt system to install instead of building the site.";
    };
    disko = mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Internal (tests): the prebuilt disko script for that system.";
    };
    kiosk = mkOption {
      type = lib.types.bool;
      default = true;
      description = "Internal: show the wizard on the local display.";
    };
  };

  config = {
    environment.systemPackages = [
      cfg.packages.nixie-installer
      cfg.packages.nixie-setup
      cfg.packages.nixie-cli
      cfg.packages.deploy
      pkgs.gum
      pkgs.git
      pkgs.jq
    ];
    environment.etc."nixie/platform".source = cfg.platform;
    environment.etc."nixie-iso".text = "nixie installer\n";

    boot.supportedFilesystems.zfs = true;
    networking.hostId = lib.mkDefault "8425e349";
    networking.useDHCP = lib.mkDefault true;
    networking.firewall.allowedTCPPorts = [
      9443
      22
    ];
    services.openssh.enable = true;
    # The person turns SSH on from the terminal wizard by setting a root
    # password; until then there is nothing to log in with.
    services.openssh.settings.PermitRootLogin = "yes";

    security.tpm2.enable = true;
    boot.initrd.availableKernelModules = [
      "tpm_tis"
      "tpm_crb"
    ];

    systemd.services.nixie-setup = {
      description = "Nixie setup service (installer)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        # exposure: runs the phase scripts as root; that is its whole purpose.
        ExecStart =
          "${lib.getExe cfg.packages.nixie-setup} --mode iso --cert-dir /var/lib/nixie/setup-cert"
          + lib.optionalString (cfg.toplevel != null) " --toplevel ${cfg.toplevel}"
          + lib.optionalString (cfg.disko != null) " --disko ${cfg.disko}";
        Restart = "on-failure";
      };
    };

    nixie.kiosk.enable = cfg.kiosk;
    # The kiosk user reads the local token the setup service writes.
    systemd.services.nixie-setup.serviceConfig.ExecStartPost = lib.mkIf cfg.kiosk (
      pkgs.writeShellScript "share-token" ''
        for _ in $(seq 50); do [ -e /run/nixie-setup/local-token ] && break; sleep 0.2; done
        chgrp nixie-kiosk /run/nixie-setup /run/nixie-setup/local-token
        chmod 750 /run/nixie-setup; chmod 640 /run/nixie-setup/local-token
      ''
    );

    # tty2: the same wizard as a terminal program, for keyboards without a
    # working display and for people who prefer it.
    systemd.services."getty@tty2".enable = false;
    systemd.services.nixie-tty2 = {
      description = "Nixie terminal wizard on tty2";
      wantedBy = [ "multi-user.target" ];
      after = [ "nixie-setup.service" ];
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.packages.deploy} --local";
        StandardInput = "tty";
        StandardOutput = "tty";
        StandardError = "tty";
        TTYPath = "/dev/tty2";
        TTYReset = true;
        TTYVHangup = true;
        Restart = "always";
        RestartSec = 2;
      };
    };
  };
}
