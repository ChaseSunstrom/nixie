# A guest running one OCI image with podman and no daemon.
{ config, lib, ... }:
let
  cfg = config.nixie.recipe.ociService;
in
{
  options.nixie.recipe.ociService = {
    image = lib.mkOption {
      type = lib.types.str;
      example = "docker.io/library/nginx:1.27";
      description = "The image to run, with a tag or digest.";
    };
    ports = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "80:80" ];
      description = "Port mappings, host:container.";
    };
    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Environment variables for the container.";
    };
    volumes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "/var/lib/app:/data" ];
      description = "Bind mounts, guest path to container path.";
    };
  };
  config = {
    virtualisation.podman.enable = true;
    virtualisation.oci-containers = {
      backend = "podman";
      containers.service = {
        inherit (cfg)
          image
          ports
          environment
          volumes
          ;
      };
    };
    networking.firewall.allowedTCPPorts = map (
      p: lib.toInt (lib.head (lib.splitString ":" p))
    ) cfg.ports;
  };
}
