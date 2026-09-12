# The desktop

One Hyprland desktop, three finishes, everything declared in the site and
switchable for a session without a rebuild. This page is the whole keybinding
scheme and every knob.

## Keys

| keys | does |
|---|---|
| `Super+Return` / `Super+B` / `Super+E` | terminal, browser, files (`nixie.desktop.defaultApps`) |
| `Super+Space` | launcher; `Tab` cycles apps, files, calculator, emoji, clipboard |
| `Super+A` | control centre: volume, brightness, Wi-Fi, Bluetooth, do not disturb, night light, keep awake, media, finish, wallpaper, and doors to the network, device and volume lists |
| `Super+N` | notification centre (do not disturb, clear all) |
| `Super+Tab` | window switcher |
| `Super+Esc` | power menu |
| `Super+/` | this cheat-sheet on screen |
| `Super+W`, `Super+Shift+W` | next wallpaper, wallpaper picker |
| `Super+T` | next finish (Graphite, Umber, Paper) for this session |
| `Super+Q`, `Super+F`, `Super+Shift+F`, `Super+V`, `Super+P` | close, fullscreen, maximise, float, pin |
| `Super+H/J/K/L`, `Super+Shift+H/J/K/L` | focus, move |
| `Super+1..9`, `Super+Shift+1..9`, `Super+S` | workspace, send there, scratchpad |
| `` Super+` ``, `Super+Tab` | every open window, with the workspace it is on |
| `Super+Shift+S`, `Super+Shift+R`, `Super+Shift+C` | screenshot with annotation, record, colour picker |
| `nixie-shell screenshots` | the screenshot menu: region, window, whole screen, after five seconds |
| `nixie-shell network` / `bluetooth` / `mixer` | join a Wi-Fi network (with its password), connect a paired device, set the volume of each playing app |
| `nixie-shell caffeine` | keep the screen awake until it is turned off again |
| `Super+,`, `Super+.`, `Super+=` | clipboard, emoji, calculator |
| `Super+Ctrl+L` | lock |
| volume, brightness and media keys | OSD and playerctl |

Clicking the mark opens the launcher, the indicators open the control
centre, the bell the notification centre, the clock the calendar.

## Options

`nixie.desktop.*` in the site (see the [option reference](reference/options.md)):

- `finish`: the default finish (Graphite, the dark neutral one, unless the
  site says otherwise). `look.gaps.inner`, `look.gaps.outer`,
  `look.rounding`, `look.borderSize`, `look.blur`, `look.animations`
  (`full`, `reduced`, `none`), `look.barPosition`, `look.terminalOpacity`,
  `look.cursor.theme`, `look.cursor.size`, `look.iconTheme`,
  `look.systemReadouts` (processor, memory and temperature in the bar).
- `audioVisualiser.enable`: a spectrum of what is playing, in the control
  centre. Off by default because it costs a background process.
- `fonts.ui` (Archivo), `fonts.mono` (JetBrains Mono).
- `wallpaper` (one image), `wallpapers` (a folder for the picker),
  `wallpaperCycle` (minutes), `accentFromWallpaper` (the accent is taken
  from the wallpaper's most saturated colour and used for borders and the
  shell, the way HyDE's wallbash does it).
- `favourites` (desktop-entry ids at the top of the launcher),
  `workspaces.labels`, `clock.format`, `terminal.greeting`.
- `keybinds` (`"SUPER + X" = "command"`), `autostart`, `monitors`,
  `keyboard.*`, `defaultApps.*`, `packages.*`, `power.*`, `idle.*`,
  `nightLight.enable`, `overview.enable`.

### Using HyDE itself instead

`nixie.desktop.hyde.enable = true` stands the Nixie desktop down completely
and leaves the session to HyDE, which your site brings in. The packaged form
is the hydenix flake:

```nix
# flake.nix of your site
inputs.hydenix.url = "github:richen604/hydenix";

# the host's settings
{
  imports = [
    inputs.hydenix.inputs.home-manager.nixosModules.home-manager
    inputs.hydenix.nixosModules.default
  ];
  nixie.desktop.hyde.enable = true;
  hydenix.enable = true;
  home-manager.users.<you> = { hydenix.hm.enable = true; };
}
```

Everything else about the host is unchanged: the same installer and phases,
the same disks, encryption and security options, the same `nixie` command,
and the server profile is untouched. Two things to know before you choose
it. HyDE's theme tool downloads a theme from its repository when you switch
themes, so that part of the system is not reproducible from your site and
reaches the network on use; and HyDE brings home-manager and its own
Hyprland, bar and launcher, so the Nixie shell, finishes and
`nixie-shell` verbs are not there. If you want HyDE's *look* without that,
import its themes instead (below) and keep the Nixie desktop.

### Themes of your own, and HyDE's

`nixie.desktop.themes.<name>` adds a finish: give it colours (any you leave
out keep Graphite's) and optionally a folder of wallpapers. It then appears
in the control centre and in `nixie-shell finish <name>` like the built-in
three.

HyDE's themes work the same way. Pin the theme repository and point at a
theme inside it:

```nix
# flake.nix
inputs.hyde-themes = {
  url = "github:HyDE-Project/hyde-themes/Catppuccin-Mocha";
  flake = false;
};

# site.nix
nixie.desktop.hyde.themes.catppuccin-mocha =
  "${inputs.hyde-themes}/Configs/.config/hyde/themes/Catppuccin Mocha";
```

The theme's palette and wallpapers are read at build time from the files it
ships. Nothing from the theme is executed, and nothing is downloaded on the
machine, so a theme is as reproducible as the rest of the system.

`nixie menu` (a launcher entry) edits the site for the finish, wallpaper and
packages, shows the diff and runs `nixie apply`.

## Per-user, no rebuild

Every finish's assets are shipped under `/etc/nixie/desktop/<finish>/`
(tokens, GTK CSS, kitty colours, hyprlock, wallpapers). The active finish is
`~/.config/nixie/finish`; `nixie-shell finish <name>` writes it, relinks
`~/.config/gtk-{3,4}.0/gtk.css`, `~/.config/nixie/kitty.conf` and
`~/.config/hypr/hyprlock.conf`, sets the GTK colour scheme and icon theme,
reloads Hyprland (its Lua config reads the tokens at load time), signals
kitty to reread its config and switches the wallpaper.
The wallpaper choice lives in `~/.config/nixie/wallpaper`; with
`accentFromWallpaper`, `~/.config/nixie/accent` holds the derived colour
that borders and the shell prefer.

`~/.config/hypr/local.lua` is loaded last by the generated
`hyprland.lua`, for example:

```lua
hl.config({ general = { gaps_out = 24 } })
hl.bind("SUPER + G", hl.dsp.exec_cmd("gimp"))
```

`~/.config/nixie/local.conf` is included last by kitty.

## What is where

| piece | from |
|---|---|
| compositor | Hyprland 0.55 (Lua config, `/etc/xdg/hypr/hyprland.lua`) |
| shell | Quickshell, `modules/desktop/shell/shell.qml`, driven by `nixie-shell <verb>` |
| wallpaper | swaybg, one process per image and per output; three generated per finish |
| networks, devices, streams | NetworkManager, BlueZ and PipeWire through `nmcli`, `bluetoothctl` and `pactl`, listed and set from the shell |
| lock, idle | hyprlock, hypridle |
| night light | hyprsunset |
| screenshots, recording, colour | grim + slurp + satty, wf-recorder, hyprpicker |
| theme | adw-gtk3 with per-finish CSS, Papirus icons, Bibata cursor, Material Symbols glyphs |
| terminal | kitty, fish + starship, fastfetch |
| greeter | greetd + regreet, themed from the tokens |
