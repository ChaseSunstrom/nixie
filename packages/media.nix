# `nix run .#media`: regenerate docs/media from scratch. Every asset comes
# from a media run (a NixOS test that screenshots or records inside a VM),
# and SHOTLIST.md maps each file to the run and the commit that produced it.
{ pkgs }:
pkgs.writeShellApplication {
  name = "nixie-media";
  runtimeInputs = with pkgs; [
    nix
    git
    ffmpeg
    asciinema-agg
    imagemagick
    coreutils
    findutils
    jq
  ];
  text = ''
    out=docs/media
    # Start from nothing: stale assets would be indistinguishable from fresh ones.
    mkdir -p "$out"
    find "$out" -mindepth 1 -type f -delete
    commit=$(git rev-parse --short HEAD)
    date=$(date -u +%Y-%m-%dT%H:%MZ)
    shot=$out/SHOTLIST.md
    {
      echo "# Shot list"
      echo
      echo "Every file here was produced by \`nix run .#media\` at commit $commit ($date) from a real run in a VM;"
      echo "nothing is mocked. Regenerate with the same command. Stills are PNG, video is webm (the screen's own"
      echo "size, at most 60 s), GIFs only for loops under 8 s."
      echo
      echo "| asset | produced by |"
      echo "|---|---|"
    } >"$shot"
    run() { # name -> builds mediaTests.<name> and prints its output path
      nix build --no-link --print-out-paths ".#mediaTests.x86_64-linux.$1" 2>/dev/null | tail -1
    }
    for name in panel desktop guests boot installer console; do
      if ! p=$(run "$name") || [ -z "$p" ]; then echo "media run $name failed; its assets do not exist" >&2; continue; fi
      find "$p" -maxdepth 2 -name '*.png' | sort | while read -r f; do
        n=$(basename "$f"); cp "$f" "$out/$n"
        printf '| `%s` | `mediaTests.%s` (machine.screenshot or Playwright) |\n' "$n" "$name" >>"$shot"
      done
      find "$p" -name '*.webm' | while read -r f; do
        n="$name-$(basename "$f")"; cp "$f" "$out/$n"
        printf '| `%s` | `mediaTests.%s` (Playwright recordVideo) |\n' "$n" "$name" >>"$shot"
      done
      find "$p" -name '*.mp4' | while read -r f; do
        b=$(basename "$f" .mp4)
        ffmpeg -loglevel error -y -i "$f" -t 60 -vf 'scale=min(1920\,iw):-2' -c:v libvpx-vp9 -b:v 2M -an "$out/$name-$b.webm"
        printf '| `%s` | `mediaTests.%s` (wf-recorder in the session, ffmpeg to vp9) |\n' "$name-$b.webm" "$name" >>"$shot"
      done
      find "$p" -name '*.cast' | while read -r f; do
        b=$(basename "$f" .cast)
        agg --theme 1f2226,eceae5 --font-family "JetBrains Mono" "$f" "$out/$name-$b.gif"
        printf '| `%s` | `mediaTests.%s` (asciinema, agg) |\n' "$name-$b.gif" "$name" >>"$shot"
      done
      if ls "$p"/frames/*.png >/dev/null 2>&1; then
        ffmpeg -loglevel error -y -framerate 10 -pattern_type glob -i "$p/frames/*.png" -t 60 -c:v libvpx-vp9 -b:v 1M "$out/$name-console.webm"
        printf '| `%s` | `mediaTests.%s` (screendumps at 10 fps, ffmpeg) |\n' "$name-console.webm" "$name" >>"$shot"
      fi
    done
    echo "media written to $out (commit $commit)"
  '';
}
