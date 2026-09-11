{ lib, ... }:
let
  inherit (import ../lib/option.nix lib) mkOption;
in
{
  options.nixie.monitoring = {
    enable = mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Collect host, guest and GPU metrics with Prometheus so the dashboards
        show history. Costs some memory and disk.
      '';
      nixieUi = {
        section = "services";
        order = 3;
      };
    };
    retention = mkOption {
      type = lib.types.str;
      default = "30d";
      description = "How long metrics are kept.";
    };
    grafana.enable = mkOption {
      type = lib.types.bool;
      default = false;
      description = "Also run Grafana with the default dashboards.";
      nixieUi = {
        section = "services";
        order = 4;
      };
    };
    grafana.port = mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Port Grafana listens on.";
    };
    gpuPowerCap = mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Reference line on the GPU dashboard, in watts. Set it to your card's limit.";
    };
    extraScrapeConfigs = mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = "Extra Prometheus scrape configurations.";
    };
    dashboards = mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = "Extra dashboards, name to JSON file.";
    };
  };
}
