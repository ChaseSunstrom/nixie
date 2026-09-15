# The bootable installer image: the minimal NixOS CD plus the installer
# system, named and branded as Nixie, with one boot entry per way of
# installing.
{
  modulesPath,
  lib,
  pkgs,
  nixieVersion,
  ...
}:
let
  inherit ((lib.importJSON ../ui/src/tokens/tokens.json)) graphite;
  argb = c: "#FF${lib.removePrefix "#" c}";
  mark = import ../lib/mark.nix graphite;
  # NixOS's GRUB theme in the Graphite finish with the mark in place of the
  # NixOS artwork; its layout and icons stay. GRUB reads only 8 or 16 bits
  # per channel, and ImageMagick writes flat images as low-depth palettes,
  # hence PNG32.
  grubTheme = pkgs.runCommand "nixie-grub-theme" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
    cp -r ${pkgs.nixos-grub2-theme} $out; chmod -R u+w $out; cd $out
    magick -size 319x100 xc:none ${mark 319 100} PNG32:logo.png
    magick -size 1x1 xc:"${graphite.bg}" PNG32:background.png
    for f in boot_menu_*.png; do magick "$f" -fill "${graphite.s1}" -colorize 100 "PNG32:$f"; done
    magick select_c.png -fill "${graphite.brand}" -colorize 100 PNG32:select_c.png
    sed -i -e 's/"#232627"/"${graphite.ink}"/g' \
      -e 's/border_color = #5579C4/border_color = "${graphite.line}"/' \
      -e 's/bg_color = #7EBAE4/bg_color = "${graphite.s1}"/' \
      -e 's/fg_color = #5579C4/fg_color = "${graphite.brand}"/' \
      -e 's/show_text = true/show_text = true\n\ttext_color = "${graphite.ink}"/' theme.txt
  '';
  splash = pkgs.runCommand "nixie-bios-splash.png" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
    magick -size 800x600 xc:"${graphite.bg}" ${mark 800 748} $out
  '';
  entry = mode: label: {
    configuration = {
      nixie.installer.mode = mode;
      isoImage.configurationName = lib.mkForce label;
    };
  };
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ./installer-system.nix
  ];

  image.baseName = lib.mkForce "nixie_${nixieVersion}_${pkgs.stdenv.hostPlatform.system}";
  isoImage.volumeID = "NIXIE";
  system.nixos.distroName = "Nixie";
  system.nixos.label = nixieVersion;
  isoImage.appendToMenuLabel = " install";
  isoImage.configurationName = "(graphical, on this screen)";
  specialisation.web = entry "web" "(from a browser on another device)";
  specialisation.terminal = entry "terminal" "(terminal)";
  isoImage.grubTheme = grubTheme;
  isoImage.splashImage = splash;
  isoImage.syslinuxTheme = ''
    MENU TITLE Nixie
    MENU RESOLUTION 800 600
    MENU CLEAR
    MENU ROWS 6
    MENU CMDLINEROW -4
    MENU TIMEOUTROW -3
    MENU TABMSGROW  -2
    MENU HELPMSGROW -1
    MENU HELPMSGENDROW -1
    MENU MARGIN 0
    MENU COLOR BORDER       30;44   #00000000 #00000000 none
    MENU COLOR SCREEN       37;40   ${argb graphite.ink} #00000000 none
    MENU COLOR TABMSG       31;40   ${argb graphite.muted} #00000000 none
    MENU COLOR TIMEOUT      1;37;40 ${argb graphite.ink} #00000000 none
    MENU COLOR TIMEOUT_MSG  37;40   ${argb graphite.ink} #00000000 none
    MENU COLOR CMDMARK      1;36;40 ${argb graphite.ink} #00000000 none
    MENU COLOR CMDLINE      37;40   ${argb graphite.ink} #00000000 none
    MENU COLOR TITLE        1;36;44 #00000000 #00000000 none
    MENU COLOR UNSEL        37;44   ${argb graphite.ink} #00000000 none
    MENU COLOR SEL          7;37;40 #FFFFFFFF ${argb graphite.brand} std
  '';
  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;
  # The installed system is UEFI only, but VirtualBox and older machines
  # start in BIOS mode, and a medium they cannot boot looks broken. The
  # installer boots there and phase 1 says what to change.
  isoImage.makeBiosBootable = true;
  # The pairing banner reaches a serial console too (headless boxes, test-iso).
  # tty1 is both the console and the wizard's (or the banner's) screen, so boot
  # status stays quiet unless a unit is slow or fails; the Options submenu
  # still offers "Debug Console Output".
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
    "quiet"
  ];
  networking.hostName = "nixie-installer";
  # The CD profile enables things a kiosk installer has no use for.
  services.getty.autologinUser = lib.mkForce null;
  services.getty.helpLine = lib.mkForce ''
    Nixie installer. Terminal install: nixie-deploy --local
    To install from another machine over SSH, set a root password with passwd
    and run the deploy app of the Nixie flake there.
  '';
  documentation.enable = false;
}
