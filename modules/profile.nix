{ lib, ... }:
let
  inherit (import ../lib/option.nix lib) mkOption;
in
{
  imports = [
    ../profiles/server.nix
    ../profiles/desktop.nix
  ];

  options.nixie.profile = mkOption {
    type = lib.types.enum [
      "server"
      "desktop"
    ];
    description = ''
      Which kind of machine this is. A server runs services as isolated Incus
      guests and has no desktop software at all. A desktop is a full Hyprland
      workstation and has no Incus, monitoring or backup stack unless you turn
      them on. The choice is made at install and can be changed only by
      reinstalling.
    '';
    nixieUi = {
      section = "profile";
      order = 0;
    };
  };
}
