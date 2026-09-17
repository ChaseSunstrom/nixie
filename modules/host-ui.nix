# The host page: Cockpit with the files, terminal, storage and podman
# plugins, branded with the Nixie tokens, behind the admin password plus the
# chosen second factor. Off by default because it widens the attack surface.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../lib/option.nix lib) mkOption;
  cfg = config.nixie.hostUi;
  t = (import ../lib/tokens.nix { inherit lib; }).forFinish config.nixie.ui.theme;
  # The fonts the control panel serves itself: a browser on another machine
  # has neither, and a font-family nothing provides falls back in silence.
  # Cockpit serves what sits beside branding.css, the way its own branding
  # reaches for logo.png.
  webFonts = import ../packages/nixie-web.nix { inherit pkgs; };
  # Joined into /etc/cockpit/share with the package; the lower priority number
  # lets this branding.css win over the one cockpit ships for NixOS. Every
  # cockpit page loads it after its own stylesheet, so redefining PatternFly's
  # tokens here reaches the shell, each plugin's frame and the login page: the
  # host page then wears the same finish as the control panel rather than
  # PatternFly's own.
  branding = pkgs.runCommand "nixie-cockpit-branding" { meta.priority = 4; } ''
    d=$out/share/cockpit/branding/nixos
    mkdir -p $d
    cp ${brandingCss} $d/branding.css
    cp ${webFonts.archivo} $d/Archivo.ttf
    cp ${pkgs.jetbrains-mono}/share/fonts/truetype/JetBrainsMono-Regular.ttf $d/
    cp ${pkgs.jetbrains-mono}/share/fonts/truetype/JetBrainsMono-Medium.ttf $d/
  '';
  # PatternFly 6 builds its components from a palette layer and a semantic
  # layer on top of it. Both are redefined: a component that reaches past the
  # semantic token to the palette (several do) still lands on this finish.
  # The finish as custom properties, so the stylesheet beside this file is
  # plain CSS: modules/host-ui/branding.css.
  tokensCss = ''
    :root {
    ${
      lib.concatStrings (
        lib.mapAttrsToList (n: v: "  --nixie-${n}: ${v};\n") (lib.filterAttrs (_: lib.isString) t)
      )
    }  --nixie-scheme: ${if t.dark then "dark" else "light"};
    }
  '';
  brandingCss = pkgs.writeText "nixie-branding.css" (
    tokensCss + builtins.readFile ./host-ui/branding.css
  );

  # Only each package's index.html asks for branding.css, so Logs, Services,
  # Terminal, hardware information and the firewall would keep PatternFly's
  # own look inside an otherwise finished shell. The same link is added to
  # them; everything else is the package as it comes, symlinked rather than
  # rebuilt.
  brandedCockpit =
    pkgs.runCommand "cockpit-branded" { passthru = { inherit (pkgs.cockpit) version; }; }
      ''
        mkdir -p $out
        cp -rs ${pkgs.cockpit}/. $out/
        chmod -R u+w $out
        for f in $out/share/cockpit/*/*.html; do
          if grep -q branding.css "$f"; then continue; fi
          sed 's|</head>|<link href="../../static/branding.css" rel="stylesheet" />\n</head>|' "$f" >branded.html
          rm "$f"
          mv branded.html "$f"
        done
      '';
  historyPage = import ../packages/nixie-cockpit.nix { inherit pkgs; };
  port = toString cfg.port;
  wsDropin = {
    overrideStrategy = "asDropin";
    environment.XDG_DATA_DIRS = "/etc/cockpit/share";
  };
in
{
  options.nixie.hostUi = {
    enable = mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        A separate web page for the host itself: files, a root terminal, the
        journal, services, disks, and the nixie commands. It is Cockpit.
        Turning it on widens the attack surface of a hardened host, which is
        why it is off.
      '';
      nixieUi = {
        section = "services";
        order = 5;
      };
    };
    listen = mkOption {
      type = lib.types.enum [
        "tailnet"
        "lan+tailnet"
      ];
      default = "tailnet";
      description = "Where the host page can be opened from. Guests can never reach it.";
      nixieUi = {
        section = "services";
        order = 6;
      };
    };
    extraOrigins = mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "https://server.example.com:9090" ];
      description = ''
        Other addresses this page is opened at, each with its scheme and port.
        The machine's own name, localhost and this host's addresses are
        already accepted; add a name here if you reach the page by one the
        machine does not know about, such as a DNS alias.
      '';
    };
    port = mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Port the host page listens on.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.cockpit = {
      enable = true;
      package = brandedCockpit;
      inherit (cfg) port;
      plugins = [
        branding
        historyPage
        pkgs.cockpit-files
        pkgs.cockpit-podman
      ];
      # Without these cockpit-ws refuses the browser's websocket with
      # "received request from bad Origin" and the page, having logged the
      # person in, says only "Connection failed". The list merges with the
      # module's own localhost entry; setting WebService.Origins conflicts.
      allowed-origins = [
        "https://${config.nixie.host.name}:${port}"
        "https://127.0.0.1:${port}"
      ]
      ++ cfg.extraOrigins;
      settings = {
        WebService = {
          AllowUnencrypted = false;
          LoginTitle = "nixie host";
        };
        Session.IdleTimeout = 15;
      };
    };
    virtualisation.podman.enable = lib.mkDefault true;
    # cockpit-ws runs unwrapped and only searches XDG_DATA_DIRS for branding;
    # a drop-in points it at the joined share tree the module builds.
    systemd.services."cockpit-wsinstance-https@" = wsDropin;
    systemd.services.cockpit-wsinstance-http = wsDropin;

    # The second factor: TOTP from the enrolled secret, checked by PAM after
    # the password. Every login and privileged action is in the journal.
    # `text` would replace the whole generated stack, leaving a service whose
    # only auth rule is this one: no password is ever checked and every login
    # is refused before the second factor is asked for. A rule is added to
    # the stack instead, after pam_unix so the password is the first factor.
    # The stack's pam_unix is `sufficient`, which ends authentication on a good
    # password before any later rule runs, so here it is `required` and the
    # code is `sufficient`: a good code finishes, a wrong one falls through to
    # pam_deny. The rule is not named `oath`: nixpkgs has a disabled built-in
    # rule of that name, and the two merged into one that never ran.
    security.pam.services.cockpit = lib.mkIf (config.nixie.auth.secondFactor == "totp") {
      rules.auth.unix.control = lib.mkForce "required";
      rules.auth.nixie-totp = {
        order = config.security.pam.services.cockpit.rules.auth.unix.order + 10;
        control = "sufficient";
        modulePath = "${pkgs.oath-toolkit}/lib/security/pam_oath.so";
        settings = {
          usersfile = "/run/nixie/oath/users";
          window = 1;
          digits = 6;
        };
      };
    };
    sops.secrets.totp-secret = lib.mkIf (config.nixie.auth.secondFactor == "totp") { };
    # pam_oath wants "HOTP/T30/6 user - secret" with the secret in hex.
    systemd.services.nixie-oath-users = lib.mkIf (config.nixie.auth.secondFactor == "totp") {
      description = "Second-factor user file for the host page";
      wantedBy = [ "multi-user.target" ];
      # The socket starts before basic.target, so ordering before it would be a
      # cycle; the activated service is what reads the file.
      before = [ "cockpit.service" ];
      after = [ "sops-nix.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # exposure: reads the decrypted TOTP secret to write a root-only file.
        ExecStart = pkgs.writeShellScript "oath-users" ''
          set -eu
          mkdir -p /run/nixie/oath; chmod 700 /run/nixie/oath
          hex=$(${pkgs.python3}/bin/python3 -c 'import base64,sys; s=open(sys.argv[1]).read().strip(); print(base64.b32decode(s + "=" * (-len(s) % 8)).hex())' ${config.sops.secrets.totp-secret.path})
          printf 'HOTP/T30/6 %s - %s\n' ${config.nixie.auth.admin.name} "$hex" >/run/nixie/oath/users
          chmod 600 /run/nixie/oath/users
        '';
      };
    };
    services.journald.extraConfig = "Audit=yes\n";
  };
}
