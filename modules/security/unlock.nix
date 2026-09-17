# The one password agent of the initrd. It asks on the boot splash (or the
# console without one) and in a remote-unlock session, and with the duress
# passphrase on, checks every answer against it before passing it on.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  template = import ../../lib/template.nix lib;
  sec = config.nixie.security;
  sd = config.boot.initrd.systemd.package;
  splash = config.boot.plymouth.enable;
  plymouth = lib.optionalString splash "${config.boot.plymouth.package}/bin/plymouth";
  # Only the Nixie theme reads the agent's instructions; any other theme
  # would print them.
  nixieTheme = lib.optionalString (splash && config.boot.plymouth.theme == "nixie") "1";
  devices = map (l: l.device) config.nixie.disks.luks;
  agent = pkgs.writeShellApplication {
    name = "nixie-unlock";
    runtimeInputs = [
      pkgs.cryptsetup
      sd
    ];
    # The agent itself is unlock.sh, beside this file.
    text = template.fill ./unlock.sh {
      devices = lib.escapeShellArgs devices;
      duress = lib.optionalString sec.duress.enable "1";
      inherit plymouth nixieTheme;
    };
  };
in
{
  config = lib.mkIf sec.encryption.enable {
    boot.initrd.systemd.storePaths = [ agent ];
    # The initrd copies the agent script but not the tools on its PATH; the
    # slot probe needs the cryptsetup CLI (systemd-cryptsetup is not enough).
    boot.initrd.systemd.initrdBin = lib.mkIf sec.duress.enable [ pkgs.cryptsetup ];
    # The minimal initrd systemd omits the standalone reply helper.
    boot.initrd.systemd.extraBin.systemd-reply-password = "${sd}/lib/systemd/systemd-reply-password";

    # systemd's console agent does not start while Plymouth runs, and
    # Plymouth's, which its package brings into the initrd, would answer
    # without the duress check. Both give way to this one, started by a
    # watch of its own that works either way.
    boot.initrd.systemd.suppressedUnits = [
      "systemd-ask-password-console.path"
      "systemd-ask-password-console.service"
    ];
    boot.initrd.systemd.services.systemd-ask-password-plymouth.enable = lib.mkIf splash false;
    boot.initrd.systemd.paths.systemd-ask-password-plymouth.enable = lib.mkIf splash false;
    boot.initrd.systemd.paths.nixie-unlock = {
      description = "Watch for passphrase requests";
      wantedBy = [ "sysinit.target" ];
      before = [
        "paths.target"
        "cryptsetup.target"
      ];
      conflicts = [
        "emergency.service"
        "shutdown.target"
      ];
      unitConfig.DefaultDependencies = false;
      pathConfig = {
        DirectoryNotEmpty = "/run/systemd/ask-password";
        MakeDirectory = true;
      };
    };
    boot.initrd.systemd.services.nixie-unlock = {
      description = "Ask for the disk passphrase";
      after = [
        "plymouth-start.service"
        "systemd-vconsole-setup.service"
      ];
      conflicts = [
        "emergency.service"
        "shutdown.target"
        "initrd-switch-root.target"
      ];
      before = [
        "emergency.service"
        "shutdown.target"
        "initrd-switch-root.target"
      ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        # systemd's own agent unit is Type=notify; this loop never reports
        # ready, and in that unit it was killed at the start timeout while
        # the boot looked stuck.
        Type = "simple";
        ExecStart = "${agent}/bin/nixie-unlock";
        # The console is where the prompt goes without the splash. Exposure:
        # it runs as root in the initrd, which has nothing to confine it from.
        StandardInput = "tty";
        StandardOutput = "tty";
        StandardError = "tty";
        TTYPath = "/dev/console";
      };
    };
    # A remote-unlock session is the same agent on the session's terminal.
    # Above mkDefault: nixpkgs sets this shell with mkDefault too, and two
    # definitions at one priority stopped every host with remote unlock from
    # evaluating. A site's own plain definition still wins.
    boot.initrd.systemd.users.root.shell = lib.mkIf sec.remoteUnlock.enable (
      lib.mkOverride 900 "${agent}/bin/nixie-unlock"
    );
  };
}
