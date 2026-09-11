# The guests. This is the only place their names appear. One entry per
# capability the platform must express; addresses use the documentation range.
{
  # A NixOS guest running a native service from a recipe, files from the data root.
  web = {
    recipe = "static-web";
    ip = "192.0.2.10/24";
    mounts."/data/state/web" = "/var/www";
    backup = [ "/data/state/web" ];
    expose.lan = [ 80 ];
    expose.tailnet = [ 80 ];
    module = ./guests/web/configuration.nix;
  };
  # A NixOS guest with its own configuration, a fixed address on the bridge,
  # state mounted from the data root and backed up.
  db = {
    ip = "192.0.2.20/24";
    mounts."/data/state/db" = "/var/lib/postgresql";
    backup = [ "/data/state/db" ];
    limits.memory = "2GiB";
    module = ./guests/db/configuration.nix;
  };
  # A NixOS guest running an OCI image with podman and no daemon.
  worker = {
    recipe = "oci-service";
    module = ./guests/worker/configuration.nix;
  };
  # The same, with every host GPU handed in.
  compute = {
    recipe = "oci-service";
    gpu = true;
    limits.cpu = "4";
    module = ./guests/compute/configuration.nix;
  };
  # A nested guest running its own container runtime.
  builder = {
    nesting = true;
    module = ./guests/builder/configuration.nix;
  };
  # A virtual machine from a pinned foreign image with cloud-init.
  vm1 = {
    kind = "vm";
    image.fingerprint = "195f2693effacf8d43de79ca81d263c147db1fce01a79743e03dd72dbf72b04b";
    cloudInit = ./guests/vm1/cloud-init.yaml;
    limits.memory = "1GiB";
  };
  # A foreign container image with cloud-init.
  legacy = {
    kind = "image";
    image.fingerprint = "de4efaf408b8bda90121491390e57b7bebb27373bd6917fc9bddb47d6de616d5";
    cloudInit = ./guests/legacy/cloud-init.yaml;
  };
}
