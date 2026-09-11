# The option reference, rendered from the same metadata the installer
# serves, so the docs and the wizard cannot disagree.
{ pkgs, nixie-setup }:
pkgs.runCommand "nixie-option-reference" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  mkdir -p $out
  python3 - ${nixie-setup.passthru.optionsJson} >$out/options.md <<'PY'
  import json, sys
  opts = json.load(open(sys.argv[1]))
  print("# Option reference\n")
  print("Generated from the module tree; the installer renders the same descriptions.\n")
  for o in sorted(opts, key=lambda o: o["path"]):
      print(f"## `{o['path']}`\n")
      t = o["type"] + (" (" + ", ".join(o["values"]) + ")" if o["values"] else "")
      d = "required" if o["required"] else "default: `" + json.dumps(o["default"]) + "`"
      print(f"*{t}*, {d}." + (f" Wizard section: {o['section']}." if o["section"] else "") + "\n")
      print(o["description"].strip() + "\n")
  PY
''
