# An Incus image by fingerprint, exported as tarballs. Manifest entry: { fingerprint; remote ? "images"; }
{ pkgs }:
{
  runtimeInputs = [
    pkgs.incus-lts.client
    pkgs.jq
  ];
  fetch = ''
    fp=$(jq -r .fingerprint <<<"$entry"); remote=$(jq -r '.remote // "images"' <<<"$entry")
    incus image export "$remote:$fp" "$dest/image"
  '';
}
