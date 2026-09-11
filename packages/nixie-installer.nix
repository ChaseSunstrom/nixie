# The phase engine: `nixie-phase N [args]` runs installer/phases/0N-*.sh with
# every tool it needs on PATH, and `nixie-discover` prints hardware facts.
{ pkgs }:
let
  tools = with pkgs; [
    age
    coreutils
    cryptsetup
    dosfstools
    e2fsprogs
    gnutar
    gptfdisk
    iproute2
    jq
    mkpasswd
    nixos-install-tools
    openssh
    openssl
    parted
    pciutils
    sops
    systemd
    tpm2-tools
    tpm2-totp
    util-linux
    zfs
  ];
  phases = pkgs.runCommand "nixie-phases" { } ''
    mkdir -p $out/libexec/nixie/phases
    cp ${../installer/lib.sh} $out/libexec/nixie/lib.sh
    cp ${../installer/finish.sh} $out/libexec/nixie/finish.sh
    cp ${../installer/phases}/*.sh $out/libexec/nixie/phases/
    chmod +x $out/libexec/nixie/phases/*.sh $out/libexec/nixie/finish.sh
  '';
in
pkgs.symlinkJoin {
  name = "nixie-installer";
  paths = [
    (pkgs.writeShellApplication {
      name = "nixie-phase";
      runtimeInputs = tools;
      text = ''
        n=''${1:?phase number}; shift
        script=$(ls ${phases}/libexec/nixie/phases/0"$n"-*.sh)
        exec "$script" "$@"
      '';
    })
    (pkgs.writeShellApplication {
      name = "nixie-discover";
      runtimeInputs = tools;
      text = builtins.readFile ../installer/discover.sh;
    })
    phases
  ];
}
