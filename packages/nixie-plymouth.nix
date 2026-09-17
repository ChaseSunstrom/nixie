# The boot splash in the host's finish: the mark and wordmark centred with a
# progress bar under them, messages below, the disk passphrase asked in a
# field drawn like the installer's, and the attestation code under that. A Plymouth script theme, so nothing beyond
# the plugins NixOS ships.
{
  pkgs,
  lib ? pkgs.lib,
  # The finish's colours (lib/tokens.nix forFinish, or a desktop's own).
  t ? (import ../lib/tokens.nix { inherit lib; }).forFinish "graphite",
}:
let
  mark = import ../lib/mark.nix t;
  # Plymouth scripts take colours as three numbers from 0 to 1.
  part =
    hex: i: toString (lib.fromHexString (builtins.substring i 2 (lib.removePrefix "#" hex)) / 255.0);
  rgb = hex: "${part hex 0}, ${part hex 2}, ${part hex 4}";
  colour =
    name: hex: "${name}.r = ${part hex 0}; ${name}.g = ${part hex 2}; ${name}.b = ${part hex 4};";
  script = ''
    Window.SetBackgroundTopColor(${rgb t.bg});
    Window.SetBackgroundBottomColor(${rgb t.bg});
    cx = Window.GetX() + Window.GetWidth() / 2;
    cy = Window.GetY() + Window.GetHeight() / 2;

    # The mark, the wordmark and the bar are one group about the middle of
    # the screen; the passphrase field opens below it.
    logo.image = Image("mark.png");
    logo.sprite = Sprite(logo.image);
    logo.sprite.SetPosition(cx - logo.image.GetWidth() / 2, cy - 150, 1);
    word.image = Image.Text("nixie", ${rgb t.ink}, 1, "Archivo 30");
    word.sprite = Sprite(word.image);
    word.sprite.SetPosition(cx - word.image.GetWidth() / 2, cy + 40, 1);

    # An indeterminate bar: the machine cannot say how far along it is, but a
    # still logo looks like a machine that has stopped.
    track.image = Image("track.png");
    track.sprite = Sprite(track.image);
    trackX = cx - track.image.GetWidth() / 2;
    track.sprite.SetPosition(trackX, cy + 104, 1);
    fill.image = Image("fill.png");
    fill.sprite = Sprite(fill.image);
    span = track.image.GetWidth() - fill.image.GetWidth();
    pos = 0;
    dir = 1;
    fun refresh() {
      pos = pos + dir * 0.012;
      if (pos > 1) { pos = 1; dir = -1; }
      if (pos < 0) { pos = 0; dir = 1; }
      fill.sprite.SetPosition(trackX + pos * span, cy + 104, 2);
    }
    Plymouth.SetRefreshFunction(refresh);

    field.image = Image("field.png");
    field.sprite = Sprite(field.image);
    field.sprite.SetPosition(cx - field.image.GetWidth() / 2, cy + 166, 2);
    field.sprite.SetOpacity(0);
    prompt.sprite = Sprite();
    dots.sprite = Sprite();
    note.sprite = Sprite();

    fun centred(sprite, image, y) {
      sprite.SetImage(image);
      sprite.SetPosition(cx - image.GetWidth() / 2, y, 3);
      sprite.SetOpacity(1);
    }

    fun bar(shown) {
      track.sprite.SetOpacity(shown);
      fill.sprite.SetOpacity(shown);
    }

    # The unlock agent (modules/security/unlock.nix) and the attestation
    # service talk to the theme through status updates starting "nixie-";
    # messages, systemd's included, are shown as they come.
    label = "";
    fun password(text, bullets) {
      # Nothing is progressing while a person types: the bar would be a lie.
      bar(0);
      if (label != "") text = label;
      centred(prompt.sprite, Image.Text(text, ${rgb t.muted}, 1, "Archivo 13"), cy + 136);
      field.sprite.SetOpacity(1);
      shown = " ";
      for (i = 0; i < bullets && i < 32; i++)
        shown = shown + "•";
      centred(dots.sprite, Image.Text(shown, ${rgb t.ink}, 1, "Archivo 18"), cy + 176);
    }
    Plymouth.SetDisplayPasswordFunction(password);

    fun normal() {
      field.sprite.SetOpacity(0);
      prompt.sprite.SetOpacity(0);
      dots.sprite.SetOpacity(0);
      bar(1);
    }
    Plymouth.SetDisplayNormalFunction(normal);

    fun line(sprite, text, colour, font, y) {
      if (text == "") {
        sprite.SetOpacity(0);
      } else {
        centred(sprite, Image.Text(text, colour.r, colour.g, colour.b, 1, font), y);
      }
    }
    ${colour "muted" t.muted}
    ${colour "ink" t.ink}
    ${colour "err" t.err}

    # The attestation code, large, under everything else, so it stays in
    # view while the PIN and passphrase are typed; or why there is none.
    caption.sprite = Sprite();
    digits.sprite = Sprite();
    shownCode = "";
    fun code(message, number) {
      shownCode = message;
      line(caption.sprite, "Attestation code", muted, "Archivo 12", cy + 280);
      line(digits.sprite, number.SubString(0, 3) + " " + number.SubString(3, 6), ink, "Archivo 34", cy + 300);
    }
    fun warn(message) {
      shownCode = message;
      line(caption.sprite, "", muted, "Archivo 12", 0);
      line(digits.sprite, message, err, "Archivo 13", cy + 290);
    }
    fun noCode() {
      shownCode = "";
      line(caption.sprite, "", muted, "Archivo 12", 0);
      line(digits.sprite, "", ink, "Archivo 34", 0);
    }

    shownNote = "";
    fun setNote(text) {
      shownNote = text;
      line(note.sprite, text, muted, "Archivo 13", cy + 240);
    }

    fun status(text) {
      if (text.SubString(0, 13) == "nixie-prompt:") label = text.SubString(13, 400);
      else if (text == "nixie-idle") normal();
    }
    Plymouth.SetUpdateStatusFunction(status);

    fun message(text) {
      if (text.SubString(0, 17) == "Attestation code ") code(text, text.SubString(17, 23));
      else if (text.SubString(0, 18) == "ATTESTATION FAILED") warn(text);
      else if (text.SubString(0, 19) == "No attestation code") warn(text);
      else setNote(text);
    }
    Plymouth.SetMessageFunction(message);

    fun hide(text) {
      if (text == shownCode) noCode();
      else if (text == shownNote) setNote("");
    }
    Plymouth.SetHideMessageFunction(hide);
  '';
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
