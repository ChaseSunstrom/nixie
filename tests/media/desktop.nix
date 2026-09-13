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
    def wait_mode(m, timeout=30):
        # The shell publishes what it is showing; a fixed sleep raced it and
        # produced screenshots of a surface that had not drawn yet.
        laptop.wait_until_succeeds(
            "grep -q '\"mode\":\"" + m + "\"' /run/user/1000/nixie-shell.state", timeout=timeout)

    def stop_recording(path):
        # wf-recorder writes nothing if its output directory is missing or
        # screen copy fails; say which, rather than failing later on `cp`.
        me("pkill -INT -x wf-recorder; sleep 3")
        size = int(laptop.succeed(f"stat -c %s {path} 2>/dev/null || echo 0").strip())
        assert size > 10000, f"{path} is {size} bytes: wf-recorder recorded nothing"

    laptop.wait_for_unit("greetd.service")
    laptop.wait_for_text("(Reboot|Power Off|Hyprland|Password|nixie)", timeout=300)
    laptop.screenshot("desktop-greeter")
    laptop.send_chars("me\n"); laptop.sleep(2); laptop.send_chars("nixie\n")
    laptop.wait_until_succeeds("pgrep -f 'bin/Hyprland'", timeout=180)  # nixpkgs wraps the binary, so match its argv
    laptop.wait_until_succeeds("pgrep -f quickshell", timeout=180)
    # The shell answers on its socket; without this the first verb can race it.
    laptop.wait_until_succeeds("test -S /run/user/1000/nixie-shell.sock", timeout=60)
    laptop.sleep(6)
    laptop.screenshot("desktop-first-login")
    me("(kitty >/dev/null 2>&1 &) ; sleep 3")
    laptop.screenshot("desktop-bar")
    for mode in ["apps", "files", "calculator", "emoji", "clipboard"]:
        me(f"nixie-shell launcher {mode}"); wait_mode("launcher"); laptop.sleep(2)
        laptop.screenshot(f"desktop-launcher-{mode}")
        laptop.send_key("esc"); laptop.sleep(1)
    # Double quotes: the su wrapper around every me() is single-quoted.
    me('notify-send "Backup finished" "state/ and 3 guest paths, 2.1 GB" ; sleep 1')
    laptop.screenshot("desktop-notification")
    me("nixie-shell notifications"); wait_mode("notifications"); laptop.sleep(2); laptop.screenshot("desktop-notification-center"); laptop.send_key("esc")
    me("nixie-shell osd volume 63"); wait_mode("osd", 15); laptop.sleep(1); laptop.screenshot("desktop-osd-volume")
    me("nixie-shell power"); wait_mode("power"); laptop.sleep(2); laptop.screenshot("desktop-power-menu"); laptop.send_key("esc")
    me("nixie-shell cheatsheet"); wait_mode("cheatsheet"); laptop.sleep(2); laptop.screenshot("desktop-cheatsheet"); laptop.send_key("esc")
    me("nixie-shell control"); wait_mode("control"); laptop.sleep(2); laptop.screenshot("desktop-control-center"); laptop.send_key("esc")
    me("nixie-shell calendar"); wait_mode("calendar"); laptop.sleep(2); laptop.screenshot("desktop-calendar"); laptop.send_key("esc")
    me("nixie-shell wallpapers"); wait_mode("wallpapers"); laptop.sleep(3); laptop.screenshot("desktop-wallpaper-picker"); laptop.send_key("esc")
    # runtime finish switch and a wallpaper change, on video: no rebuild
    me("mkdir -p /home/me/Videos; (wf-recorder -f /home/me/Videos/finish-runtime.mp4 >/dev/null 2>&1 &) ; sleep 2")
    for f in ["paper", "graphite", "umber"]:
        me(f"nixie-shell finish {f}; sleep 3")
        laptop.screenshot(f"desktop-finish-{f}-runtime")
    me("nixie-shell wallpaper next; sleep 3; nixie-shell wallpaper next; sleep 3")
    stop_recording("/home/me/Videos/finish-runtime.mp4")
    laptop.copy_from_vm("/home/me/Videos/finish-runtime.mp4", "media")
    laptop.screenshot("desktop-wallpaper-next")
    # window motion on video: open, move, workspace switch, overview
    me("mkdir -p /home/me/Videos; (wf-recorder -f /home/me/Videos/motion.mp4 >/dev/null 2>&1 &) ; sleep 2")
    # Lua dispatchers: `hyprctl dispatch <legacy>` is a syntax error against
    # a Lua config (D29).
    me("hyprctl dispatch \"hl.dsp.exec_cmd([[kitty]])\"; sleep 2; hyprctl dispatch \"hl.dsp.exec_cmd([[kitty]])\"; sleep 2; hyprctl dispatch \"hl.dsp.window.move({ direction = [[l]] })\"; sleep 1; hyprctl dispatch \"hl.dsp.focus({ workspace = 2 })\"; sleep 1; hyprctl dispatch \"hl.dsp.exec_cmd([[kitty]])\"; sleep 2; hyprctl dispatch \"hl.dsp.focus({ workspace = 1 })\"; sleep 1; nixie-shell switcher; sleep 3; nixie-shell close; sleep 1")
    stop_recording("/home/me/Videos/motion.mp4")
    laptop.copy_from_vm("/home/me/Videos/motion.mp4", "media")
    me("nixie-shell switcher"); wait_mode("switcher"); laptop.sleep(2); laptop.screenshot("desktop-overview"); me("nixie-shell close")
    # local.conf override takes effect on reload
    me('printf "hl.config({ general = { gaps_out = 40 } })\n" >> /home/me/.config/hypr/local.lua; hyprctl reload; sleep 2')
    laptop.screenshot("desktop-local-conf")
    # finish switch: recorded, no reboot
    me("mkdir -p /home/me/Videos; (wf-recorder -f /home/me/Videos/finish.mp4 >/dev/null 2>&1 &) ; sleep 2")
    laptop.succeed("/run/current-system/specialisation/paper/bin/switch-to-configuration test >&2")
    me("hyprctl reload; sleep 4")
    stop_recording("/home/me/Videos/finish.mp4")
    laptop.screenshot("desktop-finish-paper")
    laptop.copy_from_vm("/home/me/Videos/finish.mp4", "media")
    # From outside the graphical session there is no session to name;
    # the root form locks every session and hypridle answers with hyprlock.
    laptop.succeed("loginctl lock-sessions"); laptop.sleep(5); laptop.screenshot("desktop-lock")
  '';
}
