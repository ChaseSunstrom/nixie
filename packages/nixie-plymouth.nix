# The boot splash in the host's finish: the mark and wordmark, messages
# under them, and the disk passphrase asked in a field drawn like the
# installer's. A Plymouth script theme, so nothing beyond the plugins NixOS
# ships.
{
  pkgs,
  lib ? pkgs.lib,
  # The finish's colours (lib/tokens.nix forFinish, or a desktop's own).
  t ? (import ../lib/tokens.nix { inherit lib; }).forFinish "graphite",
}:
let
  mark = import ../lib/mark.nix t;
  # Plymouth scripts take colours as three numbers from 0 to 1.
  rgb =
    hex:
    let
      h = lib.removePrefix "#" hex;
      c = i: toString (lib.fromHexString (builtins.substring i 2 h) / 255.0);
    in
    "${c 0}, ${c 2}, ${c 4}";
  script = ''
    Window.SetBackgroundTopColor(${rgb t.bg});
    Window.SetBackgroundBottomColor(${rgb t.bg});
    cx = Window.GetX() + Window.GetWidth() / 2;
    cy = Window.GetY() + Window.GetHeight() / 2;

    logo.image = Image("mark.png");
    logo.sprite = Sprite(logo.image);
    logo.sprite.SetPosition(cx - logo.image.GetWidth() / 2, cy - 190, 1);
    word.image = Image.Text("nixie", ${rgb t.ink}, 1, "Archivo 30");
    word.sprite = Sprite(word.image);
    word.sprite.SetPosition(cx - word.image.GetWidth() / 2, cy - 6, 1);

    field.image = Image("field.png");
    field.sprite = Sprite(field.image);
    field.sprite.SetPosition(cx - field.image.GetWidth() / 2, cy + 96, 2);
    field.sprite.SetOpacity(0);
    prompt.sprite = Sprite();
    dots.sprite = Sprite();
    note.sprite = Sprite();

    fun centred(sprite, image, y) {
      sprite.SetImage(image);
      sprite.SetPosition(cx - image.GetWidth() / 2, y, 3);
      sprite.SetOpacity(1);
    }

    fun password(text, bullets) {
      centred(prompt.sprite, Image.Text(text, ${rgb t.muted}, 1, "Archivo 13"), cy + 66);
      field.sprite.SetOpacity(1);
      shown = " ";
      for (i = 0; i < bullets && i < 32; i++)
        shown = shown + "•";
      centred(dots.sprite, Image.Text(shown, ${rgb t.ink}, 1, "Archivo 18"), cy + 106);
    }
    Plymouth.SetDisplayPasswordFunction(password);

    fun normal() {
      field.sprite.SetOpacity(0);
      prompt.sprite.SetOpacity(0);
      dots.sprite.SetOpacity(0);
    }
    Plymouth.SetDisplayNormalFunction(normal);

    fun message(text) {
      centred(note.sprite, Image.Text(text, ${rgb t.muted}, 1, "Archivo 12"), cy + 170);
    }
    Plymouth.SetMessageFunction(message);
  '';
in
pkgs.runCommand "nixie-plymouth" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
  d=$out/share/plymouth/themes/nixie
  mkdir -p $d && cd $d
  magick -size 200x180 xc:none ${mark 200 180} PNG32:mark.png
  magick -size 420x48 xc:none -fill "${t.s2}" -stroke "${t.line}" -strokewidth 1 \
    -draw "roundrectangle 0.5,0.5 419.5,47.5 8,8" PNG32:field.png
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
