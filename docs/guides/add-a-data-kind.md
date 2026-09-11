# Add a data kind

A kind is one file with one interface. It receives `pkgs` and returns the
tools it needs and a bash snippet that runs once per manifest entry with
`$entry` (the entry as JSON) and `$dest` (the target directory) set:

```nix
# my-site/kinds/rsync.nix
{ pkgs }:
{
  runtimeInputs = [ pkgs.rsync pkgs.jq ];
  fetch = ''
    src=$(jq -r .source <<<"$entry")
    rsync -a "$src/" "$dest/"
  '';
}
```

Register it and use it:

```nix
# site.nix, in the host's settings
nixie.data.kinds.rsync = ./kinds/rsync.nix;
```

```nix
# data.nix
{ rsync.archive = { source = "backup-host:/srv/archive"; }; }
```

`nixie fetch` runs it into `<root>/cache/rsync/archive` and marks it
`.complete`; a half-fetched entry is cleared and fetched again.
