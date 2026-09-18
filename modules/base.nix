# Settings every Nixie host shares regardless of profile.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # The initrd carries the script itself, not just its name: a unit whose
  # command is not in there fails at EXEC, which is how this one first
  # behaved. storePaths brings its closure, the shell included.
  emergencyReport = pkgs.writeShellScript "nixie-emergency" (
    (import ../lib/template.nix lib).fill ./emergency.sh {
      plymouth = lib.optionalString config.boot.plymouth.enable "${config.boot.plymouth.package}/bin/plymouth";
    }
  );
in
{
  boot.initrd.systemd.storePaths = [ emergencyReport ];
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
  # When the initrd gives up, say what failed. The prompt it drops to cannot
  # be used -- root is locked, and a signed boot chain has no editable
  # command line -- so without this the screen says only "emergency mode"
  # and the person has nothing to act on or to report.
  boot.initrd.systemd.services.nixie-emergency = {
    description = "Say what failed before the emergency prompt";
    wantedBy = [ "emergency.target" ];
    before = [
      "emergency.service"
      # A machine told to panic on a failed start (a test VM, and anything
      # else passing boot.panic_on_fail) crashes from this same target, so
      # the reason has to be out before it does. Without the ordering the
      # two raced and the panic won by sixteen milliseconds.
      "panic-on-fail.service"
    ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = emergencyReport;
      # The console is the only screen there is at this point.
      StandardOutput = "tty";
      StandardError = "tty";
      TTYPath = "/dev/console";
    };
  };
  boot.loader.systemd-boot.enable = lib.mkDefault (!config.boot.lanzaboote.enable);
  boot.loader.efi.canTouchEfiVariables = true;
  # No menu: the machine starts its default entry, the setup generation until
  # Finish and the newest generation after. Holding Space as it starts shows
  # the menu for recovery; `nixie rollback` and the front panel choose
  # generations otherwise. lanzaboote takes the same setting.
  boot.loader.timeout = lib.mkDefault 0;
  # Keeping the editor off stops a console user from changing kernel
  # parameters.
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
  environment.systemPackages = [
    pkgs.git
    # `nixie apply`, `rollback`, `doctor`, the front panel and `nixie menu`;
    # the Incus client and OpenTofu come with it only where guests run.
    (import ../packages/nixie-cli.nix {
      inherit pkgs;
      guests = config.nixie.incus.enable;
    })
  ];

  system.stateVersion = lib.mkDefault "26.05";
}
