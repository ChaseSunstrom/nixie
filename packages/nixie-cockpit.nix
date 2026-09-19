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
  # The page itself is packages/nixie-cockpit/index.html; its rules are
  # beside it in history.css, in the finish. They are a file rather than a
  # <style> block because Cockpit serves its packages under default-src
  # 'self', which refuses an inline one.
  inherit ((import ../lib/template.nix lib)) fill;
  page = pkgs.writeText "nixie-history.html" (fill ./nixie-cockpit/index.html { });
  style = pkgs.writeText "nixie-history.css" (
    fill ./nixie-cockpit/history.css ((import ../lib/tokens.nix { inherit lib; }).marks t)
  );
in
pkgs.runCommand "nixie-cockpit" { meta.priority = 4; } ''
  d=$out/share/cockpit/nixie-history
  mkdir -p "$d"
  cat >"$d/manifest.json" <<'JSON'
  ${manifest}
  JSON
  cp ${page} "$d/index.html"
  cp ${style} "$d/history.css"
  cp ${./nixie-cockpit/history.js} "$d/history.js"
''
