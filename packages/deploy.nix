# The headless front end: a gum wizard over the same phases, driving a
# target over SSH (nixos-anywhere for the kexec), or the machine it runs on
# with --local (the ISO's tty2).
{ pkgs }:
pkgs.writeShellApplication {
  name = "nixie-deploy";
  runtimeInputs = with pkgs; [
    coreutils
    git
    gnused
    gum
    jq
    nix
    nixos-anywhere
    openssh
    rsync
    (import ./nixie-installer.nix { inherit pkgs; })
  ];
  # The phase commands are meant to expand on the client before they travel.
  excludeShellChecks = [ "SC2029" ];
  text = builtins.readFile ../installer/deploy.sh;
}
