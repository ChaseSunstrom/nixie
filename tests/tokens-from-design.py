# The token set is the design file's, still.
#
# The brief calls design/Nixie Front Panel.html the visual source of truth
# for every web surface, and says the tokens were extracted from it once.
# Once is the problem: nothing since has held them to it, so a colour
# changed here -- or a token the design gained and this did not -- would
# show up as a screen that no longer looks like the file it came from, and
# only a person putting the two side by side would ever notice.
#
# The file carries its own THEMES object, which is what its screens render
# from. That is what this reads, not the swatch cards beside it: those print
# a colour of their own for Paper's s2 (docs/design-tokens.md says which, and
# why the rendered value is the one to take).
import json
import re
import sys

design = open(sys.argv[1], encoding="utf-8", errors="replace").read()
tokens = json.load(open(sys.argv[2]))

# The object lives inside the bundle's own escaping.
text = design.replace("\\u002F", "/").replace("\\n", "\n").replace("&quot;", '"')
start = text.find("const THEMES = {")
assert start > 0, "the design file has no THEMES object; has it been re-exported?"
body = text[start:]

# Carried by every consumer instead of copied: `swatch` is the finish's own
# `bg` again, for a chip in the design's own picker, and `ramp` is a
# gradient built from colours that are already tokens.
DERIVED = {"swatch", "ramp"}

for finish, ours in sorted(tokens.items()):
    found = re.search(rf"\n\s*{finish}: \{{(.*?)\}},?\n", body, re.S)
    assert found, f"the design file has no {finish} finish"
    theirs = dict(re.findall(r"(\w+): '([^']*)'", found.group(1)))
    flag = re.search(r"dark: (true|false)", found.group(1))
    if flag:
        theirs["dark"] = flag.group(1) == "true"

    for name, value in sorted(ours.items()):
        assert name in theirs, f"{finish}.{name} is not in the design file at all"
        assert theirs[name] == value, (
            f"{finish}.{name} is {value!r} here and {theirs[name]!r} in the design file"
        )
    missing = sorted(set(theirs) - set(ours) - DERIVED)
    assert not missing, (
        f"the design file's {finish} has {missing} and this token set does not; "
        "a screen drawn from it would be using a colour the platform cannot name"
    )
    assert theirs["swatch"] == ours["bg"], f"{finish}: the design's swatch is no longer its bg"
    print(f"{finish}: {len(ours)} tokens, every one the design file's")

print(f"{len(tokens)} finishes checked against {sys.argv[1].rsplit('/', 1)[-1]}")
