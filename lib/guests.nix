# Pure functions from the guest attrset to every derived artifact. Both the
# host module and the tests use these, so nothing else lists guest names.
{ lib }:
rec {
  # Incus nic device: the host side is veth-<name> so firewall chains, scrape
  # labels and the UI all key on it; the guest side is always "uplink".
  nic = g: bridge: {
    type = "nic";
    nictype = "bridged";
    parent = bridge;
    name = "uplink";
    host_name = "veth-${g.name}";
  };

  mountDevices =
    g:
    lib.mapAttrs' (
      host: guest:
      lib.nameValuePair "mount-${builtins.hashString "md5" host}" {
        type = "disk";
        source = host;
        path = guest;
        shift = "true";
      }
    ) g.mounts;

  devices =
    g: bridge:
    {
      root = {
        type = "disk";
        path = "/";
        pool = "default";
      };
      uplink = nic g bridge;
    }
    // mountDevices g
    // lib.optionalAttrs g.gpu { gpu.type = "gpu"; }
    // g.devices;

  instanceConfig =
    g:
    lib.filterAttrs (_: v: v != null) {
      "security.nesting" = if g.nesting then "true" else null;
      "limits.memory" = g.limits.memory;
      "limits.cpu" = g.limits.cpu;
      "cloud-init.user-data" = if g.cloudInit != null then builtins.readFile g.cloudInit else null;
    }
    // g.extraConfig;

  # One terranix module for a host: provider, one instance per guest.
  terranix = guests: bridge: images: {
    terraform.required_providers.incus = {
      source = "lxc/incus";
      version = "1.1.0";
    };
    provider.incus = { };
    resource.incus_instance = lib.mapAttrs (name: g: {
      inherit name;
      type = if g.kind == "vm" then "virtual-machine" else "container";
      image =
        if g.kind == "nixos" then images.${name}.alias else "${g.image.remote}:${g.image.fingerprint}";
      profiles = [ "default" ] ++ g.profiles;
      config = instanceConfig g;
      device = lib.mapAttrsToList (dname: d: {
        name = dname;
        inherit (d) type;
        properties = builtins.removeAttrs d [ "type" ];
      }) (devices g bridge);
    }) guests;
  };

  backupPaths = guests: lib.concatMap (g: g.backup) (lib.attrValues guests);

  # What the UI and the CLI need to tell declared from scratch.
  declaredJson =
    guests: images:
    builtins.toJSON {
      declared = lib.mapAttrs (name: g: {
        inherit (g)
          kind
          ip
          nesting
          gpu
          mounts
          backup
          expose
          ;
        recipe = g.recipe;
        image =
          if g.kind == "nixos" then images.${name}.alias else "${g.image.remote}:${g.image.fingerprint}";
        imagePath = if g.kind == "nixos" then "${images.${name}.package}" else null;
      }) guests;
    };
}
