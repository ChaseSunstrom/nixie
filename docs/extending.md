# Extending without forking

Every hook point is an option a site sets; none is an edit to the platform.

- **Add a host module.** `settings` in `site.nix` is a full NixOS module:
  `settings = { imports = [ ./my-module.nix ]; nixie.profile = "server"; };`.
- **Add a guest.** One entry in `guests.nix` plus a directory; `devices` and
  `extraConfig` pass anything the schema lacks straight to Incus.
- **Add a data kind.** `nixie.data.kinds.<name> = ./kinds/<name>.nix;` with
  the interface in the data guide.
- **Add a firewall rule.** `nixie.network.firewall.extraInputRules` and
  `extraForwardRules` (inet family), or per guest `firewall` (bridge family,
  keyed on that guest's port).
- **Add a scrape target.** `nixie.monitoring.extraScrapeConfigs = [ { job_name = "x"; static_configs = [ { targets = [ "…" ]; } ]; } ];`.
- **Add a dashboard.** `nixie.monitoring.dashboards.mine = ./mine.json;`
  (Grafana-shaped JSON; the control panel imports the same files).
- **Add a control panel link.** `nixie.ui.links = [ { label = "Wiki"; url = "https://…"; } ];`.
- **Change the finish or the tokens.** `nixie.ui.theme` and a JSON override
  in `nixie.ui.tokens`; the desktop follows with `nixie.desktop.finish`.
- **Replace the control panel.** `nixie.incus.ui.package = pkgs.callPackage ./my-ui.nix { };`.
- **Add an installer step.** In a module of the site's own (the host's
  `configuration.nix` is never overwritten), declare an option with
  `inputs.nixie.lib.mkOption`, giving it `nixieUi = { section = "services"; order = 9; }`
  and a description written for a person; the wizard renders it in that
  section, labelled by its path. nixpkgs' own `mkOption` refuses an argument
  it does not know, which is why the metadata goes through this one:

  ```nix
  { inputs, ... }:
  {
    options.nixie.site.motto = inputs.nixie.lib.mkOption {
      type = inputs.nixpkgs.lib.types.str;
      default = "";
      description = "A line this site puts on its own machines.";
      nixieUi.section = "services";
    };
  }
  ```
- **Recipes.** `nixie.recipes.<name> = ./recipes/<name>.nix;` then
  `recipe = "<name>";` in a guest. The platform ships `static-web` and
  `oci-service` and no more.
