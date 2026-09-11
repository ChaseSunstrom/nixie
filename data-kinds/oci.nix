# A container image by digest into a local OCI layout. Manifest entry: { image; digest; }
{ pkgs }:
{
  runtimeInputs = [
    pkgs.skopeo
    pkgs.jq
  ];
  fetch = ''
    image=$(jq -r .image <<<"$entry"); digest=$(jq -r .digest <<<"$entry")
    skopeo copy "docker://$image@$digest" "oci:$dest:latest"
  '';
}
