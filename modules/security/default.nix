{
  imports = [
    ./encryption.nix
    ./tpm.nix
    ./fido2.nix
    ./secure-boot.nix
    ./attestation.nix
    ./duress.nix
    ./unlock.nix
    ./remote-unlock.nix
    ./lockdown.nix
    ./hardening.nix
  ];
}
