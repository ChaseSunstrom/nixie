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
      # substituters) past nixpkgs.config; its overlay is all HyDE needs.
      nixpkgs.overlays = [
        inputs.hydenix.overlays.default
        # hydenix fetches the cursor from HyDE's master branch, where it is
        # gone; the pinned HyDE source has the same file with the same hash.
        (_: prev: {
          Bibata-Modern-Ice = prev.Bibata-Modern-Ice.overrideAttrs {
            src = "${inputs.hydenix.inputs.hyde}/Source/arcs/Cursor_BibataIce.tar.gz";
          };
        })
      ];
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
