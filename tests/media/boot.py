keys = "mkdir -p /run/nixie/keys && chmod 700 /run/nixie/keys && printf hunter2 >/run/nixie/keys/passphrase && printf 1234 >/run/nixie/keys/pin && printf wipe-me >/run/nixie/keys/duress && printf nixie >/run/nixie/keys/admin-password"
installer.start(); installer.wait_for_unit("multi-user.target")
installer.succeed("mkdir -p /var/lib/nixie/setup && cp @state@ /var/lib/nixie/setup/state.json")
installer.succeed(keys + " && cp @keys_example_host_age@ /run/nixie/keys/age.key")
installer.succeed("cp -r @siteSrc@ /tmp/site && chmod -R u+w /tmp/site")
env = "NIXIE_SITE=/tmp/site NIXIE_TOPLEVEL=@toplevel@ NIXIE_DISKO=@disko@"
installer.succeed(f"{env} nixie-phase 1 >&2 && {env} nixie-phase 2 >&2 && {env} nixie-phase 3 >&2")
installer.shutdown()

client.start(); client.wait_for_unit("multi-user.target")
client.succeed("cp @clientKey@ /root/client_ed25519 && chmod 600 /root/client_ed25519")
ssh = "ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 -i /root/client_ed25519 -p 2222 root@192.168.1.3"

def remote_unlock(answers, gap=25):
    # Same relay as vm-encryption: each answer is fed to the prompt that
    # is pending, in order, while the splash shows it for the pictures.
    client.succeed("ip neigh flush all")
    client.wait_until_succeeds("nc -z 192.168.1.3 2222", timeout=300)
    feed = "; ".join(f"sleep {2 if i == 0 else gap}; printf '%s\\n' '{a}'" for i, a in enumerate(answers))
    client.succeed("timeout 180 sh -c \"(" + feed + "; sleep 5) | " + ssh + "\" || true")

import re, time

def on_console(pattern, timeout=420):
    # The driver's own clock and the whole serial log: the guest is in the
    # initrd, where machine.sleep() would wait for a shell that only
    # stage 2 starts.
    deadline = time.time() + timeout
    while not re.search(pattern, target.get_console_log()):
        assert time.time() < deadline, f"not on the console: {pattern}"
        time.sleep(0.5)

target.start()
client.succeed("ip neigh flush all")
on_console("asking for Passphrase or recovery key on the splash")
time.sleep(2); target.screenshot("boot-passphrase-first")
# Two VMs and a recording share the host; the initrd needs longer here
# than the encryption check does.
client.wait_until_succeeds("nc -z 192.168.1.3 2222", timeout=420)
remote_unlock(["hunter2", "hunter2"])
target.wait_for_unit("multi-user.target")
target.succeed(keys)
# Bounded: succeed() waits for ever by default, and a phase that stops for
# input would hang the whole run with nothing on screen to say so.
target.succeed("nixie-phase 4 >&2", timeout=900)
target.succeed("nixie-phase 6 >&2", timeout=900)
target.succeed("test -s /run/nixie/keys/attestation-qr")
target.shutdown()

target.start()
# The relay answers in the background so the frames keep coming while the
# PIN and passphrase prompts are on the screen being photographed. It is
# detached with its pipes closed: a child holding them open would make
# the driver wait for EOF instead of returning.
client.succeed("ip neigh flush all")
client.succeed(
    "systemd-run --collect --unit=nixie-unlock --setenv=PATH=/run/current-system/sw/bin /bin/sh -c "
    "'until nc -z 192.168.1.3 2222; do sleep 1; done; "
    "{ sleep 2; printf \"1234\\n\"; sleep 25; printf \"hunter2\\n\"; sleep 5; } | " + ssh + "'"
)
import os
os.makedirs("frames", exist_ok=True)
# Each still is taken once the splash shows what it is of, from the
# agent's notes on the serial console.
stills = [
    ("nixie-attestation: code shown", "boot-attestation-code"),
    (r"asking for PIN \(1 of 2\) on the splash", "boot-pin-prompt"),
    (r"asking for Disk passphrase \(2 of 2\) on the splash", "boot-passphrase-prompt"),
]
i = 0
t0 = time.time()
while time.time() - t0 < 45:
    target.screenshot(f"frames/frame-{i:05d}")
    i += 1
    time.sleep(0.1)
    if stills and re.search(stills[0][0], target.get_console_log()):
        time.sleep(0.5)
        target.screenshot(stills.pop(0)[1])
assert not stills, f"never shown: {stills}"
target.wait_for_unit("multi-user.target")
target.screenshot("boot-front-panel")
