# A NAS as first-class storage (ARCHITECTURE 4.13): NFS shares mounted on
# demand under /nas/<name>, optionally cached on the local disk; the data
# root's directories placed on a share by binding the share's directory over
# them, so every path stays the data root's; dated copies to a share; and a
# watcher that reports each share and, for "hold" shares, stops the guests
# that need it while it is gone.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../lib/option.nix lib) mkOption;
  t = lib.types;
  cfg = config.nixie.nas;
  data = config.nixie.data;
  root = toString data.root;
  on = cfg != { };
  mountOf = n: "/nas/${n}";
  # The data root's directories placed on a share.
  placed = lib.filterAttrs (_: v: v != null) {
    cache = data.cache.on;
    state = data.state.on;
    media = data.media.on;
  };
  # Where a copy lands: "<nas>:<dir>".
  target =
    to:
    let
      parts = lib.splitString ":" to;
    in
    {
      nas = lib.head parts;
      dir = lib.concatStringsSep ":" (lib.tail parts);
    };
  srcOf =
    from:
    if
      lib.elem from [
        "state"
        "media"
      ]
    then
      "${root}/${from}"
    else
      from;
  # A guest needs a share when one of its mounts is on it, directly or
  # through a data directory placed there.
  needs =
    n: g:
    lib.any (
      p:
      lib.hasPrefix "${mountOf n}/" "${p}/"
      || lib.any (d: placed.${d} == n && lib.hasPrefix "${root}/${d}/" "${p}/") (lib.attrNames placed)
    ) (lib.attrNames g.mounts);
  held = lib.mapAttrs (n: _: lib.attrNames (lib.filterAttrs (_: needs n) config.nixie.guests)) (
    lib.filterAttrs (_: s: s.whenDown == "hold") cfg
  );
  settings = pkgs.writeText "nixie-nas.json" (
    builtins.toJSON (
      lib.mapAttrs (n: s: {
        mount = mountOf n;
        inherit (s) server export whenDown;
        guests = held.${n} or [ ];
        binds = map (d: "${root}/${d}") (lib.attrNames (lib.filterAttrs (_: v: v == n) placed));
      }) cfg
    )
  );
  watch = pkgs.writeShellApplication {
    name = "nixie-nas-watch";
    runtimeInputs = [
      pkgs.jq
      pkgs.coreutils
      pkgs.util-linux
      config.systemd.package
      config.virtualisation.incus.package
    ];
    text = builtins.readFile ./nas-watch.sh;
  };
  copy = pkgs.writeShellApplication {
    name = "nixie-nas-copy";
    runtimeInputs = [
      pkgs.rsync
      pkgs.coreutils
      pkgs.findutils
    ];
    text = builtins.readFile ./nas-copy.sh;
  };
  share = t.submodule {
    options = {
      server = mkOption {
        type = t.str;
        example = "nas.lan";
        description = "The NAS's name or address on your network.";
      };
      export = mkOption {
        type = t.str;
        example = "/mnt/tank/nixie";
        description = "The folder the NAS shares over NFS for this machine.";
      };
      version = mkOption {
        type = t.str;
        default = "4.2";
        description = "The NFS version to speak. Most NAS systems offer 4.2 or 4.1.";
      };
      options = mkOption {
        type = t.listOf t.str;
        default = [ ];
        description = "Extra NFS mount options, for anything the NAS needs.";
      };
      cache = mkOption {
        type = t.bool;
        default = false;
        description = ''
          Keep a copy of what is read from this share on the local disk, so
          large files -- models, images -- load at disk speed the second time.
          Uses some of the local disk; the NAS stays the real copy.
        '';
      };
      whenDown = mkOption {
        type = t.enum [
          "degrade"
          "hold"
        ];
        default = "degrade";
        description = ''
          What happens while the NAS cannot be reached. "degrade": everything
          starts and keeps running; what reads from the share waits or fails,
          and the notices say the NAS is down. "hold": guests that use
          something on this share are stopped until it is back, then started
          again.
        '';
      };
    };
  };
  placement =
    what:
    mkOption {
      type = t.nullOr t.str;
      default = null;
      example = "tank";
      description =
        "Keep the data root's ${what}/ on this NAS share (a name from nixie.nas) instead of the local disk."
        +
          lib.optionalString (what == "state")
            " state/ is what cannot be fetched again: it is then only as available and as fast as the NAS, so back it up."
        + lib.optionalString (what == "cache") " Turn on the share's cache to keep reads fast.";
    };
in
{
  options.nixie.nas = mkOption {
    type = t.attrsOf share;
    default = { };
    example = lib.literalExpression ''{ tank = { server = "nas.lan"; export = "/mnt/tank/nixie"; cache = true; }; }'';
    description = ''
      NAS shares this machine uses, over NFS, each mounted at /nas/<name>
      when first used. Put the data root's directories, copies and backups
      on them with the options that name a share.
    '';
  };
  options.nixie.data = {
    cache.on = placement "cache";
    state.on = placement "state";
    media.on = placement "media";
    copies = mkOption {
      type = t.attrsOf (
        t.submodule {
          options = {
            from = mkOption {
              type = t.str;
              example = "state";
              description = "What to copy: \"state\", \"media\", or a path.";
            };
            to = mkOption {
              type = t.strMatching "^[A-Za-z0-9_-]+:.*$";
              example = "tank:copies/state";
              description = "Where, as <nas>:<folder on it>.";
            };
            schedule = mkOption {
              type = t.str;
              default = "daily";
              description = "When, as a systemd calendar expression.";
            };
            keep = mkOption {
              type = t.ints.positive;
              default = 7;
              description = "How many dated copies to keep; unchanged files are shared between them.";
            };
          };
        }
      );
      default = { };
      description = "Dated copies of local data on a NAS share, besides backups.";
    };
  };

  config = lib.mkMerge [
    {
      assertions =
        lib.mapAttrsToList (d: n: {
          assertion = cfg ? ${n};
          message = "nixie.data.${d}.on names \"${n}\", which is not in nixie.nas";
        }) placed
        ++ lib.mapAttrsToList (c: v: {
          assertion = cfg ? ${(target v.to).nas};
          message = "nixie.data.copies.${c}.to names \"${(target v.to).nas}\", which is not in nixie.nas";
        }) data.copies
        # While the share is gone, whatever writes to state/ would write to
        # the local folder under it, and that would vanish when the share
        # came back: the guests that use it must stop instead.
        ++ lib.optional (data.state.on != null) {
          assertion = cfg ? ${data.state.on} && cfg.${data.state.on}.whenDown == "hold";
          message = "nixie.data.state.on = \"${data.state.on}\" needs nixie.nas.${data.state.on}.whenDown = \"hold\", so nothing writes state/ while the NAS is gone";
        };
      warnings = lib.optional (data.state.on != null) ''
        nixie.data.state.on puts state/ on the NAS "${data.state.on}": the
        guests' irreplaceable data is then only as available and as fast as
        the NAS. Keep backups of it.
      '';
    }
    (lib.mkIf on {
      boot.supportedFilesystems = [ "nfs" ];
      services.cachefilesd.enable = lib.any (s: s.cache) (lib.attrValues cfg);
      environment.etc."nixie/nas.json".source = settings;
      fileSystems =
        lib.mapAttrs' (
          n: s:
          lib.nameValuePair (mountOf n) {
            device = "${s.server}:${s.export}";
            fsType = "nfs";
            # Mounted when first used and never in the way of booting: a NAS
            # that is down must not stop the machine starting.
            options = [
              "nfsvers=${s.version}"
              "noauto"
              "x-systemd.automount"
              "x-systemd.idle-timeout=600"
              "x-systemd.mount-timeout=30"
              "_netdev"
              "nofail"
            ]
            ++ lib.optional s.cache "fsc"
            ++ s.options;
          }
        ) cfg
        // lib.mapAttrs' (
          d: n:
          lib.nameValuePair "${root}/${d}" {
            device = "${mountOf n}/${d}";
            fsType = "none";
            options = [
              "bind"
              "nofail"
              "_netdev"
              "x-systemd.requires=nixie-nas-dirs-${n}.service"
              "x-systemd.after=nixie-nas-dirs-${n}.service"
            ];
          }
        ) placed;
      systemd.services =
        lib.mapAttrs' (
          n: _:
          lib.nameValuePair "nixie-nas-dirs-${n}" {
            description = "Folders on NAS share ${n}";
            unitConfig.RequiresMountsFor = [ (mountOf n) ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              # exposure: root, to create folders on the share for the data root.
              ExecStart = "${pkgs.coreutils}/bin/mkdir -p ${
                lib.concatMapStringsSep " " (d: "${mountOf n}/${d}") (
                  lib.attrNames (lib.filterAttrs (_: v: v == n) placed)
                )
              } ${mountOf n}/.nixie";
            };
          }
        ) cfg
        // lib.mapAttrs' (
          c: v:
          lib.nameValuePair "nixie-copy-${c}" {
            description = "Dated copy ${c} of ${v.from} to ${v.to}";
            unitConfig.RequiresMountsFor = [ (mountOf (target v.to).nas) ];
            environment = {
              NIXIE_COPY_FROM = srcOf v.from;
              NIXIE_COPY_TO = "${mountOf (target v.to).nas}/${(target v.to).dir}";
              NIXIE_COPY_KEEP = toString v.keep;
            };
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${copy}/bin/nixie-nas-copy";
              # exposure: root, to read every file of the data it copies.
              Nice = 10;
              IOSchedulingClass = "idle";
            };
          }
        ) data.copies
        // {
          nixie-nas-watch = {
            description = "Check the NAS shares";
            environment.NIXIE_NAS = "${settings}";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${watch}/bin/nixie-nas-watch";
              # exposure: root, to stop and start guests that need a share.
            };
          };
        };
      systemd.timers =
        lib.mapAttrs' (
          c: v:
          lib.nameValuePair "nixie-copy-${c}" {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = v.schedule;
              Persistent = true;
            };
          }
        ) data.copies
        // {
          nixie-nas-watch = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = "1min";
              OnUnitActiveSec = "1min";
            };
          };
        };
    })
  ];
}
