# Add a guest

One entry in `guests.nix` and, for a NixOS guest, a directory:

```nix
  app = {
    recipe = "oci-service";
    ip = "192.0.2.30/24";
    mounts."/data/state/app" = "/var/lib/app";
    backup = [ "/data/state/app" ];
    expose.lan = [ 8080 ];
    module = ./guests/app/configuration.nix;
  };
```

```nix
# guests/app/configuration.nix
{
  nixie.recipe.ociService = {
    image = "docker.io/library/nginx:1.27";
    ports = [ "8080:80" ];
    volumes = [ "/var/lib/app:/usr/share/nginx/html" ];
  };
}
```

Then `nixie apply` (or `nix run .#apply` from the site). The host is switched
first so the firewall chain, the mount directory and the image exist; the
image is imported by hash; tofu creates the instance. `nixie doctor` lists
every declared guest and its state.

For a foreign image: `kind = "image"` (or `"vm"`), `image.fingerprint` from
the image server, `cloudInit = ./guests/app/cloud-init.yaml`.
