# What runs on the installer, ISO or kexec image: the phase engine, the
# setup service with the wizard, and one of three ways to drive it from this
# machine (nixie.installer.mode). The ISO module wraps this in the CD image
# and offers each mode as a boot menu entry.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../lib/option.nix lib) mkOption;
  cfg = config.nixie.installer;
  web = cfg.mode != "terminal";
in
{
  imports = [ ./front-end.nix ];

  options.nixie.installer = {
    packages = mkOption {
      type = lib.types.attrsOf lib.types.package;
      description = "Internal: nixie-setup, nixie-installer, nixie-cli and deploy as built by the platform flake.";
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
    mode = mkOption {
      type = lib.types.enum [
        "graphical"
        "web"
        "terminal"
      ];
      default = "graphical";
      description = ''
        Internal: how the installer is driven. graphical shows the wizard on
        this screen, web shows the address and pairing code for a browser on
        another device, terminal runs the text wizard on this screen. The
        setup service listens on the network in graphical and web modes.
      '';
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
    environment.etc."nixie-iso".text = "nixie installer\n";
    # Phase 3 evaluates the site flake and nixos-install builds it; installed
    # hosts get the same setting from modules/base.nix.
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    # The installer's root and store overlay are RAM, and evaluating a site
    # takes about 2 GB on its own: on a 4 GB machine phase 3 was killed for
    # memory. Compressed swap in RAM gives the evaluator's heap room.
    zramSwap = {
      enable = true;
      memoryPercent = 100;
    };

    boot.supportedFilesystems.zfs = true;
    networking.hostId = lib.mkDefault "8425e349";
    networking.useDHCP = lib.mkDefault true;
    networking.firewall.allowedTCPPorts = [ 22 ] ++ lib.optional web 9443;
    services.openssh.enable = true;
    # The person turns SSH on from the terminal wizard by setting a root
    # password; until then there is nothing to log in with.
    services.openssh.settings.PermitRootLogin = "yes";

    security.tpm2.enable = true;
    boot.initrd.availableKernelModules = [
      "tpm_tis"
      "tpm_crb"
    ];

    systemd.services.nixie-setup = lib.mkIf web {
      description = "Nixie setup service (installer)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        # exposure: runs the phase scripts as root; that is its whole purpose.
        ExecStart =
          "${lib.getExe cfg.packages.nixie-setup} --mode iso --front-end ${cfg.mode} --cert-dir /var/lib/nixie/setup-cert"
          + lib.optionalString (cfg.toplevel != null) " --toplevel ${cfg.toplevel}"
          + lib.optionalString (cfg.disko != null) " --disko ${cfg.disko}";
        Restart = "on-failure";
      };
    };

    nixie.frontEnd = {
      inherit (cfg) mode;
      terminal = "${lib.getExe cfg.packages.deploy} --local";
    };
  };
}
