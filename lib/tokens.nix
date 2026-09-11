# The design tokens as Nix data, from the same JSON the web bundle uses, so
# the desktop, the greeter and the console draw from one source.
{ lib }:
let
  raw = builtins.fromJSON (builtins.readFile ../ui/src/tokens/tokens.json);
  # oklch() values are fine for browsers; toolkits and terminals want hex.
  # These are the same colours resolved to sRGB.
  hex = {
    graphite = {
      mem = "#c4a8f0";
      net = "#7ccfd8";
      disk = "#e0a878";
      ok = "#8fd6a8";
      ice = "#c8dcea";
      err = "#f08a86";
      hot = "#f0b870";
    };
    umber = {
      mem = "#c4a8f0";
      net = "#7ccfd8";
      disk = "#e0a878";
      ok = "#8fd6a8";
      ice = "#c8dcea";
      err = "#f08a86";
      hot = "#f0b870";
    };
    paper = {
      mem = "#6b4fa8";
      net = "#2f8a94";
      disk = "#a86a3a";
      ok = "#3a9a5c";
      ice = "#6a86a0";
      err = "#c2403c";
      hot = "#b8722e";
    };
  };
in
{
  finishes = lib.attrNames raw;
  # Every token of a finish, colours as hex so any consumer can use them.
  forFinish = f: raw.${f} // hex.${f} // { name = f; };
  # Hex without the hash, for formats that want it bare.
  bare = c: lib.removePrefix "#" c;
}
