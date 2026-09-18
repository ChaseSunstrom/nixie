# The installer backend and everything it runs: the phase scripts, the
# wizard bundle, the option metadata rendered from the module tree, and the
# finish script.
{
  pkgs,
  inputs,
  self,
}:
let
  inherit (pkgs) lib;
  web = import ./nixie-web.nix { inherit pkgs; };
  installer = import ./nixie-installer.nix { inherit pkgs; };
  # Option metadata comes from a throwaway evaluation of the module tree; the
  # values are never read, only the declarations.
  probe = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      self.nixosModules.nixie
      {
        nixie.profile = "server";
        nixie.host.name = "probe";
        nixie.auth.admin.name = "admin";
        nixie.auth.admin.passwordFile = "/dev/null";
        nixie.disks.system = "/dev/null";
        networking.hostId = "00000000";
      }
    ];
  };
  optionsJson = pkgs.writeText "options.json" (
    (import ../lib/options-json.nix { inherit lib; }) probe.options
  );
  # The same rendering, asked for at run time against a site that exists, so
  # options a site's own modules declare reach the wizard too.
  siteOptions = pkgs.writeText "site-options.nix" (
    (import ../lib/template.nix lib).fill ../installer/site-options.nix.in {
      lib = "${inputs.nixpkgs}/lib";
      nixieLib = ../lib;
    }
  );
  # Both run `nixie apply` from the host's own PATH: the host's CLI is built
  # for its profile, and bundling the full one would put OpenTofu and the
  # Incus client in a desktop's setup generation.
  finish = pkgs.writeShellApplication {
    name = "nixie-finish";
    runtimeInputs = [
      pkgs.git
      pkgs.jq
      pkgs.nix
      pkgs.systemd
    ];
    text = ''
      export PATH="$PATH:${installer}/bin"
      exec ${installer}/libexec/nixie/finish.sh "$@"
    '';
  };
in
pkgs.writeShellApplication {
  name = "nixie-setup";
  runtimeInputs = [
    pkgs.python3
    pkgs.efibootmgr
    pkgs.openssl
    pkgs.qrencode
    pkgs.iproute2
    # The wizard's drive picker: lsblk to list them, findmnt and mount to use one.
    pkgs.util-linux
    pkgs.git
    pkgs.nix
    pkgs.systemd
    installer
    finish
  ];
  text = ''
    exec python3 ${./nixie-setup/nixie-setup.py} \
      --platform "path:${self}" \
      --static ${web.nixie-setup-web} \
      --options ${optionsJson} \
      --site-options ${siteOptions} \
      --template ${../templates/site} \
      "$@"
  '';
  passthru = {
    inherit optionsJson siteOptions finish;
  };
}
