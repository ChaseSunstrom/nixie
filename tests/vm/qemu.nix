# Firmware shape every VM test boots with: UEFI plus an emulated TPM. The test
# framework provides its own disk, so the site's disk layout is declared but
# not applied, and the test-only age key is shared in so secrets decrypt.
{ lib, ... }:
{
  disko.enableConfig = false;
  virtualisation.useEFIBoot = true;
  virtualisation.tpm.enable = true;
  virtualisation.sharedDirectories.nixie-test-keys = {
    source = "${../keys}";
    target = "/run/nixie-test-keys";
  };
  sops.age.keyFile = lib.mkForce "/run/nixie-test-keys/example-host.age";
  sops.age.generateKey = lib.mkForce false;
}
