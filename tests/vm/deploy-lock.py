# The lock file a site would get from `nix flake lock` on a machine with a
# network, written from the platform's own instead.
#
# Locking is the first thing an evaluation does, and it resolves the
# platform's inputs -- `github:` every one. A machine with no way out cannot
# do that, and having the trees in its store does not help by itself: what
# nix looks up is the reference. A locked node carries a hash, and a hash is
# something nix can find in a store it already has.
import json
import sys

platform, narhash, out = sys.argv[1:4]
lock = json.load(open(platform + "/flake.lock"))
nodes, root = lock["nodes"], lock["root"]

# A follows path is read from the root down, and the root is about to be one
# step further away.
for node in nodes.values():
    node["inputs"] = {
        k: (["nixie"] + v if isinstance(v, list) else v) for k, v in node.get("inputs", {}).items()
    }

nodes["nixie"] = dict(
    nodes.pop(root),
    locked={"type": "path", "path": platform, "narHash": narhash, "lastModified": 1},
    original={"type": "path", "path": platform},
)
nodes["root"] = {"inputs": {"nixie": "nixie"}}
json.dump({"nodes": nodes, "root": "root", "version": lock["version"]}, open(out, "w"), indent=2)
