# One token set, in two forms that must stay the same colours.
#
# The design file gave the tokens once, and the web bundle uses them as
# written -- `oklch()` for the seven that carry meaning (ok, err, hot, and
# the four meters). A toolkit, a terminal, a Plymouth theme and a GRUB theme
# cannot read oklch, so lib/tokens.nix carries a hex beside each one, toned
# down because a terminal at full chroma is harsh. Nothing held those two to
# each other: a token added to the JSON with no hex draws nothing on the
# desktop, and a hex typed wrong is a colour from another palette with no
# sign that anything is amiss.
#
# So: same finishes, same tokens, and each hex the same colour as its token
# -- same hue, near enough the same lightness, and never louder than the
# design file asked for.
import json
import math
import sys

HUE = 25.0  # degrees; the worst today is 16.8
LIGHT = 0.12  # the worst today is 0.085
LOUDER = 0.005  # the hex is a toned-down copy, never a more saturated one


def to_oklch(hexcolour):
    r, g, b = (int(hexcolour[i:i + 2], 16) / 255 for i in (1, 3, 5))

    def straighten(u):
        return ((u + 0.055) / 1.055) ** 2.4 if u > 0.04045 else u / 12.92

    r, g, b = straighten(r), straighten(g), straighten(b)
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return lightness, math.hypot(a, bb), math.degrees(math.atan2(bb, a)) % 360


written = json.load(open(sys.argv[1]))  # ui/src/tokens/tokens.json
resolved = json.load(open(sys.argv[2]))  # lib/tokens.nix, per finish

assert set(written) == set(resolved), f"finishes differ: {sorted(written)} against {sorted(resolved)}"

worst_hue = worst_light = 0.0
checked = 0
for finish, tokens in sorted(written.items()):
    for name, value in sorted(tokens.items()):
        if not str(value).startswith("oklch("):
            # Anything already a hex, a shadow or a glow is carried across
            # unchanged, and that is the same string on both sides.
            assert resolved[finish][name] == value, f"{finish}.{name}: {resolved[finish][name]} is not {value}"
            continue
        body = str(value)[len("oklch("):-1].replace("%", "").split()
        want = (float(body[0]) / 100, float(body[1]), float(body[2]))
        hexcolour = resolved[finish][name]
        assert isinstance(hexcolour, str) and hexcolour.startswith("#") and len(hexcolour) == 7, (
            f"{finish}.{name} is {value} in the design tokens and {hexcolour!r} beside it; "
            "every oklch token needs a hex a toolkit can read"
        )
        got = to_oklch(hexcolour)
        hue = min(abs(want[2] - got[2]), 360 - abs(want[2] - got[2]))
        light = abs(want[0] - got[0])
        assert hue <= HUE, f"{finish}.{name}: {hexcolour} is {hue:.1f} degrees of hue from {value}"
        assert light <= LIGHT, f"{finish}.{name}: {hexcolour} is {light:.3f} of lightness from {value}"
        assert got[1] <= want[1] + LOUDER, (
            f"{finish}.{name}: {hexcolour} is more saturated ({got[1]:.3f}) than the design token "
            f"({want[1]:.3f}); the hex is the quiet copy, not the loud one"
        )
        worst_hue, worst_light = max(worst_hue, hue), max(worst_light, light)
        checked += 1

print(
    f"{checked} colours in {len(written)} finishes agree: "
    f"worst hue {worst_hue:.1f} of {HUE} degrees, worst lightness {worst_light:.3f} of {LIGHT}"
)
