# How the installer's wizard presents each option it shows: a short label in
# place of the option path, `advanced` for the ones behind "More options"
# rather than in the step itself, and `picker` for the ones this machine can
# offer a list for instead of a text field. The description stays with the
# option, and `checks.option-docs` wants an entry here for every option with a
# wizard section.
{
  "nixie.profile".label = "What this machine is for";
  "nixie.host.name".label = "Host name";
  "nixie.disks.system".label = "System disk";
  "nixie.disks.data".label = "Data disk";
  "nixie.network.bridge.uplinks".label = "Network ports for guests";
  "nixie.site.repo".label = "Keep a copy in a git repository";
  "nixie.site.ref" = {
    label = "Branch";
    advanced = true;
  };
  "nixie.data.registry.enable" = {
    label = "Serve container images to the guests";
    advanced = true;
  };
  "nixie.data.registry.port" = {
    label = "Image registry port";
    advanced = true;
  };
  "nixie.updates.mode".label = "When another machine changes the site";
  "nixie.updates.schedule" = {
    label = "How often to look";
    advanced = true;
  };
  "nixie.updates.confirmWithin" = {
    label = "Time to prove itself before going back";
    advanced = true;
  };

  "nixie.security.encryption.enable".label = "Encrypt the disk";
  "nixie.security.tpm.enable" = {
    label = "Bind to this machine's TPM, with a PIN";
    advanced = true;
  };
  "nixie.security.tpm.pcrs" = {
    label = "TPM measurements";
    advanced = true;
    # Sixteen registers with fixed meanings: checkboxes, not a list to type.
    picker = "pcrs";
  };
  "nixie.security.secureBoot.enable" = {
    label = "Secure Boot with your own keys";
    advanced = true;
  };
  "nixie.security.fido2.enable" = {
    label = "Open the disk with a security key";
    advanced = true;
  };
  "nixie.security.attestation.enable" = {
    label = "Show an attestation code at boot";
    advanced = true;
  };
  "nixie.security.duress.enable" = {
    label = "Duress passphrase";
    advanced = true;
  };
  "nixie.security.remoteUnlock.enable" = {
    label = "Unlock over SSH at boot";
    advanced = true;
  };
  "nixie.security.remoteUnlock.port" = {
    label = "Unlock port";
    advanced = true;
  };
  "nixie.security.hardening.ssh.enable" = {
    label = "Key-only, hardened SSH";
    advanced = true;
  };
  "nixie.security.hardening.usbguard.enable" = {
    label = "Block USB devices plugged in later";
    advanced = true;
  };
  "nixie.security.hardening.memoryEncryption.enable" = {
    label = "Memory encryption and IOMMU";
    advanced = true;
  };
  "nixie.security.hardening.remoteJournal.enable" = {
    label = "Copy the system log to another machine";
    advanced = true;
  };
  "nixie.security.hardening.remoteJournal.url" = {
    label = "Log destination";
    advanced = true;
  };

  "nixie.auth.admin.name".label = "Administrator name";
  "nixie.auth.admin.passwordFile".label = "Administrator password";
  "nixie.auth.sshKeys".label = "SSH public keys";
  "nixie.auth.secondFactor" = {
    label = "Second factor for the host page";
    advanced = true;
  };
  "nixie.auth.ssh.keyAndPassword" = {
    label = "SSH asks for the password after the key";
    advanced = true;
  };
  "nixie.auth.ssh.passwordLogin" = {
    label = "Allow SSH login with the password";
    advanced = true;
  };

  "nixie.host.timezone" = {
    label = "Time zone";
    # The machine's own tzdata, listed rather than typed.
    picker = "timezone";
  };
  "nixie.network.tailscale.enable".label = "Join a Tailscale network";
  "nixie.network.tailscale.authKeyFile".label = "Tailscale auth key";
  "nixie.network.bridge.mode".label = "Guest network";
  "nixie.network.bridge.vlanAware" = {
    label = "VLAN tags on the guest network";
    advanced = true;
  };
  "nixie.network.bridge.natSubnet" = {
    label = "Private guest network";
    advanced = true;
  };
  "nixie.network.address" = {
    label = "Fixed address";
    advanced = true;
  };
  "nixie.network.gateway" = {
    label = "Gateway";
    advanced = true;
  };
  "nixie.network.dns" = {
    label = "DNS servers";
    advanced = true;
  };
  "nixie.network.egress" = {
    label = "How guests reach the internet";
    advanced = true;
  };
  "nixie.network.exitNode" = {
    label = "Exit node";
    advanced = true;
  };
  "nixie.network.exitNodeAllowLan" = {
    label = "Let guests reach the local network under an exit node";
    advanced = true;
  };
  "nixie.incus.ui.listen" = {
    label = "Control panel reachable from";
    advanced = true;
  };

  "nixie.monitoring.enable".label = "Monitoring";
  "nixie.monitoring.grafana.enable" = {
    label = "Grafana dashboards";
    advanced = true;
  };
  "nixie.backups.enable".label = "Back up state and guests";
  "nixie.backups.repository" = {
    label = "Backup repository";
    # A restic URL, or a folder on a disk this machine can see.
    picker = "path";
  };
  "nixie.backups.schedule" = {
    label = "Backup schedule";
    advanced = true;
  };
  "nixie.hostUi.enable".label = "Host page (Cockpit)";
  "nixie.hostUi.listen" = {
    label = "Host page reachable from";
    advanced = true;
  };
  "nixie.console.frontPanel.enable" = {
    label = "Front panel on the machine's screen";
    advanced = true;
  };
  "nixie.console.kiosk.enable" = {
    label = "Control panel on the machine's screen";
    advanced = true;
  };

  "nixie.desktop.hyde.enable".label = "HyDE instead of the Nixie desktop";
  "nixie.desktop.finish".label = "Finish";
  "nixie.ui.theme" = {
    label = "Finish of the web pages";
    advanced = true;
  };
  "nixie.desktop.keyboard.layout".label = "Keyboard layout";
  "nixie.desktop.keyboard.variant" = {
    label = "Keyboard variant";
    advanced = true;
  };
  "nixie.desktop.wallpaper" = {
    label = "Wallpaper";
    advanced = true;
  };
  "nixie.desktop.flatpak.enable" = {
    label = "Flatpak apps";
    advanced = true;
  };
  "nixie.desktop.monitors" = {
    label = "Monitors";
    advanced = true;
  };
  "nixie.desktop.packages.categories.browsers" = {
    label = "Browsers";
    advanced = true;
  };
  "nixie.desktop.packages.categories.terminals" = {
    label = "Terminal and shell";
    advanced = true;
  };
  "nixie.desktop.packages.categories.editors" = {
    label = "Editors and development";
    advanced = true;
  };
  "nixie.desktop.packages.categories.media" = {
    label = "Media";
    advanced = true;
  };
  "nixie.desktop.packages.categories.office" = {
    label = "Office";
    advanced = true;
  };
  "nixie.desktop.packages.categories.communication" = {
    label = "Communication";
    advanced = true;
  };
  "nixie.desktop.packages.categories.gaming" = {
    label = "Games";
    advanced = true;
  };
  "nixie.desktop.packages.categories.creative" = {
    label = "Creative";
    advanced = true;
  };
}
