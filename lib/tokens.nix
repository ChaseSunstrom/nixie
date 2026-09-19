# The design tokens as Nix data, from the same JSON the web bundle uses, so
# the desktop, the greeter and the console draw from one source.
{ lib }:
let
  raw = builtins.fromJSON (builtins.readFile ../ui/src/tokens/tokens.json);
  # oklch() values are fine for browsers; toolkits and terminals want hex.
  # The same colours, quieter: same hue and lightness, chroma pulled in,
  # because a terminal or a GTK theme at the full value is harsh. The
  # tokens-agree check holds each one to its token -- within 25 degrees of
  # hue and 0.12 of lightness, and never more saturated than the design
  # file asked for.
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
  # What the configuration files beside each module ask for: every colour of
  # a finish as `@name@` (the hex), `@rgb_name@` and `@bare_name@`.
  marks =
    c:
    lib.listToAttrs (
      lib.concatMap (
        n:
        [ (lib.nameValuePair n c.${n}) ]
        # Only the plain hex colours have the other two forms; a shadow or a
        # glow is already a whole CSS value.
        ++ lib.optionals (lib.hasPrefix "#" c.${n}) [
          (lib.nameValuePair "rgb_${n}" "rgb(${lib.removePrefix "#" c.${n}})")
          (lib.nameValuePair "bare_${n}" (lib.removePrefix "#" c.${n}))
        ]
      ) (lib.attrNames (lib.filterAttrs (_: lib.isString) c))
    );
}
