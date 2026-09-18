# The data root and the manifest: state/ is precious, cache/ is rebuilt by
# `nixie fetch` from small per-kind fetchers, media/ is neither.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../lib/option.nix lib) mkOption;
  cfg = config.nixie.data;
  root = toString cfg.root;
  enabled = config.nixie.incus.enable || cfg.manifest != { };
  platformKinds = lib.genAttrs [ "http" "hf" "oci" "incus-images" ] (k: ../data-kinds + "/${k}.nix");
  kinds = lib.mapAttrs (_: f: import f { inherit pkgs; }) (platformKinds // cfg.kinds);
  manifestFile = pkgs.writeText "data.json" (builtins.toJSON cfg.manifest);

  # Guests pull from the machine they run on; the fetcher pushes to the same
  # registry over the loopback.
  inherit (cfg) registry;
  registryAddress = "127.0.0.1:${toString registry.port}";

  # One script per kind, run only for the entries the manifest has for it.
  # Each entry is fetched into cache/<kind>/<name> and marked .complete; a
  # half-fetched entry is cleared and fetched again.
  fetcher =
    kind: k:
    pkgs.writeShellApplication {
      name = "nixie-fetch-${kind}";
      runtimeInputs = k.runtimeInputs ++ [
        pkgs.jq
        # The loop's own mkdir, rm and install: a unit's PATH holds nothing.
        pkgs.coreutils
      ];
      text = ''
        base="${root}/cache/${kind}"
        ${lib.optionalString registry.enable ''
          export NIXIE_REGISTRY="${registryAddress}"
          # cache/ is re-fetchable and may have been cleared since the
          # registry started; it runs as its own user and cannot make its
          # own directory under a cache/ that belongs to root.
          install -d -o docker-registry -g docker-registry -m 0750 "${root}/cache/registry"
        ''}
        jq -c '.["${kind}"] // {} | to_entries[]' ${manifestFile} | while read -r e; do
          name=$(jq -r .key <<<"$e"); entry=$(jq -c .value <<<"$e")
          dest="$base/$name"
          if [ -e "$dest/.complete" ]; then echo "${kind}/$name: complete"; continue; fi
          echo "${kind}/$name: fetching"
          rm --recursive --force "$dest"; mkdir -p "$dest"
          ( ${k.fetch} )
          touch "$dest/.complete"
        done
      '';
    };
  fetchAll = pkgs.writeShellApplication {
    name = "nixie-fetch";
    runtimeInputs = lib.mapAttrsToList fetcher kinds;
    text = ''
      ${lib.concatMapStringsSep "\n" (kind: "nixie-fetch-${kind}") (lib.attrNames kinds)}
    '';
  };
in
{
  options.nixie.data = {
    root = mkOption {
      type = lib.types.path;
      default = "/data";
      description = ''
        Where state/, cache/ and media/ live. state/ is irreplaceable and is
        backed up. cache/ is never backed up because `nixie fetch` can rebuild
        it from the manifest. They never share a directory.
      '';
    };
    mediaBackup = mkOption {
      type = lib.types.bool;
      default = false;
      description = "Include media/ in backups. It can be large.";
    };
    manifest = mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf (lib.types.attrsOf lib.types.anything));
      default = { };
      description = "What lives in cache/, by fetcher kind and name. See the data guide.";
    };
    registry = {
      enable = mkOption {
        type = lib.types.bool;
        default = cfg.manifest.oci or { } != { };
        defaultText = "true when the manifest lists any container images";
        description = ''
          Serve the container images the manifest lists from this machine, so
          guests pull them from here instead of from the internet. Off, they
          are still fetched into the cache as an OCI layout, but nothing
          serves them.
        '';
        nixieUi = {
          section = "services";
          advanced = true;
        };
      };
      port = mkOption {
        type = lib.types.port;
        default = 5000;
        description = "Where the image registry answers on this machine.";
        nixieUi = {
          section = "services";
          advanced = true;
        };
      };
    };
    fetch.timer = mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "daily";
      description = "Also run `nixie fetch` on this schedule.";
    };
    kinds = mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = "Extra fetcher kinds provided by the site, name to file.";
    };
  };

  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = lib.all (k: kinds ? ${k}) (lib.attrNames cfg.manifest);
        message = "nixie.data.manifest names a kind with no fetcher; add it to nixie.data.kinds";
      }
    ];
    systemd.tmpfiles.rules = [
      "d ${root} 0755 root root -"
      "d ${root}/state 0750 root root -"
      "d ${root}/cache 0755 root root -"
      "d ${root}/media 0755 root root -"
    ];
    environment.systemPackages = [ fetchAll ];
    environment.etc."nixie/data.json".source = manifestFile;
    systemd.services.nixie-fetch = {
      description = "Fetch everything the data manifest lists into the cache";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe fetchAll;
        # exposure: writes the cache directory as root; network client only.
        ProtectSystem = "strict";
        ReadWritePaths = [ "${root}/cache" ];
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
    # The brief's `oci` kind puts images "into the local registry mirror":
    # the images the manifest lists are served from this machine, so a guest
    # pulls from here rather than from the internet, and a machine with no
    # way out still starts its containers. Its storage is under cache/,
    # which is re-fetchable and never backed up, like the layouts beside it.
    services.dockerRegistry = lib.mkIf registry.enable {
      enable = true;
      # Reachable by the guests, which is its whole purpose; the host's
      # firewall is what keeps it off the LAN (modules/network/firewall.nix).
      listenAddress = "0.0.0.0";
      inherit (registry) port;
      storagePath = "${root}/cache/registry";
      # What the cache holds is disposable and re-fetchable, so it may as
      # well be tidied.
      enableDelete = true;
      enableGarbageCollect = true;
    };
    # Its own directory, made as root at the moment it is needed: the data
    # root is a mount of its own, and a tmpfiles rule can run before it is
    # there. The registry itself runs as its own user and cannot make a
    # directory under cache/, which is root's.
    systemd.services.docker-registry.serviceConfig.ExecStartPre =
      lib.mkIf registry.enable "+${pkgs.coreutils}/bin/install -d -o docker-registry -g docker-registry -m 0750 ${root}/cache/registry";

    systemd.timers.nixie-fetch = lib.mkIf (cfg.fetch.timer != null) {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.fetch.timer;
        Persistent = true;
      };
    };
  };
}
