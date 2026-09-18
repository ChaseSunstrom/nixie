# Platform packages. Each lands in the slice that needs it.
{
  pkgs,
  inputs,
  self,
}:
let
  web = import ./nixie-web.nix { inherit pkgs; };
  installer = import ./nixie-installer.nix { inherit pkgs; };
in
rec {
  nixie-installer = installer;
  nixie-cli = import ./nixie-cli.nix { inherit pkgs; };
  nixie-panel = import ./nixie-panel.nix { inherit pkgs; };
  nixie-cockpit = import ./nixie-cockpit.nix { inherit pkgs; };
  inherit (web) nixie-ui nixie-setup-web;
  nixie-setup = import ./nixie-setup.nix { inherit pkgs inputs self; };
  deploy = import ./deploy.nix { inherit pkgs; };
  nixie-iso = import ./nixie-iso.nix {
    inherit pkgs inputs self;
    packages = {
      inherit
        nixie-installer
        nixie-setup
        nixie-cli
        deploy
        ;
    };
  };
  # The same image with the kiosk's browser open to a debugger on the
  # loopback, so `nixie-test-iso --kiosk` can drive the page on the screen
  # the way a person at the machine does. Nothing else differs, and nothing
  # the platform installs sets that port.
  nixie-iso-kiosk = import ./nixie-iso.nix {
    inherit pkgs inputs self;
    packages = {
      inherit
        nixie-installer
        nixie-setup
        nixie-cli
        deploy
        ;
    };
    extraModules = [
      (
        { lib, ... }:
        {
          nixie.kiosk.remoteDebugPort = 9222;
          # Chromium listens for its debugger on the loopback whatever it is
          # told, so the image that wants it driven from outside relays it,
          # and opens that port through the installer's firewall, which
          # otherwise lets only SSH and the wizard in.
          networking.firewall.allowedTCPPorts = [ 9223 ];
          systemd.services.nixie-kiosk-debug-relay = {
            description = "Relay the kiosk browser's debugger off the loopback (test image)";
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              ExecStart = "${lib.getExe pkgs.socat} TCP-LISTEN:9223,fork,reuseaddr TCP:127.0.0.1:9222";
              Restart = "always";
            };
          };
        }
      )
    ];
  };
  test-iso = import ./test-iso.nix { inherit pkgs nixie-iso nixie-iso-kiosk; };
  docs = import ./docs.nix { inherit pkgs nixie-setup; };
  media = import ./media.nix { inherit pkgs; };
  demo-shots = import ./demo-shots.nix {
    inherit pkgs;
    inherit ((import ./nixie-web.nix { inherit pkgs; })) nixie-ui;
  };
  offline = import ./offline.nix { inherit pkgs; };
}
