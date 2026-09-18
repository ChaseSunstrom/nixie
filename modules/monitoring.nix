# Prometheus for host, guest and GPU metrics, Grafana by option, dashboards
# shipped as JSON. Scrape targets and dashboard variables come from the guest
# attrset through the Incus metrics endpoint's labels.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../lib/option.nix lib) mkOption;
  cfg = config.nixie.monitoring;
  gpu = config.nixie.hardware.gpu == "nvidia";
  # The two the platform knows about, which a site may turn off, plus any
  # other of nixpkgs' exporters the site names. Every one answers on this
  # host alone; the local Prometheus is the only thing that reads them.
  wanted = name: default: cfg.exporters.${name}.enable or default;
  exporters = lib.mapAttrs (_: e: e // { listenAddress = "127.0.0.1"; }) (
    {
      node = {
        enable = wanted "node" true;
        enabledCollectors = [ "systemd" ];
      };
      nvidia-gpu.enable = wanted "nvidia-gpu" gpu;
    }
    // lib.mapAttrs (_: e: { inherit (e) enable; }) (
      lib.removeAttrs cfg.exporters [
        "node"
        "nvidia-gpu"
      ]
    )
  );
  metricsPort = 8444;
  # A dashboard's only site-specific number is the GPU power cap, so it is
  # substituted here rather than typed into JSON by hand.
  shipped = pkgs.runCommand "nixie-dashboards" { } ''
    mkdir -p $out
    cp ${../dashboards}/*.json $out/
    sed -i 's/"__GPU_POWER_CAP__"/${
      if cfg.gpuPowerCap == null then "null" else toString cfg.gpuPowerCap
    }/' $out/gpu.json
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: f: "cp ${f} $out/${n}.json") cfg.dashboards)}
  '';
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
    port = mkOption {
      type = lib.types.port;
      # Prometheus' own default is 9090, which is also Cockpit's, and the host
      # page is the one of the two a person types into a browser.
      default = 9091;
      description = "Port Prometheus listens on, on this host only. Not 9090: the host page uses that one.";
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
    exporters = mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.enable = mkOption {
            type = lib.types.bool;
            default = true;
            description = "Collect this machine's figures with this exporter.";
          };
        }
      );
      default = { };
      example = lib.literalExpression "{ node.enable = false; }";
      description = ''
        Which of Prometheus' exporters run, by the name nixpkgs gives them.
        "node" (this machine's own figures) is on, and "nvidia-gpu" is on
        when the machine has an NVIDIA card; naming either here with
        `enable = false` turns it off, and anything else nixpkgs offers can
        be turned on. What is scraped follows what runs.
      '';
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
    dashboardsDir = mkOption {
      type = lib.types.package;
      default = shipped;
      readOnly = true;
      description = "Internal: the provisioned dashboards, for the control panel to import.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Two services on one port means one of them dies at boot with nothing but
    # a journal line to say so; say it here instead.
    assertions =
      let
        listeners = [
          {
            name = "nixie.monitoring.port";
            inherit (cfg) port;
          }
        ]
        ++ lib.optional cfg.grafana.enable {
          name = "nixie.monitoring.grafana.port";
          inherit (cfg.grafana) port;
        }
        ++ lib.optional config.nixie.hostUi.enable {
          name = "nixie.hostUi.port";
          inherit (config.nixie.hostUi) port;
        };
      in
      [
        {
          assertion = lib.length (lib.unique (map (l: l.port) listeners)) == lib.length listeners;
          message = "these listen on one host and need different ports: ${
            lib.concatMapStringsSep ", " (l: "${l.name} = ${toString l.port}") listeners
          }";
        }
      ];
    systemd.services.grafana.preStart = lib.mkIf cfg.grafana.enable (
      lib.mkBefore ''
        if [ ! -s /var/lib/grafana/nixie-secret-key ]; then
          (umask 077; ${pkgs.openssl}/bin/openssl rand -hex 32 >/var/lib/grafana/nixie-secret-key)
        fi
      ''
    );
    services.prometheus = {
      enable = true;
      inherit (cfg) port;
      listenAddress = "127.0.0.1";
      retentionTime = cfg.retention;
      inherit exporters;
      # One job per exporter that runs, at whatever port nixpkgs gives it.
      scrapeConfigs =
        lib.mapAttrsToList (name: _: {
          job_name = name;
          static_configs = [
            {
              targets = [
                "127.0.0.1:${toString config.services.prometheus.exporters.${name}.port}"
              ];
            }
          ];
        }) (lib.filterAttrs (_: e: e.enable) exporters)
        ++ lib.optional config.nixie.incus.enable {
          job_name = "incus";
          metrics_path = "/1.0/metrics";
          scheme = "https";
          tls_config.insecure_skip_verify = true;
          static_configs = [ { targets = [ "127.0.0.1:${toString metricsPort}" ]; } ];
        }
        ++ cfg.extraScrapeConfigs;
    };

    # The metrics endpoint is bound to this host only and read by the local
    # Prometheus, so the certificate dance would protect nothing.
    virtualisation.incus.preseed.config = lib.mkIf config.nixie.incus.enable {
      "core.metrics_address" = "127.0.0.1:${toString metricsPort}";
      "core.metrics_authentication" = false;
    };

    services.grafana = lib.mkIf cfg.grafana.enable {
      enable = true;
      settings.server = {
        http_addr = "127.0.0.1";
        http_port = cfg.grafana.port;
        # Published under /grafana by tailscale serve when Tailscale is on.
        root_url = "%(protocol)s://%(domain)s/grafana/";
        serve_from_sub_path = true;
      };
      # Grafana wants its own secret key; it is made on first start and never
      # enters the store or the site.
      settings.security.secret_key = "$__file{/var/lib/grafana/nixie-secret-key}";
      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            uid = "nixie-prometheus";
            type = "prometheus";
            url = "http://127.0.0.1:${toString cfg.port}";
            isDefault = true;
          }
        ];
        dashboards.settings.providers = [
          {
            name = "nixie";
            options.path = shipped;
          }
        ];
      };
    };
  };
}
