# HyDE itself, from the site's hydenix flake input (D27). lib/mk-site.nix
# adds this module to every host of a site that has the input; on a host
# without nixie.desktop.hyde.enable it only keeps hydenix's always-on parts
# off.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  on = config.nixie.desktop.hyde.enable && config.nixie.profile == "desktop";
  user = config.nixie.desktop.user;
  # hydenix fetches the cursor from HyDE's master branch, where it is gone;
  # the pinned HyDE source has the same file with the same hash.
  cursor = _: prev: {
    Bibata-Modern-Ice = prev.Bibata-Modern-Ice.overrideAttrs {
      src = "${inputs.hydenix.inputs.hyde}/Source/arcs/Cursor_BibataIce.tar.gz";
    };
  };
  # crates.io answers 403 to any user agent that begins with "curl/", which is
  # what fetchurl sends. The platform's nixpkgs fetches crates from
  # static.crates.io for that reason; hyde-ipc comes from a flake of its own
  # with an older nixpkgs that does not, and nothing has it cached, so a HyDE
  # desktop could not be built at all. It is the only Rust program HyDE pulls
  # in (hydectl is Go, hyq is C++), so the same source is built here with the
  # platform's toolchain.
  hydeIpc = _: prev: {
    hyde-ipc = pkgs.rustPlatform.buildRustPackage {
      pname = "hyde-ipc";
      inherit (prev.hyde-ipc) version;
      src = inputs.hydenix.inputs.hyde-ipc;
      cargoLock.lockFile = "${inputs.hydenix.inputs.hyde-ipc}/Cargo.lock";
    };
  };
  # HyDE's configuration files are written for the Hyprland and the tools
  # hydenix pins. On the platform's newer nixpkgs those options are renamed or
  # gone, and the session came up under a thousand "config error" lines, so
  # the desktop's own packages come from hydenix's nixpkgs while the system
  # around them stays on the platform's.
  hydePkgs = import inputs.hydenix.inputs.nixpkgs {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
    overlays = [
      inputs.hydenix.overlays.default
      cursor
      hydeIpc
    ];
  };
in
{
  imports = [
    inputs.hydenix.inputs.home-manager.nixosModules.home-manager
    inputs.hydenix.nixosModules.default
  ];

  config = lib.mkMerge [
    {
      # hydenix says mkDefault false; its nix, sddm and system modules default
      # to on even then.
      hydenix.enable = on;
      hydenix.nix.enable = false;
      hydenix.sddm.enable = lib.mkDefault on;
      hydenix.system.enable = lib.mkDefault on;
      # hydenix sets 25.05 at normal priority on every host that imports it.
      system.stateVersion = lib.mkOverride 99 "26.05";
    }
    (lib.mkIf on {
      hydenix = {
        hostname = config.nixie.host.name;
        inherit (config.nixie.host) timezone;
        # hydenix writes i18n.defaultLocale from this, so it cannot read it back.
        locale = lib.mkDefault "en_US.UTF-8";
        # systemd-boot and another kernel: collides with lanzaboote and
        # replaces the kernel the ZFS root was chosen for.
        boot.enable = false;
        # The NixOS firewall with SSH open: collides with Nixie's nftables.
        network.enable = false;
        # Steam opens firewall ports and, like Spotify, Discord and VS Code,
        # is unfree: the installer's Apps offer them instead.
        gaming.enable = false;
      };
      # hydenix.nix.enable would build pkgs itself (allowUnfree, extra
      # substituters) past nixpkgs.config; its overlay is all HyDE needs from
      # the system's own package set.
      nixpkgs.overlays = [
        inputs.hydenix.overlays.default
        cursor
      ];
      # The session itself: HyDE's own Hyprland, its portal, and every package
      # its home-manager modules install.
      programs.hyprland = {
        package = lib.mkForce hydePkgs.hyprland;
        portalPackage = lib.mkForce hydePkgs.xdg-desktop-portal-hyprland;
      };
      # The driver stack has to match the compositor: HyDE's Hyprland links
      # hydenix's glibc, the platform's newer Mesa in /run/opengl-driver needs
      # a newer one ("GLIBC_ABI_GNU2_TLS not found"), and the compositor then
      # dies with "CBackend::create() failed" before it draws anything.
      hardware.graphics = {
        package = lib.mkForce hydePkgs.mesa;
        package32 = lib.mkForce hydePkgs.pkgsi686Linux.mesa;
      };
      # hydenix's system module turns sshd on whatever the site says.
      services.openssh.enable = lib.mkOverride 99 (
        config.nixie.auth.sshKeys != [ ] || config.nixie.auth.ssh.passwordLogin
      );
      services.flatpak.enable = config.nixie.desktop.flatpak.enable;
      programs.nm-applet.enable = true;
      users.users.${user} = {
        shell = pkgs.zsh;
        extraGroups = [
          "networkmanager"
          "video"
        ];
      };
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = { inherit inputs; };
        users.${user} = {
          imports = [ inputs.hydenix.homeModules.default ];
          _module.args.pkgs = lib.mkForce hydePkgs;
          hydenix.hm = {
            enable = true;
            spotify.enable = false;
            social.discord.enable = false;
            editors.vscode.enable = false;
            editors.default = "nvim";
          };
        };
      };
    })
  ];
}
