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
      echo "nothing is mocked. Regenerate with the same command. Stills are PNG, video is webm (1280 wide,"
      echo "at most 45 s, VP9), GIFs only for loops under 8 s. The whole gallery is kept under 100 MB and"
      echo "each video under 8 MB so it lives in git with no large-file storage."
      echo
      echo "| asset | produced by |"
      echo "|---|---|"
    } >"$shot"
    # Everything here goes into git as an ordinary file, so the gallery has a
    # budget: 8 MB a video, 100 MB the lot. A video that will not fit at the
    # lowest bitrate is a failure, not a silently huge commit.
    videoBudget=$((8 * 1024 * 1024))
    galleryBudget=$((100 * 1024 * 1024))
    encode() {
      src=$1; dst=$2
      for br in 1200k 800k 500k 320k 200k; do
        ffmpeg -loglevel error -y -i "$src" -t 45 -vf 'scale=min(1280\,iw):-2' \
          -c:v libvpx-vp9 -b:v "$br" -deadline good -cpu-used 2 -an "$dst"
        if [ "$(stat -c %s "$dst")" -le "$videoBudget" ]; then return 0; fi
      done
      echo "$dst is over $((videoBudget / 1024 / 1024)) MB even at the lowest bitrate" >&2
      return 1
    }
    run() { # name -> builds mediaTests.<name> and prints its output path
      nix build --no-link --print-out-paths ".#mediaTests.x86_64-linux.$1" 2>/dev/null | tail -1
    }
    failed=()
    for name in panel desktop guests boot installer console; do
      if ! p=$(run "$name") || [ -z "$p" ]; then
        # Every run is attempted before giving up, so one command names all
        # the broken ones; an incomplete gallery is never a success.
        echo "media run $name failed; its assets do not exist" >&2
        failed+=("$name")
        continue
      fi
      # Not frames/: those are the individual frames of a video, not gallery
      # images, and there are hundreds of them.
      mapfile -t pngs < <(find "$p" -maxdepth 2 -name '*.png' -not -path '*/frames/*' | sort)
      for f in "''${pngs[@]}"; do
        n=$(basename "$f")
        # Assets are named by their basename, so two runs using one name would
        # leave the gallery with the second and the shot list claiming both.
        if [ -e "$out/$n" ]; then echo "two runs both produced $n; rename one of them" >&2; exit 1; fi
        cp "$f" "$out/$n"
        # shellcheck disable=SC2016  # markdown backticks, not command substitution
        printf '| `%s` | `mediaTests.%s` (machine.screenshot or Playwright) |\n' "$n" "$name" >>"$shot"
      done
      mapfile -t vids < <(find "$p" \( -name '*.webm' -o -name '*.mp4' \) | sort)
      for f in "''${vids[@]}"; do
        b=$(basename "$f"); b=''${b%.*}
        encode "$f" "$out/$name-$b.webm"
        # shellcheck disable=SC2016  # markdown backticks, not command substitution
        printf '| `%s` | `mediaTests.%s` (recorded in the session, ffmpeg to vp9 under the size budget) |\n' "$name-$b.webm" "$name" >>"$shot"
      done
      find "$p" -name '*.cast' | while read -r f; do
        b=$(basename "$f" .cast)
        agg --theme 1f2226,eceae5 --font-family "JetBrains Mono" "$f" "$out/$name-$b.gif"
        # shellcheck disable=SC2016  # markdown backticks, not command substitution
        printf '| `%s` | `mediaTests.%s` (asciinema, agg) |\n' "$name-$b.gif" "$name" >>"$shot"
      done
      if ls "$p"/frames/*.png >/dev/null 2>&1; then
        ffmpeg -loglevel error -y -framerate 10 -pattern_type glob -i "$p/frames/*.png" -t 45 -vf 'scale=min(1280\,iw):-2' -c:v libvpx-vp9 -b:v 600k "$out/$name-frames.webm"
        # This one is not built by encode(), so it gets the same budget here.
        if [ "$(stat -c %s "$out/$name-frames.webm")" -gt "$videoBudget" ]; then
          echo "$name-frames.webm is over $((videoBudget / 1024 / 1024)) MB" >&2; exit 1
        fi
        # shellcheck disable=SC2016  # markdown backticks, not command substitution
        printf '| `%s` | `mediaTests.%s` (screendumps at 10 fps, ffmpeg) |\n' "$name-frames.webm" "$name" >>"$shot"
      fi
    done
    if [ ''${#failed[@]} -gt 0 ]; then
      echo "these media runs failed, so the gallery is incomplete: ''${failed[*]}" >&2
      exit 1
    fi
    total=$(du -sb "$out" | cut -f1)
    printf '\nThe gallery is %s MB; the budget is %s MB, so it lives in git with no large-file storage.\n' \
      "$((total / 1024 / 1024))" "$((galleryBudget / 1024 / 1024))" >>"$shot"
    if [ "$total" -gt "$galleryBudget" ]; then
      echo "docs/media is $((total / 1024 / 1024)) MB, over the $((galleryBudget / 1024 / 1024)) MB budget" >&2
      exit 1
    fi
    echo "media written to $out ($((total / 1024 / 1024)) MB, commit $commit)"
  '';
}
