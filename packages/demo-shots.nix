# `nix run .#demo-shots`: every screen of the control panel in all three
# finishes, from demo mode. The brief asks for these in CI, and demo mode is
# what lets them run there: no daemon, no VM, no KVM.
{ pkgs, nixie-ui }:
let
  py = pkgs.python3.withPackages (p: [ p.playwright ]);
in
pkgs.writeShellApplication {
  name = "nixie-demo-shots";
  runtimeInputs = [ pkgs.coreutils ];
  text = ''
    out=''${1:-docs/media/demo}
    export PLAYWRIGHT_BROWSERS_PATH=${pkgs.playwright-driver.browsers}
    # Chromium from the same pin as the driver, so the two agree.
    exec ${py}/bin/python3 ${./demo-shots/shots.py} ${nixie-ui} "$out" ${../design}
  '';
}
