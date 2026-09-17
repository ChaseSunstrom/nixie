# The desktop profile: the greeter comes up, a login lands in a Hyprland
# session (Lua config, no config errors) with the shell bar, every shell
# surface renders, the finish switches at runtime without a rebuild, the
# wallpaper changes with a transition, the screen locks, and switching the
# site's default finish takes effect after an apply without a reboot.
{
  pkgs,
  nixieLib,
  desktopSite,
}:
let
  inherit (pkgs) lib;
in
pkgs.testers.runNixOSTest {
  name = "vm-desktop";
  enableOCR = true;
  nodes.laptop = {
    imports = nixieLib.hostModules ../../examples/desktop-site "laptop" desktopSite.hosts.laptop ++ [
      ./qemu.nix
    ];
    virtualisation.sharedDirectories.nixie-site = {
      source = "${lib.cleanSource ../../examples/desktop-site}";
      target = "/etc/nixie/site";
    };
    virtualisation.memorySize = 4096;
    virtualisation.cores = 4;
    virtualisation.resolution = {
      x = 1280;
      y = 800;
    };
    # A software renderer: the test VM has no GPU.
    environment.sessionVariables.WLR_RENDERER_ALLOW_SOFTWARE = "1";
    environment.systemPackages = [ pkgs.libnotify ];
    # OCR polls are slow; the idle lock must not fire in the middle of a subtest.
    nixie.desktop.idle.lockAfter = 3600;
    nixie.desktop.idle.screenOffAfter = 7200;
    # The other finish, to prove switching the site default takes effect after an apply.
    specialisation.paper.configuration.nixie.desktop.finish = lib.mkForce "paper";
  };

  testScript = builtins.readFile ./desktop.py;
}
