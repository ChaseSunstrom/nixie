# `nix run .#media`: regenerate docs/media from scratch. Every asset comes
# from a media run (a NixOS test that screenshots or records inside a VM),
# and SHOTLIST.md maps each file to the run and the commit that produced it.
{ pkgs }:
pkgs.writeShellApplication {
  name = "nixie-media";
  runtimeInputs = with pkgs; [
    nix
    git
    ffmpeg
    asciinema-agg
    imagemagick
    coreutils
    findutils
    jq
  ];
  # The run itself is packages/media/media.sh.
  text = builtins.readFile ./media/media.sh;
}
