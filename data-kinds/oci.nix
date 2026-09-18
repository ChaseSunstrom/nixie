# A container image by digest into a local OCI layout, and into this
# machine's registry when it keeps one. Manifest entry: { image; digest; }
{ pkgs }:
let
  # skopeo refuses to copy anything without a trust policy, and a Nixie host
  # is not a container host: it has no /etc/containers. The manifest names
  # every image by digest, which is the integrity check here -- a signature
  # policy would be a second one over the same bytes -- so the fetcher
  # carries a policy of its own rather than asking the host for one.
  policy = pkgs.writeText "skopeo-policy.json" (
    builtins.toJSON { default = [ { type = "insecureAcceptAnything"; } ]; }
  );
in
{
  runtimeInputs = [
    pkgs.skopeo
    pkgs.jq
  ];
  fetch = ''
    image=$(jq -r .image <<<"$entry"); digest=$(jq -r .digest <<<"$entry")
    skopeo --policy ${policy} copy "docker://$image@$digest" "oci:$dest:latest"
    # And into this machine's own registry when it keeps one, which is what
    # a guest pulls from: the layout stays beside it, so the image is still
    # there for a machine that serves nothing.
    if [ -n "''${NIXIE_REGISTRY:-}" ]; then
      skopeo --policy ${policy} copy --dest-tls-verify=false "oci:$dest:latest" "docker://$NIXIE_REGISTRY/$name:latest"
    fi
  '';
}
