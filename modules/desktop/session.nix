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
        background.path = cfg.wallpaperPath;
        GTK = {
          application_prefer_dark_theme = lib.mkForce t.dark;
          cursor_theme_name = lib.mkForce cfg.look.cursor.theme;
          font_name = lib.mkForce "${cfg.fonts.ui} 12";
          icon_theme_name = lib.mkForce cfg.look.iconTheme;
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
        .login-box, box.horizontal > box { background: ${t.s1}; border: 1px solid ${t.line}; border-radius: 12px; padding: 28px; }
        entry { background: ${t.s2}; color: ${t.ink}; border: 1px solid ${t.line}; border-radius: 8px; padding: 8px 12px; }
        entry:focus { border-color: ${t.brand2}; }
        button { background: ${t.brand}; color: #fff; border-radius: 8px; border: 0; padding: 8px 16px; }
        button:hover { background: ${t.brand2}; }
        label { color: ${t.ink}; }
        .dim-label { color: ${t.muted}; }
      '';
    };
    # regreet runs the login shell unless its cache names a session for the
    # user; seeding it makes the first login land in Hyprland.
    systemd.tmpfiles.rules = [
      "d /var/lib/regreet 0755 greeter greeter -"
      "C /var/lib/regreet/state.toml 0644 greeter greeter - ${pkgs.writeText "regreet-state.toml" ''
        last_user = "${cfg.user}"

        [user_to_last_sess]
        ${cfg.user} = "Hyprland (uwsm-managed)"
      ''}"
    ];
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
      monospace = [ cfg.fonts.mono ];
      sansSerif = [ cfg.fonts.ui ];
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
      XCURSOR_THEME = cfg.look.cursor.theme;
      XCURSOR_SIZE = toString cfg.look.cursor.size;
      GTK_THEME = "adw-gtk3${lib.optionalString t.dark "-dark"}";
    };
  };
}
