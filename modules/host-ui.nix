{ lib, ... }:
let
  inherit (import ../lib/option.nix lib) mkOption;
in
{
  options.nixie.hostUi = {
    enable = mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        A separate web page for the host itself: files, a root terminal, the
        journal, services, disks, and the nixie commands. It is Cockpit.
        Turning it on widens the attack surface of a hardened host, which is
        why it is off.
      '';
      nixieUi = {
        section = "services";
        order = 5;
      };
    };
    listen = mkOption {
      type = lib.types.enum [
        "tailnet"
        "lan+tailnet"
      ];
      default = "tailnet";
      description = "Where the host page can be opened from. Guests can never reach it.";
      nixieUi = {
        section = "services";
        order = 6;
      };
    };
    port = mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Port the host page listens on.";
    };
  };
}
