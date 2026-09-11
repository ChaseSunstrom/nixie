{
  config,
  lib,
  ...
}:
let
  inherit (import ../lib/option.nix lib) mkOption;
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
}
