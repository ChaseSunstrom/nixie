# A guest serving files from a mounted directory over HTTP.
{ config, lib, ... }:
{
  options.nixie.recipe.staticWeb.root = lib.mkOption {
    type = lib.types.path;
    default = "/var/www";
    description = "Directory served at the root URL; mount it from the data root.";
  };
  config = {
    services.nginx = {
      enable = true;
      virtualHosts.default.root = config.nixie.recipe.staticWeb.root;
    };
    networking.firewall.allowedTCPPorts = [ 80 ];
  };
}
