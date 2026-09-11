{ lib, ... }:
let
  inherit (import ../../lib/option.nix lib) mkOption;
in
{
  options.nixie.network.tailscale = {
    enable = mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Join a Tailscale network so you can reach this host and its web pages
        from anywhere without opening ports on your router.
      '';
      nixieUi = {
        section = "network";
        order = 10;
      };
    };
    authKeyFile = mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "A file with a Tailscale auth key so the host joins without a browser login.";
      nixieUi = {
        section = "network";
        order = 11;
        secret = "tailscale";
      };
    };
    serve = mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "/" = "http://127.0.0.1:8080";
      };
      description = "Extra `tailscale serve` entries (path to target) beyond what guests declare.";
    };
  };
}
