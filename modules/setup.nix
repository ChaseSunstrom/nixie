# The setup generation: a specialisation that carries the on-screen wizard
# through the phases that run after first boot, then removes itself.
{ inputs, self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../lib/option.nix lib) mkOption;
  cfg = config.nixie.setup;
in
{
  options.nixie.setup = {
    pending = mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Internal: true from first boot until the wizard's Finish step. While
        true the system carries an extra boot entry with the on-screen wizard.
      '';
    };
    packages = mkOption {
      type = lib.types.attrs;
      default = import ../packages { inherit pkgs inputs self; };
      description = "Internal: the platform packages the setup generation runs.";
    };
    kiosk = mkOption {
      type = lib.types.bool;
      default = true;
      description = "Internal: show the continuation wizard on the local display (off on desktops, which continue in their own session).";
    };
  };

  config = lib.mkIf cfg.pending {
    # The loader's default entry is the setup generation until Finish, kept in
    # loader.conf on every activation while pending. The installer used to
    # record it in firmware instead, but `bootctl set-default` refuses unless
    # systemd-boot itself is running, which it never is on the ISO, so a
    # Secure Boot install first booted the plain generation and no wizard.
    boot.loader.systemd-boot.extraInstallCommands = lib.mkIf config.boot.loader.systemd-boot.enable ''
      ${pkgs.gnused}/bin/sed -i 's|^default .*|default nixos-generation-*-specialisation-nixie-setup.conf|' ${config.boot.loader.efi.efiSysMountPoint}/loader/loader.conf
    '';
    # lanzaboote writes loader.conf from its settings; its entries are UKIs.
    boot.lanzaboote.settings.default = "nixos-generation-*-specialisation-nixie-setup-*";
    specialisation.nixie-setup.configuration = {
      imports = [ ../installer/kiosk.nix ];
      system.nixos.tags = [ "setup" ];
      nixie.kiosk.enable = cfg.kiosk && config.nixie.profile == "server";
      environment.systemPackages = [ cfg.packages.nixie-installer ];
      systemd.services.nixie-setup = {
        description = "Nixie setup service (continuation)";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        unitConfig.ConditionPathExists = "!/var/lib/nixie/setup/finished";
        # Phase 8 and Finish run the host's own `nixie`, built for its profile.
        path = [ "/run/current-system/sw" ];
        serviceConfig = {
          # exposure: runs the phase scripts as root; that is its whole purpose.
          ExecStart = "${lib.getExe cfg.packages.nixie-setup} --mode continuation";
          Restart = "on-failure";
        };
      };
      systemd.services.nixie-setup.serviceConfig.ExecStartPost =
        lib.mkIf (cfg.kiosk && config.nixie.profile == "server")
          (
            pkgs.writeShellScript "share-token" ''
              for _ in $(seq 50); do [ -e /run/nixie-setup/local-token ] && break; sleep 0.2; done
              chgrp nixie-kiosk /run/nixie-setup /run/nixie-setup/local-token
              chmod 750 /run/nixie-setup; chmod 640 /run/nixie-setup/local-token
            ''
          );
      networking.firewall.allowedTCPPorts = [ 9443 ];
      nixie.network.firewall.extraInputRules = ''iifname "${config.nixie.network.firewall.lanInterface}" tcp dport 9443 accept'';
    };
  };
}
