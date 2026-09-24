# Route traffic through a VPN, a tailnet exit node or Tor

An *exit* is a way out to the internet other than your own connection. Name
as many as you like in the host's `settings`, then give each kind of traffic
an ordered list of them. The first exit in a list that works carries that
traffic; when it stops, the next one takes over; when none works, that
traffic is cut off rather than sent out through your own connection.

```nix
nixie.network.exits = {
  # A device on your tailnet that offers itself as an exit node.
  home = { type = "tailnet"; node = "home-router"; };
  # NordVPN over NordLynx. The token comes from your NordVPN account
  # (Services, NordVPN, Access token) and lives in the site's secrets.
  nord = { type = "nordvpn"; tokenFile = config.sops.secrets.nord-token.path; country = "ch"; };
  # Any provider's WireGuard file: Mullvad, Proton, your own server.
  mullvad = { type = "wireguard"; configFile = config.sops.secrets.mullvad.path; };
  # Tor, which itself connects through NordVPN: NordVPN sees only Tor, and
  # Tor never sees your address.
  tor = { type = "tor"; via = "nord"; };
};

nixie.network.guestEgress = [ "nord" "mullvad" ];  # every guest, in order
nixie.network.hostEgress = [ "mullvad" ];          # this machine itself (a desktop: everything)
nixie.guests.browser.egress = [ "tor" ];           # one guest, its own list
nixie.guests.backup.egress = "direct";             # one guest, your own connection
```

Then `nixie apply`. Guest lists need `nixie.network.bridge.mode =
"managed-nat"`, because the machine can only steer traffic it routes.

## Offer your NordVPN as a tailnet exit node

```nix
nixie.network.tailscale.enable = true;
nixie.network.tailscale.advertiseExit = "nord";
```

After `nixie apply`, approve the machine as an exit node in the Tailscale
admin console. Phones and laptops that pick it as their exit node leave
through NordVPN. Any exit works here, Tor included.

## Switch while it runs

```sh
nixie egress                       # which exits are up, and what each list uses
nixie egress use tor --guests      # pin the guests to one exit (direct works too)
nixie egress use nord --host       # the same for this machine
nixie egress auto --guests         # back to the first working exit in the list
```

A pinned exit is used even while it is down, so the kill switch holds. The
host page (Cockpit) has the same choices, and a desktop's control centre has
a tile that steps through them for the machine itself.

## What to know

- Only one tailnet exit node can be in use at a time, because Tailscale
  carries one per machine. WireGuard, NordVPN and Tor exits have no such
  limit and can differ from guest to guest.
- An exit counts as down when its tunnel has not heard from the other side
  for three minutes, so a failover can take that long.
- On Tor, only TCP and DNS get through. Everything else is dropped.
- Your local network and your tailnet stay reachable from this machine
  whatever its exit. Guests reach the LAN only with
  `nixie.network.exitNodeAllowLan`.
