# The boot splash: from the loader to the login or the wizard, with the
# passphrase, the PIN and the attestation code asked and shown on it, and no
# kernel or systemd text under it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../lib/option.nix lib) mkOption;
  theme = config.nixie.host.splashTheme;
  # The themes the Plymouth package carries itself.
  builtin = [
    "bgrt"
    "details"
    "fade-in"
    "glow"
    "script"
    "solar"
    "spinfinity"
    "spinner"
    "text"
    "tribar"
  ];
  # A theme from anywhere: its <name>.plymouth is found at any depth of the
  # source, and the directory holding it is installed where Plymouth looks,
  # with the usual absolute paths pointed at the copy.
  custom =
    pkgs.runCommand "plymouth-theme-${theme.name}"
      {
        src = theme.source;
        file = "${theme.name}.plymouth";
      }
      ''
        f=$(find -L "$src" -name "$file" -print -quit)
        if [ -z "$f" ]; then
          echo "the splash theme source has no $file" >&2
          exit 1
        fi
        d=$out/share/plymouth/themes/${theme.name}
        mkdir -p "$d"
        cp -rL "$(dirname "$f")"/. "$d"
        chmod -R u+w "$d"
        sed -i "s#/usr/share/plymouth/themes/#$out/share/plymouth/themes/#g" "$d"/*.plymouth
      '';
in
{
  options.nixie.host = {
    bootSplash = mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Show a splash screen while the machine starts, from the first moment
        to the login or the setup wizard, and ask for the disk passphrase and
        PIN and show the attestation code on it, in the installer's look.
        Off, the machine prints the usual start-up text instead. A serial
        console on the kernel command line turns the splash into text on
        every screen, so the prompts reach that console too; the kernel
        parameter `plymouth.ignore-serial-consoles` keeps the picture.
      '';
    };
    splashTheme = {
      name = mkOption {
        type = lib.types.str;
        default = "nixie";
        description = ''
          The splash theme, by the name of its `.plymouth` file. "nixie" is the
          platform's own, in the host's finish. Plymouth's own themes
          ("spinner", "bgrt", "fade-in", "glow", "solar", "spinfinity",
          "tribar") need nothing more; any other comes from the theme source.
          Every theme asks for the passphrase and shows the attestation code;
          only the Nixie one also says when a passphrase was wrong and while
          the disk is being opened.
        '';
      };
      source = mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = lib.literalExpression "inputs.plymouth-themes";
        description = ''
          Where a theme that Plymouth does not ship comes from: a package such
          as `pkgs.adi1090x-plymouth-themes`, a directory in the site, or a
          flake input pointing at any theme repository. The theme's
          `<name>.plymouth` file may be at any depth in it.
        '';
      };
    };
  };

  config = lib.mkIf config.nixie.host.bootSplash {
    assertions = [
      {
        assertion = theme.name == "nixie" || theme.source != null || builtins.elem theme.name builtin;
        message = "nixie.host.splashTheme.name = \"${theme.name}\" is not one of Plymouth's own themes; set nixie.host.splashTheme.source to where it comes from";
      }
    ];
    boot.plymouth = {
      enable = true;
      theme = theme.name;
      # In the host's finish: the desktop's (its own themes and HyDE's
      # included), which on a server is nixie.ui.theme.
      themePackages = [
        (import ../packages/nixie-plymouth.nix {
          inherit pkgs;
          t = config.nixie.desktop.tokens;
        })
      ]
      ++ lib.optional (theme.source != null) custom;
      font = "${(import ../packages/nixie-web.nix { inherit pkgs; }).archivo}";
    };
    # Quiet: nothing but the splash from the loader on. Errors still print,
    # and Escape shows the messages behind the splash.
    boot.consoleLogLevel = lib.mkDefault 3;
    boot.initrd.verbose = lib.mkDefault false;
    boot.kernelParams = [
      # The firmware's framebuffer at once: without this Plymouth takes it
      # only after waiting eight seconds for a graphics driver, which the
      # initrd does not load.
      "plymouth.use-simpledrm"
      "quiet"
      "udev.log_level=3"
      "rd.udev.log_level=3"
      "systemd.show_status=auto"
      "rd.systemd.show_status=auto"
    ];
  };
}
