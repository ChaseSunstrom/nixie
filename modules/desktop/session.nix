# The session: greetd with a greeter drawn from the tokens, Hyprland,
# PipeWire, NetworkManager, Bluetooth, portals, fonts, cursors.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../../lib/option.nix lib) mkOption;
  cfg = config.nixie.desktop;
  t = (import ../../lib/tokens.nix { inherit lib; }).forFinish cfg.finish;
in
{
  options.nixie.desktop.enable = mkOption {
    type = lib.types.bool;
    default = false;
    description = "Internal: the desktop profile is active.";
  };

  config = lib.mkIf cfg.enable {
    programs.hyprland = {
      enable = true;
      withUWSM = true;
    };
    services.greetd.enable = true;
    programs.regreet = {
      enable = true;
      settings = {
        background.fit = "Cover";
        GTK = {
          application_prefer_dark_theme = lib.mkForce t.dark;
          cursor_theme_name = lib.mkForce "Adwaita";
          font_name = lib.mkForce "Inter 12";
        };
        commands.reboot = [
          "systemctl"
          "reboot"
        ];
        commands.poweroff = [
          "systemctl"
          "poweroff"
        ];
      };
      extraCss = ''
        window { background: ${t.bg}; color: ${t.ink}; }
        .login-box, box.horizontal > box { background: ${t.s1}; border: 1px solid ${t.line}; border-radius: 6px; padding: 24px; }
        entry { background: ${t.s2}; color: ${t.ink}; border: 1px solid ${t.line}; border-radius: 3px; }
        button { background: ${t.brand}; color: #fff; border-radius: 3px; border: 0; }
        label { color: ${t.ink}; }
      '';
    };
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };
    hardware.bluetooth.enable = true;
    hardware.bluetooth.powerOnBoot = true;
    services.blueman.enable = true;
    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    };
    hardware.graphics.enable = true;
    fonts.packages = with pkgs; [
      jetbrains-mono
      inter
      noto-fonts
      noto-fonts-color-emoji
    ];
    fonts.fontconfig.defaultFonts = {
      monospace = [ "JetBrains Mono" ];
      sansSerif = [ "Inter" ];
    };
    services.flatpak.enable = cfg.flatpak.enable;
    users.users.${cfg.user}.extraGroups = [
      "networkmanager"
      "video"
      "audio"
    ];
    security.polkit.enable = true;
    services.dbus.enable = true;
    services.udisks2.enable = true;
    services.gvfs.enable = true;
    programs.dconf.enable = true;
    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
      XCURSOR_THEME = "Adwaita";
      XCURSOR_SIZE = "24";
    };
  };
}
