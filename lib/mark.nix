# The Segment n mark (docs/design-tokens.md section 5) at twice its 72 unit
# size, centred in a w by h canvas, as ImageMagick draw arguments in a
# finish's colours. The installer image and the boot splash draw it.
t: w: h:
let
  x = n: toString (w / 2 - 72 + 2 * n);
  y = n: toString (h / 2 - 80 + 2 * n);
in
''-fill "${t.brand}" -draw "roundrectangle ${x 10},${y 18} ${x 20},${y 62} 6,6" -draw "roundrectangle ${x 10},${y 18} ${x 62},${y 28} 6,6" -fill "${t.brand2}" -draw "roundrectangle ${x 52},${y 18} ${x 62},${y 62} 6,6"''
