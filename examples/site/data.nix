# What lives in the cache directory, by fetcher kind. Everything here can be
# deleted and fetched again.
{
  http.example-dataset = {
    url = "https://example.com/dataset.tar";
    sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
  };
  hf.small-model = {
    repo = "org/model";
    rev = "main";
    include = [ "*.safetensors" ];
  };
  oci.nginx = {
    image = "docker.io/library/nginx";
    digest = "sha256:0000000000000000000000000000000000000000000000000000000000000000";
  };
  incus-images.alpine = {
    fingerprint = "de4efaf408b8bda90121491390e57b7bebb27373bd6917fc9bddb47d6de616d5";
  };
}
