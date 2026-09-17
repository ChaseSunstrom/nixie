# Media: the desktop. Greeter, session, launcher modes, notifications, OSDs,
# power menu, lock screen, overview; window motion and a finish switch on
# video recorded inside the session with wf-recorder.
{
  pkgs,
  nixieLib,
  desktopSite,
}:
let
  inherit (pkgs) lib;
in
pkgs.testers.runNixOSTest {
  name = "media-desktop";
  enableOCR = true;
  nodes.laptop = {
    imports = nixieLib.hostModules ../../examples/desktop-site "laptop" desktopSite.hosts.laptop ++ [
      ../vm/qemu.nix
    ];
    virtualisation.sharedDirectories.nixie-site = {
      source = "${lib.cleanSource ../../examples/desktop-site}";
      target = "/etc/nixie/site";
    };
    virtualisation.memorySize = 4096;
    virtualisation.cores = 4;
    virtualisation.resolution = {
      x = 1920;
      y = 1080;
    };
    environment.sessionVariables.WLR_RENDERER_ALLOW_SOFTWARE = "1";
    specialisation.paper.configuration.nixie.desktop.finish = lib.mkForce "paper";
    environment.systemPackages = [ pkgs.libnotify ];
  };
  testScript = builtins.readFile ./desktop.py;
}
