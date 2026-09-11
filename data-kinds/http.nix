# A file by URL and checksum. Manifest entry: { url; sha256; }
{ pkgs }:
{
  runtimeInputs = [
    pkgs.curl
    pkgs.coreutils
    pkgs.jq
  ];
  fetch = ''
    url=$(jq -r .url <<<"$entry"); sum=$(jq -r .sha256 <<<"$entry")
    curl -sSL --fail -o "$dest/file.part" "$url"
    echo "$sum  $dest/file.part" | sha256sum -c --quiet
    mv "$dest/file.part" "$dest/$(basename "$url")"
  '';
}
