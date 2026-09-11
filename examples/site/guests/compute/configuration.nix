{
  nixie.recipe.ociService = {
    image = "docker.io/library/python:3.12-slim";
    environment.NVIDIA_VISIBLE_DEVICES = "all";
  };
}
