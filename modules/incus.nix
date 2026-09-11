# The Incus daemon and everything derived from nixie.guests on the host: the
# preseed, the tofu configuration, NixOS guest images, and the declared list.
{ terranix }:
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  inherit (import ../lib/option.nix lib) mkOption;
  guestsLib = import ../lib/guests.nix { inherit lib; };
  cfg = config.nixie.incus;
  guests = config.nixie.guests;
  bridge = config.nixie.network.bridge.name;
  nixosGuests = lib.filterAttrs (_: g: g.kind == "nixos") guests;

  recipeModule =
    g:
    if g.recipe == null then
      { }
    else if builtins.pathExists (../recipes + "/${g.recipe}.nix") then
      import (../recipes + "/${g.recipe}.nix")
    else
      config.nixie.recipes.${g.recipe} or (throw "guest ${g.name}: unknown recipe ${g.recipe}");

  guestSystem =
    g:
    import "${modulesPath}/../lib/eval-config.nix" {
      inherit lib;
      system = null;
      modules = [
        "${modulesPath}/virtualisation/lxc-container.nix"
        "${modulesPath}/virtualisation/lxc-image-metadata.nix"
        (recipeModule g)
        (if g.module == null then { } else g.module)
        {
          nixpkgs.pkgs = pkgs;
          networking.hostName = g.name;
          system.stateVersion = config.system.stateVersion;
          # The nic device names the guest-side interface "uplink".
          networking.useDHCP = lib.mkDefault (g.ip == "auto");
          networking.interfaces.uplink = lib.mkIf (g.ip != "auto") {
            useDHCP = false;
            ipv4.addresses = [
              {
                address = lib.head (lib.splitString "/" g.ip);
                prefixLength = lib.toInt (lib.last (lib.splitString "/" g.ip));
              }
            ];
          };
          networking.defaultGateway =
            lib.mkIf (g.ip != "auto" && config.nixie.network.bridge.mode == "managed-nat")
              (
                lib.removeSuffix ".0" (lib.head (lib.splitString "/" config.nixie.network.bridge.natSubnet)) + ".1"
              );
        }
      ];
    };

  images = lib.mapAttrs (
    name: g:
    let
      sys = guestSystem g;
      package = pkgs.runCommand "nixie-guest-${name}" { } ''
        mkdir -p $out
        ln -s ${sys.config.system.build.tarball}/tarball/*.tar.xz $out/rootfs.tar.xz
        ln -s ${sys.config.system.build.metadata}/tarball/*.tar.xz $out/metadata.tar.xz
      '';
    in
    {
      inherit package;
      # The alias carries the store hash, so a changed image is a new alias
      # and tofu replaces the instance.
      alias = "nixie/${name}/${lib.substring 11 32 (baseNameOf package.outPath)}";
    }
  ) nixosGuests;

  # The control panel bundle plus this host's nixie.json, which is how the
  # UI learns the finish, the declared guests and the site's links.
  ui = config.nixie.incus.ui;
  panel =
    if ui.package != null then
      ui.package
    else
      (import ../packages/nixie-web.nix { inherit pkgs; }).nixie-ui;
  siteJson = pkgs.writeText "nixie.json" (
    builtins.toJSON {
      theme = config.nixie.ui.theme;
      tokens =
        if config.nixie.ui.tokens == null then
          { }
        else
          builtins.fromJSON (builtins.readFile config.nixie.ui.tokens);
      links = config.nixie.ui.links;
      declared = lib.mapAttrs (name: g: {
        inherit (g) kind ip;
        image =
          if g.kind == "nixos" then images.${name}.alias else "${g.image.remote}:${g.image.fingerprint}";
      }) guests;
      inherit (config.nixie.ui) allowSiteEdits;
      declareUrl = null;
      hostUiUrl = if config.nixie.hostUi.enable then ":${toString config.nixie.hostUi.port}" else null;
      # Long history and Grafana are published on the tailnet by tailscale
      # serve; the panel fills in the tailnet name it was opened on.
      prometheusPath =
        if config.nixie.monitoring.enable && config.nixie.network.tailscale.enable then
          "/prometheus"
        else
          null;
      grafanaPath =
        if config.nixie.monitoring.grafana.enable && config.nixie.network.tailscale.enable then
          "/grafana"
        else
          null;
      inherit (config.nixie.monitoring) gpuPowerCap;
    }
  );
  uiDir = pkgs.runCommand "nixie-ui-${config.nixie.host.name}" { } ''
    mkdir -p $out
    cp -r ${panel}/. $out/
    cp ${siteJson} $out/nixie.json
  '';

  tofuConfig = terranix.lib.terranixConfiguration {
    inherit pkgs;
    modules = [ (guestsLib.terranix guests bridge images) ];
  };
in
{
  options.nixie.incus = {
    enable = mkOption {
      type = lib.types.bool;
      default = config.nixie.profile == "server";
      defaultText = "true on the server profile";
      description = "Run the Incus daemon that hosts guests. On a desktop this is off unless you want both.";
    };
    ui.listen = mkOption {
      type = lib.types.enum [
        "tailnet"
        "lan+tailnet"
      ];
      default = if config.nixie.network.tailscale.enable then "tailnet" else "lan+tailnet";
      defaultText = "\"tailnet\" when Tailscale is on, otherwise \"lan+tailnet\"";
      description = ''
        Where the control panel can be opened from. "tailnet" is only over
        Tailscale and is the safest; "lan+tailnet" also answers on your local
        network.
      '';
      nixieUi = {
        section = "network";
        order = 12;
      };
    };
    ui.port = mkOption {
      type = lib.types.port;
      default = 8443;
      description = "Port the control panel listens on.";
    };
    ui.package = mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Replace the control panel with another web bundle. Empty means the Nixie panel.";
    };
    oidc = mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            issuer = mkOption {
              type = lib.types.str;
              description = "Issuer URL of the identity provider.";
            };
            clientId = mkOption {
              type = lib.types.str;
              description = "Client ID registered with the provider.";
            };
            audience = mkOption {
              type = lib.types.str;
              default = "";
              description = "Expected audience claim, if the provider needs one.";
            };
          };
        }
      );
      default = null;
      description = "Log in to the control panel with an identity provider instead of a certificate.";
    };
    pools = mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            driver = mkOption {
              type = lib.types.enum [
                "zfs"
                "dir"
              ];
              default = "zfs";
              description = "Storage driver.";
            };
            source = mkOption {
              type = lib.types.str;
              description = "Dataset or directory backing the pool.";
            };
          };
        }
      );
      default = {
        default = {
          driver = "zfs";
          source = if config.nixie.disks.data != null then "dpool/incus" else "rpool/incus";
        };
      };
      defaultText = "one ZFS pool on the data disk when present, otherwise on the system disk";
      description = "Incus storage pools.";
    };
    images.remotes = mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        images = "https://images.linuxcontainers.org";
      };
      description = "Image servers guests of kind \"image\" and \"vm\" may pull from.";
    };
  };

  options.nixie.recipes = mkOption {
    type = lib.types.attrsOf lib.types.deferredModule;
    default = { };
    description = "Site-provided recipes: a name to a NixOS module a guest may pick with `recipe`.";
  };

  options.nixie.build.guestImages = mkOption {
    type = lib.types.attrsOf lib.types.attrs;
    default = images;
    readOnly = true;
    description = "Internal: built NixOS guest images by name, each with `package` and `alias`.";
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.mapAttrsToList (name: g: {
      assertion = g.kind == "nixos" || g.image != null;
      message = "guest ${name}: kind \"${g.kind}\" needs an image with a pinned fingerprint";
    }) guests;

    virtualisation.incus = {
      enable = true;
      package = pkgs.incus-lts;
      ui.enable = true;
      ui.package = uiDir;
      preseed = {
        config."core.https_address" = ":${toString cfg.ui.port}";
        storage_pools = lib.mapAttrsToList (name: p: {
          inherit name;
          inherit (p) driver;
          config.source = p.source;
        }) cfg.pools;
        profiles = [
          {
            name = "default";
            devices.root = {
              type = "disk";
              path = "/";
              pool = "default";
            };
          }
        ];
      };
    };
    # Incus would otherwise add its own firewall rules for managed networks;
    # the bridge is ours and the ruleset is one file.
    virtualisation.incus.socketActivation = false;
    users.users.${config.nixie.auth.admin.name}.extraGroups = [ "incus-admin" ];

    hardware.nvidia-container-toolkit.enable = lib.mkIf (
      config.nixie.hardware.gpu == "nvidia" && lib.any (g: g.gpu) (lib.attrValues guests)
    ) true;

    environment.etc."nixie/tofu/config.tf.json".source = tofuConfig;
    environment.etc."nixie/guests.json".text = guestsLib.declaredJson guests images;
    # Mount sources must exist before an instance starts, owned so the shifted
    # guest root can write them.
    systemd.tmpfiles.rules = map (p: "d ${p} 0755 root root -") (
      lib.unique (lib.concatMap (g: lib.attrNames g.mounts) (lib.attrValues guests))
    );
  };
}
