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
  testScript = ''
    def me(cmd):
        return laptop.succeed(f"su - me -c 'export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=$(ls /run/user/1000 | grep -m1 wayland-) HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -1); {cmd}'")
    laptop.wait_for_unit("greetd.service")
    laptop.wait_for_text("(me|Password|nixie)", timeout=300)
    laptop.screenshot("desktop-greeter")
    laptop.send_chars("me\n"); laptop.sleep(2); laptop.send_chars("nixie\n")
    laptop.wait_until_succeeds("pgrep -x Hyprland", timeout=180)
    laptop.wait_until_succeeds("pgrep -f quickshell", timeout=180)
    laptop.sleep(6)
    laptop.screenshot("desktop-first-login")
    me("kitty & sleep 3")
    laptop.screenshot("desktop-bar")
    for mode in ["apps", "files", "calculator", "emoji", "clipboard"]:
        me(f"nixie-shell launcher {mode}"); laptop.sleep(2)
        laptop.screenshot(f"desktop-launcher-{mode}")
        laptop.send_key("esc"); laptop.sleep(1)
    me("notify-send 'Backup finished' 'state/ and 3 guest paths, 2.1 GB' ; sleep 1")
    laptop.screenshot("desktop-notification")
    me("nixie-shell notifications"); laptop.sleep(2); laptop.screenshot("desktop-notification-center"); laptop.send_key("esc")
    me("nixie-shell osd volume 63"); laptop.sleep(1); laptop.screenshot("desktop-osd-volume")
    me("nixie-shell power"); laptop.sleep(2); laptop.screenshot("desktop-power-menu"); laptop.send_key("esc")
    me("nixie-shell cheatsheet"); laptop.sleep(2); laptop.screenshot("desktop-cheatsheet"); laptop.send_key("esc")
    # window motion on video: open, move, workspace switch, overview
    me("mkdir -p /home/me/Videos; (wf-recorder -f /home/me/Videos/motion.mp4 >/dev/null 2>&1 &) ; sleep 2")
    me("hyprctl dispatch exec kitty; sleep 2; hyprctl dispatch exec kitty; sleep 2; hyprctl dispatch movewindow l; sleep 1; hyprctl dispatch workspace 2; sleep 1; hyprctl dispatch exec kitty; sleep 2; hyprctl dispatch workspace 1; sleep 1; hyprctl dispatch overview:toggle; sleep 3; hyprctl dispatch overview:toggle; sleep 1")
    me("pkill -INT -x wf-recorder; sleep 3")
    laptop.copy_from_vm("/home/me/Videos/motion.mp4", "media")
    me("hyprctl dispatch overview:toggle"); laptop.sleep(3); laptop.screenshot("desktop-overview"); me("hyprctl dispatch overview:toggle")
    # local.conf override takes effect on reload
    me("printf 'general { gaps_out = 40 }\n' >> /home/me/.config/hypr/local.conf; hyprctl reload; sleep 2")
    laptop.screenshot("desktop-local-conf")
    # finish switch: recorded, no reboot
    me("(wf-recorder -f /home/me/Videos/finish.mp4 >/dev/null 2>&1 &) ; sleep 2")
    laptop.succeed("/run/current-system/specialisation/paper/bin/switch-to-configuration test >&2")
    me("hyprctl reload; sleep 4; pkill -INT -x wf-recorder; sleep 3")
    laptop.screenshot("desktop-finish-paper")
    laptop.copy_from_vm("/home/me/Videos/finish.mp4", "media")
    me("loginctl lock-session"); laptop.sleep(4); laptop.screenshot("desktop-lock")
  '';
}
