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

  testScript = ''
    def mecmd(cmd):
        return f"su - me -c 'export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=$(ls /run/user/1000 | grep -m1 wayland-) HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -1); {cmd}'"

    def me(cmd):
        return laptop.succeed(mecmd(cmd))

    import json
    # The shell keeps its state in a small JSON next to its socket; small
    # text in the bar and cards is below what OCR reads reliably, so the
    # tests ask the shell and keep the screenshots for people.
    def state():
        return json.loads(laptop.succeed("cat /run/user/1000/nixie-shell.state"))

    def wait_state(pred, what, timeout=60):
        import time
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                st = state()
                if pred(st):
                    return st
            except Exception:
                pass
            time.sleep(1)
        raise Exception(f"shell state never showed {what}: {state()}")

    def show(mode, name):
        me(f"nixie-shell {mode}")
        wait_state(lambda st: st["mode"] == mode, mode)
        laptop.sleep(2)
        laptop.screenshot(name)
        laptop.send_key("esc")
        wait_state(lambda st: st["mode"] == "", "closed")

    laptop.wait_for_unit("greetd.service")
    laptop.wait_for_text("(Reboot|Power Off|Hyprland|Password|Log in|nixie)", timeout=300)
    laptop.screenshot("greeter")
    # The site's finish reaches every consumer from one source; all are shipped.
    laptop.succeed("grep -q '\"finish\":\"graphite\"' /etc/nixie/desktop/tokens.json || grep -q '\"finish\": \"graphite\"' /etc/nixie/desktop/tokens.json")
    # The site's own theme is a finish like any other.
    laptop.succeed("test -s /etc/nixie/desktop/midnight/tokens.json && test -s /etc/nixie/desktop/midnight/gtk.css && ls /etc/nixie/desktop/midnight/wallpapers/*.png >/dev/null")
    laptop.succeed("grep -q '\"midnight\"' /etc/nixie/desktop/settings.json")
    laptop.succeed("grep -q '#0f1420' /etc/nixie/desktop/midnight/tokens.json")
    for f in ["graphite", "umber", "paper"]:
        laptop.succeed(f"test -s /etc/nixie/desktop/{f}/tokens.json && test -s /etc/nixie/desktop/{f}/gtk.css && test -s /etc/nixie/desktop/{f}/kitty.conf && test -s /etc/nixie/desktop/{f}/hyprlock.conf && ls /etc/nixie/desktop/{f}/wallpapers/*.png | grep -q 3")
    laptop.succeed("grep -q 'background #231b16' /etc/nixie/desktop/umber/kitty.conf")
    laptop.succeed("grep -q 'guibg=#1f2226' /etc/xdg/nvim/sysinit.vim")
    laptop.succeed("grep -q 'pcall(require, \"local\")' /etc/xdg/hypr/hyprland.lua")
    laptop.succeed("grep -q 'nixie-shell launcher' /etc/xdg/hypr/hyprland.lua")
    laptop.succeed("fc-list | grep -qi archivo && fc-list | grep -qi 'Material Symbols'")

    with subtest("log in and land in Hyprland with the shell bar, no config errors"):
        laptop.send_chars("me\n")
        laptop.sleep(2)
        laptop.send_chars("nixie\n")
        laptop.wait_until_succeeds("pgrep -f 'bin/Hyprland'", timeout=180)  # nixpkgs wraps the binary, so match its argv
        laptop.wait_until_succeeds("pgrep -f 'quickshell' ", timeout=180)
        laptop.wait_until_succeeds("test -S /run/user/1000/nixie-shell.sock", timeout=60)
        # The bar is a layer-shell surface; its 12 px text is below what OCR
        # reads reliably, so the compositor is asked instead.
        laptop.wait_until_succeeds(mecmd("hyprctl layers") + " | grep -q 'namespace: nixie-shell'", timeout=180)
        laptop.succeed("test -L /home/me/.config/hypr/hyprland.lua && test -f /home/me/.config/hypr/local.lua")
        errs = me("hyprctl configerrors").strip()
        print("configerrors:", errs)
        assert errs in ("", "no errors"), errs
        laptop.wait_until_succeeds("pgrep -f 'swaybg -m fill'", timeout=60)
        laptop.sleep(3)
        laptop.screenshot("session")

    with subtest("launcher lists apps with icons and favourites; the other modes answer"):
        me("nixie-shell launcher")
        st = wait_state(lambda st: st["mode"] == "launcher" and st["results"] >= 5, "apps in the launcher")
        print(st)
        laptop.sleep(4)  # icons load asynchronously
        laptop.screenshot("launcher")
        me("nixie-shell close")
        wait_state(lambda st: st["mode"] == "", "closed")
        me("nixie-shell calculator"); laptop.sleep(1); laptop.send_chars("2*21")
        st = wait_state(lambda st: st["launcher"] == "calculator" and st["first"].strip() == "42", "42 from the calculator")
        laptop.screenshot("launcher-calculator")
        # Escape closes any dialog.
        laptop.send_key("esc")
        wait_state(lambda st: st["mode"] == "", "closed by Escape")

    with subtest("notification popup and centre, OSD, power menu, calendar, control centre, wallpaper picker"):
        # Double quotes: the su wrapper around every me() is single-quoted.
        me('notify-send "Backup finished" "state/ and 3 guest paths, 2.1 GB"')
        wait_state(lambda st: st["notifs"] >= 1, "the notification")
        laptop.sleep(1)
        laptop.screenshot("notification")
        me("nixie-shell notifications")
        st = wait_state(lambda st: st["mode"] == "notifications" and st["notifFirst"], "notifications")
        laptop.sleep(2)
        # The card must show the whole summary and its body: QML reports the
        # summary truncated if the layout starves it (that happened once).
        assert st["notifFirst"] == "Backup finished / state/ and 3 guest paths, 2.1 GB", st
        assert st["notifTruncated"] is False, st
        laptop.screenshot("notification-center")
        me("nixie-shell close")
        wait_state(lambda st: st["mode"] == "", "closed")
        me("nixie-shell osd volume 63"); wait_state(lambda st: st["mode"] == "osd", "the OSD", 15); laptop.screenshot("osd")
        show("power", "power")
        show("calendar", "calendar")
        show("control", "control-center")
        show("wallpapers", "wallpapers")
        show("cheatsheet", "cheatsheet")

    with subtest("networks, devices, the volume mixer, the screenshot menu, keep-awake and the readouts"):
        me("nixie-shell network")
        wait_state(lambda st: st["mode"] == "network", "the network list")
        laptop.sleep(2); laptop.screenshot("network")
        me("nixie-shell close"); wait_state(lambda st: st["mode"] == "", "closed")
        show("bluetooth", "bluetooth")
        show("mixer", "mixer")
        me("nixie-shell screenshots")
        wait_state(lambda st: st["mode"] == "screenshot", "the screenshot menu")
        laptop.sleep(2); laptop.screenshot("screenshot-menu")
        me("nixie-shell close"); wait_state(lambda st: st["mode"] == "", "closed")
        # Keep-awake holds a systemd inhibitor while it is on.
        me("nixie-shell caffeine")
        wait_state(lambda st: st["caffeine"] is True, "keep-awake on")
        laptop.succeed("pgrep -f '[s]ystemd-inhibit .*nixie'")
        me("nixie-shell caffeine")
        wait_state(lambda st: st["caffeine"] is False, "keep-awake off")
        laptop.fail("pgrep -f '[s]ystemd-inhibit .*nixie'")
        # The bar's readouts are real numbers from the machine.
        st = wait_state(lambda st: st["mem"] > 0, "the system readouts", 30)
        assert 0 <= st["cpu"] <= 100 and 0 < st["mem"] <= 100, st

    with subtest("the overview key shows every window, and the screen can be recorded"):
        # Hyprland 0.55 reaches dispatchers through Lua, and a plugin that
        # registers only a legacy dispatcher cannot be called from there
        # (D29), so the overview is the shell's own panel: it lists windows
        # from every workspace, which a plugin overview cannot be asked for.
        # A detached window with its pipes closed: `kitty &` alone keeps the
        # command output open and the driver waits for EOF forever.
        me("(kitty >/dev/null 2>&1 &) ; sleep 3")
        laptop.succeed("test -z \"$(pgrep -f [h]yprspace)\"")
        clients = json.loads(me("hyprctl clients -j"))
        assert clients, "no window for the switcher to show"
        me("nixie-shell switcher")
        wait_state(lambda st: st["mode"] == "switcher", "the window switcher")
        laptop.sleep(2)
        laptop.screenshot("switcher")
        me("nixie-shell close")
        wait_state(lambda st: st["mode"] == "", "closed")
        # wf-recorder is what the record keybind runs; under a software
        # renderer screen copy is the part that can quietly not work.
        me("mkdir -p /home/me/Videos; (wf-recorder -f /home/me/Videos/t.mp4 >/tmp/wf.log 2>&1 &); sleep 5; pkill -INT -x wf-recorder; sleep 3")
        print(laptop.succeed("cat /tmp/wf.log || true"))
        size = int(laptop.succeed("stat -c %s /home/me/Videos/t.mp4").strip())
        print("recording bytes:", size)
        assert size > 10000, f"the recording is {size} bytes"

    with subtest("the finish switches at runtime: tokens, GTK, kitty, Hyprland border, wallpaper"):
        before = me("hyprctl getoption general:col.inactive_border -j")
        me("nixie-shell finish paper")
        laptop.wait_until_succeeds("test \"$(cat /home/me/.config/nixie/finish)\" = paper", timeout=30)
        laptop.succeed("readlink /home/me/.config/gtk-4.0/gtk.css | grep -q /etc/nixie/desktop/paper/gtk.css")
        laptop.succeed("readlink /home/me/.config/nixie/kitty.conf | grep -q /etc/nixie/desktop/paper/kitty.conf")
        laptop.succeed("readlink /home/me/.config/hypr/hyprlock.conf | grep -q /etc/nixie/desktop/paper/hyprlock.conf")
        after = me("hyprctl getoption general:col.inactive_border -j")
        print(before, after)
        assert before != after, "the border colour did not follow the finish"
        laptop.wait_until_succeeds("pgrep -a swaybg | grep -q paper", timeout=30)
        laptop.sleep(3)
        laptop.screenshot("finish-paper")
        # A site theme switches the same way a built-in finish does.
        me("nixie-shell finish midnight")
        wait_state(lambda st: st["finish"] == "midnight", "the site's own finish")
        laptop.succeed("readlink /home/me/.config/nixie/kitty.conf | grep -q /etc/nixie/desktop/midnight/")
        laptop.sleep(2); laptop.screenshot("finish-midnight")
        me("nixie-shell finish graphite")
        laptop.wait_until_succeeds("test \"$(cat /home/me/.config/nixie/finish)\" = graphite", timeout=30)

    with subtest("the wallpaper changes and is remembered"):
        w1 = laptop.succeed("cat /home/me/.config/nixie/wallpaper").strip()
        me("nixie-shell wallpaper next")
        laptop.wait_until_succeeds(f"test \"$(cat /home/me/.config/nixie/wallpaper)\" != \"{w1}\"", timeout=30)
        w2 = laptop.succeed("cat /home/me/.config/nixie/wallpaper").strip()
        laptop.wait_until_succeeds(f"pgrep -a swaybg | grep -q \"{w2}\"", timeout=30)
        laptop.sleep(2)
        laptop.screenshot("wallpaper-next")

    with subtest("the screen locks with the themed lock screen"):
        # From outside the session `lock-session` has no session to name; the
        # root form locks every session, and hypridle answers with hyprlock.
        laptop.succeed("loginctl lock-sessions")
        # The bracket keeps the pattern from matching the checking command itself.
        laptop.wait_until_succeeds("pgrep -f '[h]yprlock'", timeout=30)
        laptop.wait_for_text("(password|[0-9]{2}:[0-9]{2})", timeout=60)
        laptop.screenshot("lock")
        # hyprlock takes the keyboard a moment after it draws; type once it has.
        laptop.sleep(3)
        laptop.send_chars("nixie\n")
        laptop.wait_until_fails("pgrep -f '[h]yprlock'", timeout=60)

    with subtest("the idle rules run commands the compositor accepts"):
        # hypridle runs these verbatim; a legacy `hyprctl dispatch dpms off`
        # is a Lua syntax error against a Lua config (D29) and the screen
        # would simply never blank, so the generated commands are run here.
        import json as _j
        conf = laptop.succeed("cat /etc/xdg/hypr/hypridle.conf")
        cmds = [ln.split("=", 1)[1].strip() for ln in conf.splitlines() if "dpms" in ln]
        assert len(cmds) >= 2, conf
        off = next(c for c in cmds if "off" in c)
        on = next(c for c in cmds if "off" not in c)

        def dpms():
            return _j.loads(me("hyprctl monitors -j"))[0]["dpmsStatus"]

        print(me(off + " 2>&1"))
        for _ in range(10):
            if dpms() is False:
                break
            laptop.sleep(1)
        assert dpms() is False, "the screen never turned off"
        print(me(on + " 2>&1"))
        for _ in range(10):
            if dpms() is True:
                break
            laptop.sleep(1)
        assert dpms() is True, "the screen never came back on"

    with subtest("the nixie command is installed, built without the guest tools"):
        print(laptop.succeed("nixie doctor || true"))
        out = laptop.fail("nixie export anything 2>&1")
        assert "runs no guests" in out, out
        laptop.fail("command -v tofu || command -v incus")

    with subtest("switching the site's default finish takes effect after an apply, no reboot"):
        laptop.succeed("/run/current-system/specialisation/paper/bin/switch-to-configuration test >&2")
        laptop.succeed("grep -q '\"finish\":\"paper\"' /etc/nixie/desktop/tokens.json || grep -q '\"finish\": \"paper\"' /etc/nixie/desktop/tokens.json")
        laptop.succeed("grep -q 'background #e4e1da' /etc/nixie/desktop/paper/kitty.conf")
        laptop.succeed("test \"$(cat /etc/nixie/desktop/default-finish)\" = paper")
  '';
}
