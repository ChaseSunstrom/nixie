# `nix run .#offline`: prove the clean-clone criterion that the platform
# builds with no network once `nix flake archive` has run.
{ pkgs }:
pkgs.writeShellApplication {
  name = "nixie-offline";
  runtimeInputs = with pkgs; [
    nix
    coreutils
  ];
  # The run itself is packages/offline/offline.sh.
  text = builtins.readFile ./offline/offline.sh;
}
