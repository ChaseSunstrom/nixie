# Settings every Nixie host shares regardless of profile.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  # A site is applied with `nixie apply`, never by hand-editing channels.
  nix.channel.enable = false;
  # The name in the boot menu, the console greeting and os-release; ID stays
  # nixos, so tools that look for NixOS still find it.
  system.nixos.distroName = lib.mkDefault "Nixie";

  boot.initrd.systemd.enable = true;
  boot.loader.systemd-boot.enable = lib.mkDefault (!config.boot.lanzaboote.enable);
  boot.loader.efi.canTouchEfiVariables = true;
  # Setup selects the setup generation with `bootctl set-default`; keeping the
  # editor off stops a console user from changing kernel parameters.
  boot.loader.systemd-boot.editor = false;
  # nixie.host.keepGenerations: the loader (lanzaboote inherits this) and the
  # weekly clean-up below agree on how many generations stay.
  boot.loader.systemd-boot.configurationLimit = config.nixie.host.keepGenerations;
  # The site commit labels every generation (`nixie rollback --list`, the
  # boot menu); a site flake passes it through lib.mkSite (ARCHITECTURE D19).
  system.nixos.tags = lib.optional (
    config.nixie.host.siteRevision != null
  ) "site-${config.nixie.host.siteRevision}";
  systemd.services.nixie-gc = {
    description = "Delete system generations beyond nixie.host.keepGenerations and collect garbage";
    serviceConfig = {
      Type = "oneshot";
      # exposure: writes the Nix store and the system profile as root; that is its job.
      ExecStart = pkgs.writeShellScript "nixie-gc" ''
        ${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +${toString config.nixie.host.keepGenerations}
        ${config.nix.package}/bin/nix-collect-garbage
      '';
    };
  };
  systemd.timers.nixie-gc = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "6h";
    };
  };

  time.timeZone = config.nixie.host.timezone;
  networking.hostName = config.nixie.host.name;

  environment.defaultPackages = lib.mkDefault [ ];
  documentation.nixos.enable = lib.mkDefault false;

  # Guest tarballs and the site checkout are the only things that need git on
  # the host; keeping it in the base means `nixie apply` works on both profiles.
  environment.systemPackages = [ pkgs.git ];

  system.stateVersion = lib.mkDefault "26.05";
}
