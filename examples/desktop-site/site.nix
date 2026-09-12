{
  hosts.laptop = {
    hardware = ./hosts/laptop/hardware.nix;
    secrets = ./secrets/laptop.yaml;
    settings = {
      nixie.profile = "desktop";
      nixie.auth.admin.name = "me";
      nixie.desktop.finish = "graphite";
      # A finish of this site's own, on top of the three built in. Colours you
      # leave out keep Graphite's.
      nixie.desktop.themes.midnight = {
        dark = true;
        colors = {
          bg = "#0f1420";
          ink = "#dbe4f4";
          brand = "#3f6fd8";
          brand2 = "#79b8ff";
          ok = "#86d99b";
          err = "#ef8785";
        };
      };
    };
  };
}
