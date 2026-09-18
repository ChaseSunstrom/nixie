# `nixie`: the everyday command. Subcommands arrive with their slices.
# guests = false builds it without the Incus client and OpenTofu, for hosts
# that run no guests (a desktop, unless it enables Incus).
{
  pkgs,
  guests ? true,
}:
let
  template = import ../lib/template.nix pkgs.lib;
in
pkgs.writeShellApplication {
  name = "nixie";
  runtimeInputs =
    with pkgs;
    [
      coreutils
      cryptsetup
      git
      # Three commands parse a tool's columns with it; without it here they
      # depend on whatever PATH the caller happened to have.
      gawk
      gnugrep
      openssl # the Secure Boot check reads the firmware's own key
      gnused
      rsync
      zfs
      jq
      nix # nix-env for generations; a transient unit's PATH has no system profile
      openssh # the site's remote, and its key
      nixos-rebuild
      systemd
      tpm2-tools
      tpm2-totp
      usbguard
      qrencode
      gptfdisk
      iproute2
      pciutils
      util-linux
      yq-go
      # `security reenroll` runs the same phase scripts setup ran.
      (import ./nixie-installer.nix { inherit pkgs; })
    ]
    ++ lib.optionals guests [
      incus-lts.client
      (opentofu.withPlugins (p: [ p.lxc_incus ]))
    ];
  # The command itself is packages/nixie-cli/nixie.sh; only what Nix knows
  # is substituted in.
  text = template.fill ./nixie-cli/nixie.sh {
    guests = if guests then "1" else "0";
    inherit (pkgs) systemd;
  };
}
