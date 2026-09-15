# The boot splash: the Nixie finish from the loader to the login or the
# wizard, and the disk passphrase asked on the same screen.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../lib/option.nix lib) mkOption;
  sec = config.nixie.security;
  # The duress check replaces the console's password agent, which systemd
  # does not start while Plymouth runs, so a splash would let the duress
  # passphrase through unchecked; the attestation code is printed on the text
  # console a splash covers.
  needsTextConsole = sec.duress.enable || sec.attestation.enable;
in
{
  options.nixie.host.bootSplash = mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Show the Nixie logo while the machine starts and ask for the disk
      passphrase on the same screen, in the installer's look. A machine with
      the duress passphrase or boot attestation keeps the plain text console
      either way, because both need it.
    '';
  };

  config = lib.mkIf (config.nixie.host.bootSplash && !needsTextConsole) {
    boot.plymouth = {
      enable = true;
      theme = "nixie";
      # In the host's finish: the desktop's (its own themes and HyDE's
      # included), which on a server is nixie.ui.theme.
      themePackages = [
        (import ../packages/nixie-plymouth.nix {
          inherit pkgs;
          t = config.nixie.desktop.tokens;
        })
      ];
      font = "${(import ../packages/nixie-web.nix { inherit pkgs; }).archivo}";
    };
  };
}
