# Use a NAS for data, copies and backups

Name the NAS's NFS share in the host's `settings`, then say what lives on it.

```nix
nixie.nas.tank = {
  server = "nas.lan";            # the NAS's name or address
  export = "/mnt/tank/nixie";    # the folder it shares for this machine
  cache = true;                  # keep what is read on the local disk too
  whenDown = "hold";             # stop the guests that need it while it is gone
};

nixie.data.cache.on = "tank";    # models, images: fetched once, read through the local cache
nixie.data.media.on = "tank";
nixie.data.state.on = "tank";    # guests' irreplaceable data (needs whenDown = "hold")

# A dated copy of state/ every night, hard-linked so unchanged files are free.
nixie.data.copies.state = { from = "state"; to = "tank:copies/state"; keep = 14; };

# Backups to the same NAS (or keep them elsewhere: a NAS is one place).
nixie.backups.repository = "nas:tank/restic";
```

Then `nixie apply`. The share mounts at `/nas/tank` the first time something
uses it; `/data/cache` (and the others you placed) are that share's folders
from then on, so guests' mounts from the data root need no change.

## On the NAS

Export the folder over NFS to this machine, read and write. The machine
writes as root (backups and copies keep owners and permissions), so the
export needs root not to be squashed: on TrueNAS, "Maproot User: root"; on
Synology, "Squash: No mapping"; in `/etc/exports`,
`/mnt/tank/nixie 192.168.1.10(rw,no_root_squash,no_subtree_check)`.

## When the NAS is down

- The machine starts and runs anyway; the share is never in the way of
  booting.
- `whenDown = "degrade"`: guests keep running; what reads from the share
  waits or fails until it is back.
- `whenDown = "hold"`: guests that use the share are stopped, and started
  again when it answers. State on a NAS requires this, so nothing writes
  state while it is gone.
- The notices (control panel, host page, console) say which share is
  unreachable; `nixie nas status` shows each share and what waits for it.
