# The guest schema. This attrset is the only place guest names appear; every
# derived artifact is computed from it in lib/guests.nix.
{ lib, ... }:
let
  inherit (import ../lib/option.nix lib) mkOption;

  t = lib.types;
  guest = t.submodule (
    { name, ... }:
    {
      options = {
        kind = mkOption {
          type = t.enum [
            "nixos"
            "image"
            "vm"
          ];
          default = "nixos";
          description = "\"nixos\": built from the site. \"image\": a foreign container image with cloud-init. \"vm\": a virtual machine from an image.";
        };
        recipe = mkOption {
          type = t.nullOr t.str;
          default = null;
          description = "A ready-made guest module: \"static-web\", \"oci-service\", or a name the site provides.";
        };
        ip = mkOption {
          type = t.either (t.enum [ "auto" ]) (t.strMatching "^[0-9.]+/[0-9]+$");
          default = "auto";
          description = "\"auto\" takes an address from the network; otherwise a fixed address with prefix length.";
        };
        profiles = mkOption {
          type = t.listOf t.str;
          default = [ ];
          description = "Extra Incus profiles to attach. The kill switch profile is added automatically under exit-node egress.";
        };
        egress = mkOption {
          type = t.nullOr (t.either (t.enum [ "direct" ]) (t.listOf t.str));
          default = null;
          example = [
            "tor"
            "nord"
          ];
          description = ''
            This guest's own way out: "direct", or exits from
            nixie.network.exits in order, the next taking over when one stops;
            none working cuts the guest off. Empty follows
            nixie.network.guestEgress.
          '';
        };
        nesting = mkOption {
          type = t.bool;
          default = false;
          description = "Let the guest run its own containers. Weakens isolation; off unless needed.";
        };
        gpu = mkOption {
          type = t.bool;
          default = false;
          description = "Give the guest every GPU in the host.";
        };
        devices = mkOption {
          type = t.attrsOf (t.attrsOf t.str);
          default = { };
          description = "Extra raw Incus devices, merged last, for anything the schema lacks.";
        };
        limits.memory = mkOption {
          type = t.nullOr t.str;
          default = null;
          example = "4GiB";
          description = "Memory limit.";
        };
        limits.cpu = mkOption {
          type = t.nullOr t.str;
          default = null;
          example = "2";
          description = "CPU limit: a count or a pin set.";
        };
        mounts = mkOption {
          type = t.attrsOf t.str;
          default = { };
          example = {
            "/data/state/web" = "/var/lib/web";
          };
          description = "Host path to guest path. Ownership is shifted so the guest's users own the files.";
        };
        backup = mkOption {
          type = t.listOf t.str;
          default = [ ];
          description = "Host paths included in backups for this guest.";
        };
        expose.tailnet = mkOption {
          type = t.listOf t.port;
          default = [ ];
          example = [ 8080 ];
          description = "Ports published on the tailnet through `tailscale serve`, at /<guest> (and /<guest>-<port> when several). Needs a fixed address.";
        };
        expose.lan = mkOption {
          type = t.listOf t.port;
          default = [ ];
          description = "Ports opened from the local network to this guest.";
        };
        module = mkOption {
          type = t.nullOr t.deferredModule;
          default = null;
          description = "The NixOS configuration of a \"nixos\" guest.";
        };
        image = mkOption {
          type = t.nullOr (
            t.submodule {
              options = {
                remote = mkOption {
                  type = t.str;
                  default = "images";
                  description = "Which image server.";
                };
                fingerprint = mkOption {
                  type = t.str;
                  description = "The exact image, by fingerprint, so it never changes underneath you.";
                };
              };
            }
          );
          default = null;
          description = "Image for \"image\" and \"vm\" guests.";
        };
        cloudInit = mkOption {
          type = t.nullOr t.path;
          default = null;
          description = "cloud-init user-data for \"image\" and \"vm\" guests.";
        };
        firewall = mkOption {
          type = t.lines;
          default = "";
          description = "Extra nftables rules (bridge family) applied to frames from this guest's port, before the default accept.";
        };
        extraConfig = mkOption {
          type = t.attrsOf t.str;
          default = { };
          description = "Raw Incus instance configuration merged last.";
        };
        name = mkOption {
          type = t.str;
          default = name;
          readOnly = true;
          description = "The guest's name, from the attribute name.";
        };
      };
    }
  );
in
{
  options.nixie.guests = mkOption {
    type = t.attrsOf guest;
    default = { };
    description = "The declared guests. Anything else running on the host is a scratch instance.";
  };
}
