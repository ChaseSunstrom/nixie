# Code and configuration live in files of their own, next to the module that
# installs them; this puts the values Nix knows in place of their `@name@`
# marks. A mark with nothing given for it stops the evaluation, so a renamed
# value cannot reach a machine as literal text.
lib: {
  fill =
    file: values:
    let
      name = builtins.baseNameOf file;
      # Split rather than replace: `builtins.replaceStrings` loses track of
      # the string context when several store paths go in at once ("Bad
      # String Context element"), and each path here is a build input.
      parts = builtins.split "@([a-zA-Z0-9_]+)@" (builtins.readFile file);
      render =
        part:
        if !builtins.isList part then
          part
        else
          let
            mark = builtins.head part;
            value = values.${mark};
          in
          assert lib.assertMsg (values ? ${mark}) "${name}: nothing given for @${mark}@";
          # A path is interpolated, not `toString`ed: that copies the file
          # into the store and keeps it an input, as `${./file}` inline did.
          (if builtins.isPath value then "${value}" else toString value);
    in
    lib.concatStrings (map render parts);
}
