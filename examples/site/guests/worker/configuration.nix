{
  nixie.recipe.ociService = {
    image = "docker.io/library/nginx:1.27";
    ports = [ "80:80" ];
  };
}
