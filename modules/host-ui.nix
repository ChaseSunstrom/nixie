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
  # Joined into /etc/cockpit/share with the package; the lower priority number
  # lets this branding.css win over the one cockpit ships for NixOS.
  branding = pkgs.runCommand "nixie-cockpit-branding" { meta.priority = 4; } ''
    mkdir -p $out/share/cockpit/branding/nixos
    cat >$out/share/cockpit/branding/nixos/branding.css <<CSS
    :root { --pf-v5-global--BackgroundColor--100: ${t.s1}; --pf-v5-global--BackgroundColor--200: ${t.bg}; --pf-v5-global--BackgroundColor--dark-100: ${t.s2}; --pf-v5-global--Color--100: ${t.ink}; --pf-v5-global--Color--200: ${t.muted}; --pf-v5-global--primary-color--100: ${t.brand}; --pf-v5-global--link--Color: ${t.brand2}; --pf-v5-global--BorderColor--100: ${t.line}; --pf-v5-global--FontFamily--sans-serif: Archivo, sans-serif; --pf-v5-global--FontFamily--monospace: "JetBrains Mono", monospace; }
    body, .pf-v5-c-page { background: ${t.bg}; color: ${t.ink}; }
    .pf-v5-c-page__header, .pf-v5-c-masthead { background: ${t.s1}; border-bottom: 1px solid ${t.line}; }
    .pf-v5-c-card { background: ${t.s1}; border: 1px solid ${t.line}; border-radius: 6px; box-shadow: 0 8px 24px -14px ${t.shadow}; }
    .pf-v5-c-button.pf-m-primary { background: ${t.brand}; border-radius: 3px; }
    .login-pf, .login-pf-page { background: ${t.bg}; }
    #brand { font-family: Archivo, sans-serif; font-weight: 600; letter-spacing: -0.03em; font-size: 20px; color: ${t.ink}; }
    #brand::before { content: "nixie · "; color: ${t.brand2}; }
    CSS
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
    port = mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Port the host page listens on.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.cockpit = {
      enable = true;
      inherit (cfg) port;
      plugins = [
        branding
        historyPage
        pkgs.cockpit-files
        pkgs.cockpit-podman
      ];
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
    security.pam.services.cockpit = lib.mkIf (config.nixie.auth.secondFactor == "totp") {
      text = lib.mkAfter ''
        auth required ${pkgs.oath-toolkit}/lib/security/pam_oath.so usersfile=/run/nixie/oath/users window=1 digits=6
      '';
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
