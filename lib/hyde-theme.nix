# Read a HyDE theme directory as data and hand back a Nixie finish: the
# colours come from the theme's kitty file (the one place every HyDE theme
# states its palette in plain hex), the wallpapers from its own folder.
# Nothing in the theme is executed, fetched or sourced; a theme is a pinned
# directory in the store like any other input.
{ lib }:
let
  digits = lib.listToAttrs (
    lib.imap0 (i: c: lib.nameValuePair c i) (lib.stringToCharacters "0123456789abcdef")
  );
  byte =
    s:
    16 * digits.${lib.toLower (builtins.substring 0 1 s)}
    + digits.${lib.toLower (builtins.substring 1 1 s)};
  channels =
    hex:
    map (o: byte (builtins.substring o 2 hex)) [
      1
      3
      5
    ];
  # Rough perceived brightness, enough to decide dark from light.
  bright =
    hex:
    let
      c = channels hex;
    in
    (299 * lib.elemAt c 0 + 587 * lib.elemAt c 1 + 114 * lib.elemAt c 2) / 1000;

  hexDigits = "0123456789abcdef";
  toHex =
    n:
    let
      i =
        if n < 0 then
          0
        else if n > 255 then
          255
        else
          n;
    in
    builtins.substring (i / 16) 1 hexDigits + builtins.substring (lib.mod i 16) 1 hexDigits;
  # mix a b p: p percent of b into a.
  mix =
    a: b: p:
    let
      ca = channels a;
      cb = channels b;
      m = i: (lib.elemAt ca i * (100 - p) + lib.elemAt cb i * p) / 100;
    in
    "#" + toHex (m 0) + toHex (m 1) + toHex (m 2);

  read =
    dir: file:
    let
      p = dir + "/${file}";
    in
    if builtins.pathExists p then builtins.readFile p else "";
  # "background   #1E1E2E" -> "#1e1e2e"
  lookup =
    text: key:
    let
      hit = lib.findFirst (m: m != null) null (
        map (l: builtins.match "^[[:space:]]*${key}[[:space:]]+#?([0-9a-fA-F]{6}).*" l) (
          lib.splitString "\n" text
        )
      );
    in
    if hit == null then null else "#" + lib.toLower (builtins.head hit);
in
dir:
let
  kitty = read dir "kitty.theme";
  pick =
    key: fallback:
    let
      v = lookup kitty key;
    in
    if v == null then fallback else v;
  bg = pick "background" "#1f2226";
  ink = pick "foreground" "#eceae5";
  accent = pick "cursor" (pick "color4" "#7ebae4");
in
{
  wallpapers = dir + "/wallpapers";
  dark = bright bg < 128;
  colors = {
    inherit bg ink;
    s1 = mix bg ink 7;
    s2 = mix bg ink 3;
    s3 = mix bg ink 14;
    line = mix bg ink 18;
    line2 = mix bg ink 30;
    muted = mix ink bg 45;
    brand = pick "active_border_color" (pick "color4" "#5277c3");
    brand2 = accent;
    cpu = pick "color4" "#7ebae4";
    mem = pick "color5" "#c4a8f0";
    net = pick "color6" "#7ccfd8";
    disk = pick "color3" "#e0a878";
    ok = pick "color2" "#8fd6a8";
    ice = pick "color14" "#c8dcea";
    err = pick "color1" "#f08a86";
    hot = pick "color3" "#f0b870";
  };
}
