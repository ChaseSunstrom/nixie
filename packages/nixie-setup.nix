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
  cli = import ./nixie-cli.nix { inherit pkgs; };
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
  finish = pkgs.writeShellApplication {
    name = "nixie-finish";
    runtimeInputs = [
      cli
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
    pkgs.openssl
    pkgs.qrencode
    pkgs.iproute2
    pkgs.git
    pkgs.nix
    pkgs.systemd
    installer
    finish
  ];
  text = ''
    exec python3 ${./nixie-setup/nixie-setup.py} \
      --static ${web.nixie-setup-web} \
      --options ${optionsJson} \
      --template ${../templates/site} \
      "$@"
  '';
  passthru = {
    inherit optionsJson finish;
  };
}
