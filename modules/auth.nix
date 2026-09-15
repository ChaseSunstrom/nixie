{
  config,
  lib,
  ...
}:
let
  inherit (import ../lib/option.nix lib) mkOption;

  cfg = config.nixie.auth;
  # Accounts NixOS defines itself. The administrator is made a normal user,
  # and on root that collided inside users-groups ("users.users.root.shell is
  # defined multiple times") with nothing saying why.
  reserved = [
    "root"
    "nobody"
  ];
in
{
  options.nixie.auth = {
    admin.name = mkOption {
      type = lib.types.strMatching "^[a-z_][a-z0-9_-]{0,31}$";
      description = ''
        The one administrator account created at install. It can use sudo, log
        in over SSH and open the web pages. It cannot be root or nobody: the
        administrator is a normal account of its own that uses sudo.
      '';
      nixieUi = {
        section = "auth";
        order = 0;
      };
    };
    admin.passwordFile = mkOption {
      type = lib.types.path;
      description = ''
        A file holding the password hash for the administrator. The installer
        writes it into the site's secrets; it never ends up in the Nix store.
      '';
      nixieUi = {
        section = "auth";
        order = 1;
        secret = "password";
      };
    };
    sshKeys = mkOption {
      type = lib.types.listOf lib.types.singleLineStr;
      default = [ ];
      description = ''
        SSH public keys allowed to log in as the administrator. Any key type
        works. A hardware-backed key is a good choice but is not required.
        With no keys and password login off, SSH cannot be used, which is fine
        for a desktop.
      '';
      nixieUi = {
        section = "auth";
        order = 2;
      };
    };
    secondFactor = mkOption {
      type = lib.types.enum [
        "none"
        "totp"
      ];
      default = "none";
      description = ''
        An extra step for logging in to the host page. "totp" asks for a
        six-digit code from an authenticator app, enrolled during setup.
        Passkeys are not offered because the host page checks logins on the
        server itself, where a browser passkey cannot reach.
      '';
      nixieUi = {
        section = "auth";
        order = 3;
      };
    };
    totpSecretFile = mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Internal: the enrolled authenticator secret when the second factor is \"totp\".";
    };
    ssh.passwordLogin = mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Allow SSH login with the password instead of a key. Anyone who can
        reach port 22 can then try to guess the password; leave this off
        unless you have no way to use a key.
      '';
      nixieUi = {
        section = "auth";
        order = 4;
      };
    };
  };

  config = {
    users.mutableUsers = false;
    users.users.${
      if lib.elem cfg.admin.name reserved then
        throw "nixie.auth.admin.name cannot be \"${cfg.admin.name}\": the administrator is a normal account that uses sudo; choose another name"
      else
        cfg.admin.name
    } =
      {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        hashedPasswordFile = cfg.admin.passwordFile;
        openssh.authorizedKeys.keys = cfg.sshKeys;
      };
    security.sudo.wheelNeedsPassword = true;

    services.openssh = {
      enable = lib.mkDefault (
        config.nixie.profile == "server" || cfg.sshKeys != [ ] || cfg.ssh.passwordLogin
      );
      settings = {
        PasswordAuthentication = cfg.ssh.passwordLogin;
        KbdInteractiveAuthentication = cfg.ssh.passwordLogin;
        PermitRootLogin = "no";
      };
    };
  };
}
