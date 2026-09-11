# A Hugging Face repository at a revision. Manifest entry: { repo; rev; include ? [ ]; }
{ pkgs }:
{
  runtimeInputs = [
    pkgs.python3Packages.huggingface-hub
    pkgs.jq
  ];
  fetch = ''
    repo=$(jq -r .repo <<<"$entry"); rev=$(jq -r .rev <<<"$entry")
    mapfile -t include < <(jq -r '.include[]?' <<<"$entry")
    args=(); for i in "''${include[@]}"; do args+=(--include "$i"); done
    hf download "$repo" --revision "$rev" --local-dir "$dest" "''${args[@]}"
  '';
}
