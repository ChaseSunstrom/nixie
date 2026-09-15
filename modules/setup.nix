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
    frontEnd = mkOption {
      type = lib.types.enum [
        "graphical"
        "web"
        "terminal"
      ];
      default = "graphical";
      description = "Internal: the front end chosen at the installer's boot menu, which setup keeps until Finish. The installer writes it next to nixie.setup.pending.";
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
    # The plain entry is only reached by holding Space at boot (the menu is
    # hidden); it has no wizard, so it says where setup went.
    services.getty.greetingLine = lib.mkOverride 900 "<<< Setup is not finished on this machine. Restart it and let it start by itself: setup continues where it stopped. >>>";
    specialisation.nixie-setup.configuration = {
      imports = [ ../installer/front-end.nix ];
      system.nixos.tags = [ "setup" ];
      services.getty.greetingLine = lib.mkForce "<<< Nixie setup >>>";
      # The same front end as at the installer's boot menu, on every reboot
      # until Finish: the wizard, the address for a browser, or the terminal.
      nixie.frontEnd = {
        mode = cfg.frontEnd;
        terminal = "${lib.getExe cfg.packages.deploy} --continue";
      };
      # Setup owns the screen until Finish, on a desktop as on a server; a
      # desktop session came up here before and nothing led back to setup.
      services.greetd.enable = lib.mkForce false;
      programs.regreet.enable = lib.mkForce false;
      environment.systemPackages = [
        cfg.packages.nixie-installer
        cfg.packages.deploy
        cfg.packages.nixie-setup.passthru.finish
      ];
      systemd.services.nixie-setup = lib.mkIf (cfg.frontEnd != "terminal") {
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
      networking.firewall.allowedTCPPorts = lib.mkIf (cfg.frontEnd != "terminal") [ 9443 ];
      nixie.network.firewall.extraInputRules = lib.mkIf (
        cfg.frontEnd != "terminal"
      ) ''iifname "${config.nixie.network.firewall.lanInterface}" tcp dport 9443 accept'';
    };
  };
}
