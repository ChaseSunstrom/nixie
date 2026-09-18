# shellcheck shell=bash
# `nix run .#offline`: the clean-clone criterion, "builds offline after
# `nix flake archive`", as far as it can honestly be taken.
#
# Literally -- a store holding only the archive, building everything with no
# network -- it cannot be met by any flake that uses nixpkgs: `nix flake
# archive` copies the inputs' *sources*, so such a store has to build the
# whole stdenv from scratch, and the bootstrap seed it starts from is itself
# fetched. What the criterion is really about is that nothing reaches the
# network behind the lock file: no input left unpinned, nothing fetched while
# the modules are evaluated. That is what this checks, by archiving and then
# working with the network refused.
set -euo pipefail
flake=${1:-.}
store=${NIXIE_OFFLINE_STORE:-$(mktemp -d -t nixie-offline-XXXXXX)}
keep=${NIXIE_OFFLINE_KEEP:-0}
say() { printf '\n== %s\n' "$1"; }
cleanup() {
  if [ "$keep" = 1 ]; then return 0; fi
  # A store's paths are read-only by design, so the copy has to be made
  # writable before it can be taken away again.
  chmod -R u+w "$store" 2>/dev/null || true
  rm -rf "$store"
}
trap cleanup EXIT

say "archiving $flake and everything it pins"
nix flake archive "$flake" --to "$store" --no-write-lock-file
printf 'every input copied to a store of its own: %s\n' "$store"

# Evaluation is where an unpinned fetch hides: a `builtins.fetchTarball` or a
# `fetchFromGitHub` in a module reaches the network here, and a clean clone on
# a machine behind a firewall would stop at it. With --offline that is an
# error rather than a download.
say "evaluating every output with the network refused"
# The hosts live in a site, not here: `eval-matrix` is the check that builds
# the example site's machines through mkSite, so evaluating it evaluates them.
for out in \
  "checks.x86_64-linux.eval-matrix" \
  "checks.x86_64-linux.no-secrets-in-store" \
  "packages.x86_64-linux.nixie-cli" \
  "packages.x86_64-linux.nixie-iso" \
  "packages.x86_64-linux.nixie-setup" \
  "packages.x86_64-linux.deploy" \
  "packages.x86_64-linux.docs"; do
  printf '   %s\n' "$out"
  nix eval --offline --raw "$flake#$out.drvPath" >/dev/null
done

say "nothing reached the network: every input is pinned, and every module evaluates from what the archive holds"
