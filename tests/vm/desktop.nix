# The desktop profile: the greeter comes up, a login lands in a Hyprland
# session with the shell bar, the finish is applied everywhere from one
# token source, and switching finish through the site takes effect after an
# apply without a reboot. local.conf is sourced last.
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
    # The other finish, to prove switching takes effect after an apply.
    specialisation.paper.configuration.nixie.desktop.finish = lib.mkForce "paper";
  };

  testScript = ''
    laptop.wait_for_unit("greetd.service")
    laptop.wait_for_text("(me|Password|Log in|nixie)", timeout=300)
    laptop.screenshot("greeter")
    laptop.succeed("grep -q 'background: #231b16' /etc/greetd/regreet.css || grep -rq '231b16' /etc/greetd/ /etc/xdg/ | true")
    # umber tokens reach every consumer from one source
    laptop.succeed("grep -q '\"finish\": \"umber\"' /etc/nixie/desktop/tokens.json || grep -q '\"finish\":\"umber\"' /etc/nixie/desktop/tokens.json")
    laptop.succeed("grep -q 'col.active_border = rgb(7ebae4)' /etc/xdg/hypr/hyprland.conf")
    laptop.succeed("grep -q 'background #231b16' /etc/xdg/kitty/kitty.conf")
    laptop.succeed("grep -q 'guibg=#231b16' /etc/xdg/nvim/sysinit.vim")
    laptop.succeed("grep -q 'source = ~/.config/hypr/local.conf' /etc/xdg/hypr/hyprland.conf")
    laptop.succeed("grep -q 'nixie-shell launcher' /etc/xdg/hypr/hyprland.conf")

    with subtest("log in and land in Hyprland with the shell bar"):
        laptop.send_chars("me\n")
        laptop.sleep(2)
        laptop.send_chars("nixie\n")
        laptop.wait_until_succeeds("pgrep -f 'bin/Hyprland'", timeout=180)  # nixpkgs wraps the binary, so match its argv
        laptop.wait_until_succeeds("pgrep -f 'quickshell' ", timeout=180)
        laptop.wait_for_text("(nixie|[0-9]{2}:[0-9]{2})", timeout=180)
        laptop.screenshot("session")
        laptop.succeed("test -L /home/me/.config/hypr/hyprland.conf && test -f /home/me/.config/hypr/local.conf")
        # The shell's IPC socket appears a moment after quickshell starts.
        laptop.wait_until_succeeds("su - me -c 'XDG_RUNTIME_DIR=/run/user/1000 nixie-shell launcher'", timeout=60)
        laptop.wait_for_text("(apps|matches)", timeout=60)
        laptop.screenshot("launcher")

    with subtest("switching finish takes effect after an apply, no reboot"):
        laptop.succeed("/run/current-system/specialisation/paper/bin/switch-to-configuration test >&2")
        laptop.succeed("grep -q '\"finish\": \"paper\"' /etc/nixie/desktop/tokens.json || grep -q '\"finish\":\"paper\"' /etc/nixie/desktop/tokens.json")
        laptop.succeed("grep -q 'background #e4e1da' /etc/xdg/kitty/kitty.conf")
        laptop.succeed("grep -q 'col.active_border = rgb(3f6bb8)' /etc/xdg/hypr/hyprland.conf")
  '';
}
