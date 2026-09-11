{
  imports = [
    ./encryption.nix
    ./tpm.nix
    ./secure-boot.nix
    ./attestation.nix
    ./duress.nix
    ./remote-unlock.nix
    ./lockdown.nix
    ./hardening.nix
  ];
}
