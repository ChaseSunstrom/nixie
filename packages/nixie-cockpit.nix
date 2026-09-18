# The host page's History screen: host generations, guest and data snapshots
# and restic backups, with the action for each. A Cockpit package, not a host
# agent: it asks the `nixie` command for JSON through the Cockpit bridge, so
# there is nothing new listening and nothing new to authenticate.
{
  pkgs,
  lib ? pkgs.lib,
  # The site's finish, as the rest of the host page wears it.
  finish ? "graphite",
}:
let
  t = (import ../lib/tokens.nix { inherit lib; }).forFinish finish;
  manifest = builtins.toJSON {
    version = 0;
    requires.cockpit = "266";
    menu.index = {
      label = "History";
      order = 30;
      docs = [
        {
          label = "What can be rolled back";
          url = "https://github.com/OWNER/nixie/blob/master/docs/guides/restore.md";
        }
      ];
    };
  };
  # The page itself is packages/nixie-cockpit/index.html, in the finish.
  page = pkgs.writeText "nixie-history.html" (
    (import ../lib/template.nix lib).fill ./nixie-cockpit/index.html (
      (import ../lib/tokens.nix { inherit lib; }).marks t
    )
  );
in
pkgs.runCommand "nixie-cockpit" { meta.priority = 4; } ''
  d=$out/share/cockpit/nixie-history
  mkdir -p "$d"
  cat >"$d/manifest.json" <<'JSON'
  ${manifest}
  JSON
  cp ${page} "$d/index.html"
  cp ${./nixie-cockpit/history.js} "$d/history.js"
''
