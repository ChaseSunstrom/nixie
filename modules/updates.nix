# Following the site repository: one machine applies a change and pushes it,
# the others see that they are behind and either say so or catch up. The
# work itself is `nixie apply`, which switches the host and rebuilds the
# guests the site declares, so a guest's configuration follows the same way.
{
  config,
  options,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../lib/option.nix lib) mkOption;
  cfg = config.nixie.updates;
  # Nothing to follow without a repository to follow it in.
  follows = cfg.mode != "off" && config.nixie.site.repo != null;
  # Whether anyone asked for a mode at all. The option's own default is a
  # definition like any other, so the question is one of priority: below the
  # default's means a person or the site put it there.
  asked = options.nixie.updates.mode.highestPrio < (lib.mkOptionDefault null).priority;
  nixie = "/run/current-system/sw/bin/nixie";
in
{
  options.nixie.updates = {
    mode = mkOption {
      type = lib.types.enum [
        "off"
        "notify"
        "auto"
      ];
      default = "notify";
      description = ''
        What this machine does when the site repository holds a newer commit
        than the one it is running. "notify" says so on the front panel, the
        host page, the desktop and at login, and waits for
        `nixie update --now`. "auto" applies it by itself, undoing it if the
        new system comes out less healthy than the one it replaced. "off"
        does not look.
        Applying brings the guests the site declares with it, on a server as
        on a desktop.
      '';
      nixieUi = {
        section = "site";
        order = 2;
      };
    };
    schedule = mkOption {
      type = lib.types.str;
      default = "hourly";
      description = ''
        How often to look, as a systemd time ("hourly", "daily", "*:0/15").
        A machine that was off looks as soon as it is back.
      '';
      nixieUi = {
        section = "site";
        order = 3;
        advanced = true;
      };
    };
    confirmWithin = mkOption {
      type = lib.types.str;
      default = "10m";
      description = ''
        In "auto" mode, how long the machine has to prove itself after
        applying: it confirms when `nixie doctor` comes out no worse than it
        did before, and otherwise goes back to the system it had. Empty
        applies with no way back, which is only sensible where someone is
        watching.
      '';
      nixieUi = {
        section = "site";
        order = 4;
        advanced = true;
      };
    };
  };

  config = {
    # Everything that wants a person's attention, in one file every surface
    # reads: the front panel, the host page, the desktop and the login line.
    systemd.services.nixie-notices = {
      description = "Collect what this machine wants you to know";
      # exposure: root, to read the backup check, the TPM and usbguard.
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${nixie} notices --write";
      };
    };
    systemd.timers.nixie-notices = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "15min";
        Unit = "nixie-notices.service";
      };
    };

    # Only when a mode was asked for: a machine with no site repository at
    # all is a normal standalone one, and the default is not a mistake.
    warnings = lib.optional (asked && cfg.mode != "off" && config.nixie.site.repo == null) ''
      nixie.updates.mode is "${cfg.mode}", but nixie.site.repo is not set:
      this machine has no repository to follow, so nothing looks for changes.
    '';

    systemd.services.nixie-update = lib.mkIf follows {
      description = "Look for a newer site, and in auto mode apply it";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      # exposure: root, because applying the site is what it may do.
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${nixie} update --auto";
      };
    };
    systemd.timers.nixie-update = lib.mkIf follows {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        # A machine that was off looks as soon as it is back, and not every
        # machine of a site in the same second.
        Persistent = true;
        RandomizedDelaySec = "5m";
        Unit = "nixie-update.service";
      };
    };

    # A login says what is waiting: over SSH on a server, in a terminal on a
    # desktop. NixOS has no /etc/profile.d, and a login shell has no PATH to
    # speak of yet, so jq goes in by its own path.
    environment.interactiveShellInit = (import ../lib/template.nix lib).fill ./notices-login.sh {
      jq = "${pkgs.jq}/bin/jq";
    };

    # On a desktop the same notices arrive as desktop notifications, each
    # one once: the path unit fires when the file changes.
    systemd.user.services.nixie-notify = lib.mkIf config.nixie.desktop.enable {
      description = "Show this machine's notices on the desktop";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "nixie-notify" (
          (import ../lib/template.nix lib).fill ./notify.sh {
            notifySend = "${pkgs.libnotify}/bin/notify-send";
            jq = "${pkgs.jq}/bin/jq";
          }
        );
      };
    };
    systemd.user.paths.nixie-notify = lib.mkIf config.nixie.desktop.enable {
      wantedBy = [ "default.target" ];
      pathConfig = {
        PathChanged = "/run/nixie/notices.json";
        Unit = "nixie-notify.service";
      };
    };
  };
}
