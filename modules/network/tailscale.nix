{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../../lib/option.nix lib) mkOption;
  cfg = config.nixie.network.tailscale;
  net = config.nixie.network;
  # Guest exposures and the site's own entries, as one `tailscale serve` set.
  serveEntries =
    cfg.serve
    // lib.optionalAttrs config.nixie.monitoring.enable {
      "/prometheus" = "http://127.0.0.1:${toString config.nixie.monitoring.port}";
    }
    // lib.optionalAttrs config.nixie.monitoring.grafana.enable {
      "/grafana" = "http://127.0.0.1:${toString config.nixie.monitoring.grafana.port}";
    }
    // lib.listToAttrs (
      lib.concatMap (
        g:
        map (port: {
          name = "/${g.name}${lib.optionalString (lib.length g.expose.tailnet > 1) "-${toString port}"}";
          value = "http://${lib.head (lib.splitString "/" g.ip)}:${toString port}";
        }) g.expose.tailnet
      ) (lib.attrValues config.nixie.guests)
    );
in
{
  options.nixie.network.tailscale = {
    enable = mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Join a Tailscale network so you can reach this host and its web pages
        from anywhere without opening ports on your router.
      '';
      nixieUi = {
        section = "network";
        order = 10;
      };
    };
    authKeyFile = mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "A file with a Tailscale auth key so the host joins without a browser login.";
      nixieUi = {
        section = "network";
        order = 11;
        secret = "tailscale";
      };
    };
    serve = mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "/" = "http://127.0.0.1:8080";
      };
      description = "Extra `tailscale serve` entries (path to target) beyond what guests declare.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = net.egress != "exit-node" || net.exitNode != "";
        message = "nixie.network.egress = \"exit-node\" needs nixie.network.exitNode";
      }
    ]
    ++ lib.mapAttrsToList (name: g: {
      assertion = g.expose.tailnet == [ ] || g.ip != "auto";
      message = "guest ${name}: expose.tailnet needs a fixed ip";
    }) config.nixie.guests;
    services.tailscale = {
      enable = true;
      inherit (cfg) authKeyFile;
      useRoutingFeatures = "both";
      extraUpFlags = lib.optionals (net.egress == "exit-node") [
        "--exit-node=${net.exitNode}"
        "--exit-node-allow-lan-access=${lib.boolToString net.exitNodeAllowLan}"
      ];
    };
    # `tailscale serve` state is imperative; this rewrites it from the site on
    # every activation so the set of published services is always what git says.
    systemd.services.nixie-tailscale-serve = lib.mkIf (serveEntries != { }) {
      description = "Publish declared services on the tailnet";
      wantedBy = [ "multi-user.target" ];
      after = [ "tailscaled.service" ];
      requires = [ "tailscaled.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # exposure: talks to tailscaled over its socket as root; nothing else.
        ExecStart = pkgs.writeShellScript "nixie-tailscale-serve" ''
          set -eu
          ${pkgs.tailscale}/bin/tailscale serve reset
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              path: target:
              "${pkgs.tailscale}/bin/tailscale serve --bg --set-path ${lib.escapeShellArg path} ${lib.escapeShellArg target}"
            ) serveEntries
          )}
        '';
      };
    };
  };
}
