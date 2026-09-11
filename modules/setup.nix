# The setup generation: a specialisation that carries the on-screen wizard
# through the phases that run after first boot, then removes itself.
{ lib, ... }:
let
  inherit (import ../lib/option.nix lib) mkOption;
in
{
  options.nixie.setup.pending = mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Internal: true from first boot until the wizard's Finish step. While
      true the system carries an extra boot entry with the on-screen wizard.
    '';
  };
}
