# site.nix -> flake outputs. A site is data; this is the only wiring.
{ inputs, self }:
let
  inherit (inputs.nixpkgs) lib;
  system = "x86_64-linux";

  # Secrets are read from the site checkout on the host at activation, never
  # from the store, so the path inside the site becomes the same path under
  # nixie.site.path.
  secretsModule =
    siteDir: host:
    { config, ... }:
    {
      nixie.secrets.file =
        if host ? secrets then
          "${config.nixie.site.path}/${lib.removePrefix (toString siteDir + "/") (toString host.secrets)}"
        else
          null;
    };

  # Unfree packages a host may need: the NVIDIA driver, and desktop packages
  # the site names (a name chosen is a licence chosen: Steam, Discord, VS
  # Code). The decision is made from the site's files before evaluation so
  # hosts without either never define nixpkgs.config at all (tests hand in a
  # read-only package set).
  hardwareFacts =
    host:
    let
      h = if lib.isAttrs host.hardware then host.hardware else import host.hardware;
    in
    if lib.isAttrs h then h else { };
  unfreeModule =
    host:
    let
      nvidia = (hardwareFacts host).nixie.hardware.gpu or "none" == "nvidia";
      categories =
        if lib.isAttrs host.settings then host.settings.nixie.desktop.packages.categories or { } else { };
      chosen = map (n: lib.last (lib.splitString "." n)) (lib.concatLists (lib.attrValues categories));
    in
    lib.optional (nvidia || chosen != [ ]) {
      nixpkgs.config.allowUnfreePredicate =
        pkg:
        let
          name = lib.getName pkg;
        in
        (nvidia && (lib.hasPrefix "nvidia-x11" name || lib.hasPrefix "nvidia-settings" name))
        # The dash admits the pieces a package is built from (steam-unwrapped).
        || lib.any (n: name == n || lib.hasPrefix "${n}-" name) chosen;
    };

  hostModules =
    siteDir: name: host:
    hostModulesRev null siteDir name host;
  hostModulesRev =
    rev: siteDir: name: host:
    unfreeModule host
    # `nixie usb allow` writes this file; a host without one has no extra devices.
    ++ lib.optional (builtins.pathExists (siteDir + "/hosts/${name}/usb.nix")) (
      siteDir + "/hosts/${name}/usb.nix"
    )
    ++ [
      self.nixosModules.nixie
      host.hardware
      host.settings
      (secretsModule siteDir host)
      {
        nixie.host.name = lib.mkDefault name;
        nixie.host.siteRevision = rev;
        nixie.guests = host.guests or { };
        nixie.data.manifest = host.data or { };
      }
    ];

  mkHost =
    rev: siteInputs: siteDir: name: host:
    lib.nixosSystem {
      inherit system;
      specialArgs = {
        # The site's own inputs reach its modules as well (configuration.nix
        # can use `inputs.<name>`); the platform's win a clash, so a site
        # cannot swap nixpkgs or the platform modules from under them.
        inputs = removeAttrs siteInputs [ "self" ] // inputs;
      };
      modules =
        hostModulesRev rev siteDir name host
        # HyDE comes from the site's hydenix input, never the platform's (D27).
        ++ lib.optional (siteInputs ? hydenix) ../modules/desktop/hyde.nix;
    };

  # `mkSite ./site.nix`, or `mkSite { site = ./site.nix; rev = self.shortRev or null; inherit inputs; }`
  # so generations carry the site commit (pure evaluation cannot read .git)
  # and the site's inputs, hydenix among them, reach its hosts.
  mkSite =
    arg:
    let
      sitePath = if lib.isAttrs arg then arg.site else arg;
      rev = if lib.isAttrs arg then (arg.rev or null) else null;
      siteInputs = if lib.isAttrs arg then (arg.inputs or { }) else { };
      site = import sitePath;
      hosts = lib.mapAttrs (mkHost rev siteInputs (dirOf sitePath)) site.hosts;
    in
    {
      nixosConfigurations = hosts;
      packages.${system} =
        lib.mapAttrs' (n: h: lib.nameValuePair "${n}-vm" h.config.system.build.vm) hosts
        // lib.mapAttrs' (
          n: h: lib.nameValuePair "${n}-tofu" h.config.environment.etc."nixie/tofu/config.tf.json".source
        ) (lib.filterAttrs (_: h: h.config.nixie.incus.enable) hosts)
        // lib.concatMapAttrs (
          n: h:
          lib.mapAttrs' (
            g: img: lib.nameValuePair "${n}-guest-${g}" img.package
          ) h.config.nixie.build.guestImages
        ) hosts;
      checks.${system} = lib.mapAttrs' (
        n: h: lib.nameValuePair "${n}-eval" h.config.system.build.toplevel
      ) hosts;
    };
in
{
  inherit mkSite hostModules;
}
