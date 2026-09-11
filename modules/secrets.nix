# Wires a site's sops file to the options that need secrets, so a site only
# points at the file and never names individual secrets.
{
  config,
  lib,
  ...
}:
let
  inherit (import ../lib/option.nix lib) mkOption;

  cfg = config.nixie.secrets;
in
{
  options.nixie.secrets.file = mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = ''
      The sops file holding this host's secrets: the administrator password
      hash and whatever the enabled features need. Encrypted in git,
      decrypted on the host with its own key.
    '';
  };

  config = lib.mkIf (cfg.file != null) {
    sops.defaultSopsFile = cfg.file;
    # One identity per host, made by the installer (phase 2) and independent
    # of whether SSH is enabled, so desktops and servers work the same way.
    sops.age.keyFile = "/var/lib/nixie/age.key";
    sops.age.generateKey = true;
    sops.age.sshKeyPaths = [ ];
    sops.gnupg.sshKeyPaths = [ ];
    sops.secrets.admin-password.neededForUsers = true;
    nixie.auth.admin.passwordFile = lib.mkDefault config.sops.secrets.admin-password.path;
  };
}
