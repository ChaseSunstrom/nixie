# `mkOption` that also carries `nixieUi` metadata (wizard section, order,
# secret kind). nixpkgs' mkOption rejects unknown arguments, so the metadata is
# attached after the option is built; the module system keeps extra attributes.
lib: {
  mkOption =
    args:
    lib.mkOption (builtins.removeAttrs args [ "nixieUi" ])
    // lib.optionalAttrs (args ? nixieUi) { inherit (args) nixieUi; };
}
