# The boot splash in the host's finish: the mark and wordmark centred with a
# progress bar under them, messages below, the disk passphrase asked in a
# field drawn like the installer's, and the attestation code under that. A
# Plymouth script theme, so nothing beyond the plugins NixOS ships.
{
  pkgs,
  lib ? pkgs.lib,
  # The finish's colours (lib/tokens.nix forFinish, or a desktop's own).
  t ? (import ../lib/tokens.nix { inherit lib; }).forFinish "graphite",
}:
let
  template = import ../lib/template.nix lib;
  mark = import ../lib/mark.nix t;
  # Plymouth scripts take colours as three numbers from 0 to 1.
  part =
    hex: i: toString (lib.fromHexString (builtins.substring i 2 (lib.removePrefix "#" hex)) / 255.0);
  rgb = hex: "${part hex 0}, ${part hex 2}, ${part hex 4}";
  colour =
    name: hex: "${name}.r = ${part hex 0}; ${name}.g = ${part hex 2}; ${name}.b = ${part hex 4};";
  # The theme itself is packages/nixie-plymouth/nixie.script; the finish's
  # colours are substituted into it.
  script = template.fill ./nixie-plymouth/nixie.script {
    bg = rgb t.bg;
    ink = rgb t.ink;
    muted = rgb t.muted;
    mutedRGB = colour "muted" t.muted;
    inkRGB = colour "ink" t.ink;
    errRGB = colour "err" t.err;
  };
in
pkgs.runCommand "nixie-plymouth" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
  d=$out/share/plymouth/themes/nixie
  mkdir -p $d && cd $d
  magick -size 200x180 xc:none ${mark 200 180} PNG32:mark.png
  magick -size 420x48 xc:none -fill "${t.s2}" -stroke "${t.line}" -strokewidth 1 \
    -draw "roundrectangle 0.5,0.5 419.5,47.5 8,8" PNG32:field.png
  magick -size 260x4 xc:none -fill "${t.line2}" -draw "roundrectangle 0,0 259,3 2,2" PNG32:track.png
  magick -size 84x4 xc:none -fill "${t.brand2}" -draw "roundrectangle 0,0 83,3 2,2" PNG32:fill.png
  cat >nixie.script <<'SCRIPT'
  ${script}
  SCRIPT
  cat >nixie.plymouth <<EOF
  [Plymouth Theme]
  Name=Nixie
  Description=The Nixie finish while the machine starts
  ModuleName=script

  [script]
  ImageDir=$d
  ScriptFile=$d/nixie.script
  EOF
''
