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

  # The NVIDIA driver is the one unfree package a host may need. The
  # decision is made from the hardware file before evaluation so hosts
  # without it never define nixpkgs.config at all (tests hand in a read-only
  # package set).
  hardwareFacts =
    host:
    let
      h = if lib.isAttrs host.hardware then host.hardware else import host.hardware;
    in
    if lib.isAttrs h then h else { };
  unfreeModule =
    host:
    lib.optional ((hardwareFacts host).nixie.hardware.gpu or "none" == "nvidia") {
      nixpkgs.config.allowUnfreePredicate =
        pkg:
        lib.hasPrefix "nvidia-x11" (lib.getName pkg) || lib.hasPrefix "nvidia-settings" (lib.getName pkg);
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
    rev: siteDir: name: host:
    lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
      };
      modules = hostModulesRev rev siteDir name host;
    };

  # `mkSite ./site.nix`, or `mkSite { site = ./site.nix; rev = self.shortRev or null; }`
  # so generations carry the site commit (pure evaluation cannot read .git).
  mkSite =
    arg:
    let
      sitePath = if lib.isAttrs arg then arg.site else arg;
      rev = if lib.isAttrs arg then (arg.rev or null) else null;
      site = import sitePath;
      hosts = lib.mapAttrs (mkHost rev (dirOf sitePath)) site.hosts;
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
