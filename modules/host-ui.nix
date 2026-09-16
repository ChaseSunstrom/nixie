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
  brandingCss = pkgs.writeText "nixie-branding.css" ''
    @font-face {
      font-family: "Archivo";
      src: url("Archivo.ttf") format("truetype");
      font-weight: 100 900;
      font-display: swap;
    }
    @font-face {
      font-family: "JetBrains Mono";
      src: url("JetBrainsMono-Regular.ttf") format("truetype");
      font-weight: 400;
      font-display: swap;
    }
    @font-face {
      font-family: "JetBrains Mono";
      src: url("JetBrainsMono-Medium.ttf") format("truetype");
      font-weight: 500;
      font-display: swap;
    }

    :root,
    .pf-v6-theme-dark {
      --pf-t--color--white: ${t.s1};
      --pf-t--color--black: ${t.ink};
      --pf-t--color--gray--10: ${t.bg};
      --pf-t--color--gray--20: ${t.s2};
      --pf-t--color--gray--30: ${t.s3};
      --pf-t--color--gray--40: ${t.line};
      --pf-t--color--gray--45: ${t.line};
      --pf-t--color--gray--50: ${t.line2};
      --pf-t--color--gray--60: ${t.muted};
      --pf-t--color--gray--70: ${t.muted};
      --pf-t--color--gray--80: ${t.ink};
      --pf-t--color--gray--90: ${t.ink};
      --pf-t--color--gray--95: ${t.ink};

      --pf-t--global--background--color--primary--default: ${t.s1};
      --pf-t--global--background--color--secondary--default: ${t.bg};
      --pf-t--global--background--color--tertiary--default: ${t.s2};
      --pf-t--global--background--color--floating--default: ${t.s2};
      --pf-t--global--background--color--control--default: ${t.s2};
      --pf-t--global--background--color--action--plain--hover: ${t.s3};
      --pf-t--global--background--color--action--plain--clicked: ${t.s3};
      --pf-t--global--background--color--highlight--default: ${t.s3};

      --pf-t--global--text--color--regular: ${t.ink};
      --pf-t--global--text--color--subtle: ${t.muted};
      --pf-t--global--text--color--placeholder: ${t.muted};
      --pf-t--global--text--color--link--default: ${t.brand2};
      --pf-t--global--text--color--link--hover: ${t.brand2};
      --pf-t--global--text--color--link--visited: ${t.brand2};
      --pf-t--global--text--color--on-brand--default: ${t.bg};
      --pf-t--global--text--color--brand--default: ${t.brand2};
      --pf-t--global--text--color--brand--hover: ${t.brand2};

      --pf-t--global--border--color--default: ${t.line};
      --pf-t--global--border--color--100: ${t.line};
      --pf-t--global--border--color--200: ${t.line2};
      --pf-t--global--border--color--300: ${t.line2};
      --pf-t--global--border--color--hover: ${t.line2};
      --pf-t--global--border--color--brand--default: ${t.brand};
      --pf-t--global--border--color--control--default: ${t.line};

      --pf-t--global--color--brand--default: ${t.brand};
      --pf-t--global--color--brand--hover: ${t.brand2};
      --pf-t--global--color--brand--clicked: ${t.brand2};
      --pf-t--global--color--status--success--default: ${t.ok};
      --pf-t--global--color--status--warning--default: ${t.hot};
      --pf-t--global--color--status--danger--default: ${t.err};
      --pf-t--global--color--status--info--default: ${t.brand2};
      --pf-t--global--text--color--status--success--default: ${t.ok};
      --pf-t--global--text--color--status--warning--default: ${t.hot};
      --pf-t--global--text--color--status--danger--default: ${t.err};
      --pf-t--global--text--color--status--info--default: ${t.brand2};
      --pf-t--global--icon--color--status--success--default: ${t.ok};
      --pf-t--global--icon--color--status--warning--default: ${t.hot};
      --pf-t--global--icon--color--status--danger--default: ${t.err};
      --pf-t--global--icon--color--status--info--default: ${t.brand2};

      /* The panel's recipes: 6px on controls, 10px on panels and cards. */
      --pf-t--global--border--radius--100: 3px;
      --pf-t--global--border--radius--200: 6px;
      --pf-t--global--border--radius--300: 8px;
      --pf-t--global--border--radius--400: 10px;

      --pf-t--global--font--family--body: Archivo, system-ui, sans-serif;
      --pf-t--global--font--family--heading: Archivo, system-ui, sans-serif;
      --pf-t--global--font--family--mono: "JetBrains Mono", ui-monospace, monospace;
      --pf-t--global--font--family--100: Archivo, system-ui, sans-serif;
      --pf-t--global--font--family--200: Archivo, system-ui, sans-serif;
      --pf-t--global--font--family--300: "JetBrains Mono", ui-monospace, monospace;

      color-scheme: ${if t.dark then "dark" else "light"};
    }

    body,
    .pf-v6-c-page,
    .pf-v6-c-page__main {
      background: ${t.bg};
      color: ${t.ink};
    }

    /* The control panel's header: one surface, one hairline under it. */
    .pf-v6-c-masthead {
      background: ${t.s1};
      border-block-end: 1px solid ${t.line};
      box-shadow: none;
    }

    /* Navigation as pills, the way the panel and the installer draw it. */
    .pf-v6-c-page__sidebar,
    .pf-v6-c-page__sidebar-body {
      background: ${t.bg};
      border-inline-end: 1px solid ${t.line};
    }
    .pf-v6-c-nav__link {
      border-radius: 999px;
      transition: background-color 160ms ease, color 160ms ease;
    }
    .pf-v6-c-nav__link:hover {
      background: ${t.s3};
    }
    .pf-v6-c-nav__item .pf-v6-c-nav__link.pf-m-current,
    .pf-v6-c-nav__link[aria-current="page"] {
      background: ${t.s1};
      color: ${t.brand2};
      font-weight: 500;
    }

    /* Panels: the same border, radius and shadow as every other surface. */
    .pf-v6-c-card,
    .pf-v6-c-panel {
      background: ${t.s1};
      border: 1px solid ${t.line};
      border-radius: 10px;
      box-shadow: 0 8px 24px -14px ${t.shadow};
    }
    .pf-v6-c-card__title,
    .pf-v6-c-title {
      letter-spacing: -0.01em;
    }

    .pf-v6-c-button {
      border-radius: 6px;
      transition: background-color 160ms ease, border-color 160ms ease;
    }
    .pf-v6-c-button.pf-m-primary {
      background: ${t.brand};
      color: ${t.bg};
    }
    .pf-v6-c-button.pf-m-primary:hover {
      background: ${t.brand2};
    }
    .pf-v6-c-button.pf-m-secondary {
      border-color: ${t.line2};
      color: ${t.ink};
    }

    .pf-v6-c-form-control,
    .pf-v6-c-form-control > input,
    .pf-v6-c-text-input-group__text-input {
      background: ${t.s2};
      border-radius: 6px;
      color: ${t.ink};
    }

    .pf-v6-c-table thead th {
      color: ${t.muted};
      font-weight: 500;
    }
    .pf-v6-c-table tbody tr:hover {
      background: ${t.s3};
    }

    /* The login page keeps colours of its own rather than PatternFly's
       tokens, so it takes the finish through those: without them it stays
       PatternFly's light page, with this stylesheet's near-white brand line
       invisible on it. */
    :root,
    .pf-v6-theme-dark {
      --color-body-background: ${t.bg};
      --color-background: ${t.s1};
      --color-secondary-background: ${t.s2};
      --color-text: ${t.ink};
      --color-text-light: ${t.muted};
      --color-text-lighter: ${t.muted};
      --color-border: ${t.line};
      --color-border-light: ${t.line2};
      --color-input: ${t.ink};
      --color-input-background: ${t.s2};
      --color-input-hover: ${t.line2};
      --color-link: ${t.brand2};
      --color-link-active: ${t.brand2};
      --color-primary: ${t.brand};
      --color-primary-active: ${t.brand2};
      --color-error: ${t.err};
      --color-danger: ${t.err};
      --color-warning: ${t.hot};
      --color-disabled-background: ${t.s3};
      --color-disabled-text: ${t.muted};
    }
    .login-pf .container {
      border: 1px solid ${t.line};
      box-shadow: 0 8px 24px -14px ${t.shadow};
    }
    .login-pf .btn-primary,
    .login-pf #login-button {
      background: ${t.brand};
      color: ${t.bg};
      border-radius: 6px;
    }
    #brand {
      font-family: Archivo, system-ui, sans-serif;
      font-weight: 600;
      letter-spacing: -0.03em;
      font-size: 20px;
      color: ${t.ink};
    }
    #brand::before {
      content: "nixie";
      color: ${t.brand2};
    }
    #brand:not(:empty)::before {
      content: "nixie · ";
    }

    @media (prefers-reduced-motion: reduce) {
      * {
        transition: none !important;
        animation: none !important;
      }
    }
  '';

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
