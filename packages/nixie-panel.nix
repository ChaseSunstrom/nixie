# The front panel: a status screen for the first text console. Same
# language as nixie-cli. Reads the Incus socket read-only through curl and
# the local metrics endpoint, draws in the finish's 256-colour palette, and
# hands the console to `login` on any key.
{ pkgs }:
pkgs.writeShellApplication {
  name = "nixie-panel";
  runtimeInputs = with pkgs; [
    coreutils
    curl
    util-linux # logger
    jq
    qrencode
    iproute2
    ncurses
    procps
    util-linux
    shadow
    gawk
    hostname
  ];
  text = builtins.readFile ./nixie-panel/panel.sh;
}
