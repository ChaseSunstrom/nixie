{ lib, ... }:
let
  inherit (import ../../lib/option.nix lib) mkOption;
in
{
  options.nixie.network.firewall.extraRules = mkOption {
    type = lib.types.lines;
    default = "";
    description = "Extra nftables rules for the host's input chain, for a site's own needs.";
  };
}
