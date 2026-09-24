import re, time

keys = "mkdir -p /run/nixie/keys && chmod 700 /run/nixie/keys && printf hunter2 >/run/nixie/keys/passphrase && printf 1234 >/run/nixie/keys/pin && printf wipe-me >/run/nixie/keys/duress && printf nixie >/run/nixie/keys/admin-password"

def on_console(pattern, timeout=600):
    # The whole serial log of this start, polled: the driver's own wait
    # reads one line a second, slower than a verbose boot writes them.
    deadline = time.time() + timeout
    while True:
        m = re.search(pattern, target.get_console_log(), re.M)
        if m:
            return m
        assert time.time() < deadline, f"not on the console: {pattern}"
        time.sleep(1)

# A hardened machine asks twice once the TPM is bound -- the PIN opens the
# outer layer and the inner one has no answer to reuse -- so the prompts say
# which of the two they are.
def asked(label, again=False):
    # The agent notes each question in the kernel log; the splash itself
    # is read off the screen.
    # Not anchored at the line's end: Plymouth's text view on the same
    # serial console leaves control characters there.
    suffix = " again" if again else "(?! again)"
    on_console("asking for " + re.escape(label) + " on the splash" + suffix)
    time.sleep(2)

def type_in(text):
    target.send_chars(text + "\n")

def screen():
    # Light text on a dark ground: every reading the driver offers.
    text = "\n".join(target.get_screen_text_variants())
    print(text)
    return text

with subtest("phases 1-3: the duress passphrase is a slot that opens nothing, on both layers"):
    installer.start()
    installer.wait_for_unit("multi-user.target")
    installer.succeed("mkdir -p /var/lib/nixie/setup && cp @state@ /var/lib/nixie/setup/state.json")
    installer.succeed(keys + " && cp @keys_example_host_age@ /run/nixie/keys/age.key")
    installer.succeed("cp -r @siteSrc@ /tmp/site && chmod -R u+w /tmp/site")
    env = "NIXIE_SITE=/tmp/site NIXIE_TOPLEVEL=@toplevel@ NIXIE_DISKO=@disko@"
    installer.succeed(f"{env} nixie-phase 1 >&2 && {env} nixie-phase 2 >&2 && {env} nixie-phase 3 >&2", timeout=1800)
    # Phase 3 closes the layers when it is done; the inner one is read
    # through the outer.
    installer.succeed("printf hunter2 | cryptsetup open --key-file=- /dev/vda2 rpool-outer")
    for dev in ["/dev/vda2", "/dev/mapper/rpool-outer"]:
        dump = installer.succeed(f"cryptsetup luksDump {dev}")
        assert re.search(r"^  7: luks2 \(unbound\)", dump, re.M), dump
        # It verifies, and it opens nothing.
        installer.succeed(f"printf wipe-me | cryptsetup open --test-passphrase --key-slot 7 --key-file=- {dev}")
        installer.fail(f"printf wipe-me | cryptsetup open --test-passphrase --key-file=- {dev}")
    installer.succeed("cryptsetup close rpool-outer")
    installer.shutdown()

with subtest("first start: the passphrase typed on the splash opens both layers"):
    target.start()
    asked("Passphrase or recovery key")
    target.screenshot("splash-first-passphrase")
    type_in("hunter2")
    # systemd offers the inner layer the passphrase it was just given,
    # which is the same one, so a person types it once.
    target.wait_for_unit("multi-user.target")
    assert "asking for Disk passphrase" not in target.get_console_log()
    # In the initrd only this agent answers: systemd's console agent used
    # to fail there after its start timeout, and Plymouth's skipped the
    # duress check. The installed system has its own agents after that.
    journal = target.succeed("journalctl -b -o cat")
    initrd = journal.split("Switching root.")[0]
    print("\n".join(l for l in initrd.splitlines() if "assword" in l or "nixie-unlock" in l))
    assert "Dispatch Password Requests" not in initrd, "another password agent ran in the initrd"
    assert "Forward Password Requests to Plymouth" not in initrd, "Plymouth's agent ran in the initrd"
    target.fail("journalctl -b -o cat | grep -iE 'failed to start.*(password|cryptsetup|nixie|plymouth)'")
    target.succeed(keys)
    # The key gets a PIN (fido2-token reads it from a terminal, and
    # flushes what was typed before it asks), and setup gets the PIN.
    target.succeed("fido2-token -L | grep -i canokey")
    target.succeed(
        "dev=$(fido2-token -L | grep -i canokey | cut -d: -f1); "
        "(sleep 2; printf '123456\\n'; sleep 2; printf '123456\\n'; sleep 2) | script -qec \"fido2-token -S $dev\" /dev/null"
    )
    target.succeed("fido2-token -I $(fido2-token -L | grep -i canokey | cut -d: -f1) | grep -qw clientPin")
    target.succeed("printf 123456 >/run/nixie/keys/fido2-pin")
    target.succeed("nixie-phase 4 >&2", timeout=900)
    target.succeed("nixie-phase 6 >&2", timeout=900)
    recovery = target.succeed("cat /run/nixie/keys/recovery-key").strip()
    target.succeed("cryptsetup luksDump /dev/mapper/rpool-outer | grep -q systemd-fido2")
    sealed = target.succeed("cat /boot/nixie/attestation-generation")
    assert sealed == target.succeed("readlink -f /run/booted-system").strip(), sealed
    target.shutdown()

with subtest("a machine with no TPM still asks for the passphrase, and soon"):
    # The code comes from the TPM and is drawn in front of every prompt. With
    # the service ordered after the TPM's device unit, a machine without one
    # waited that device out -- ninety seconds -- before asking for anything.
    # The disk still has its passphrase here: the TPM is enrolled below.
    notpm.start()
    # Polled, like on_console above and for the same reason: the driver's
    # own wait reads about a line a second and a boot prints hundreds, so it
    # was still catching up two minutes after the prompt had come and gone.
    said = ""
    for _ in range(120):
        said = notpm.get_console_log()
        if "nixie-unlock: asking for" in said:
            break
        time.sleep(1)
    asked_at = re.search(r"\[ *([0-9.]+)\] nixie-unlock: asking for", said)
    assert asked_at, said[-3000:]
    # The machine's own clock, which is the measurement that matters: the
    # device timeout this used to sit through is ninety seconds.
    seconds = float(asked_at.group(1))
    print(f"the passphrase was asked for {seconds:.1f} s into the boot")
    assert seconds < 60, f"the prompt came {seconds:.1f} s in"
    # And it says there is no code rather than pretending to have one.
    assert "nixie-attestation: warn shown" in said, said[-3000:]
    # Stopped through the monitor, not by asking the guest: it is sitting at
    # the passphrase prompt in the initrd, where there is no backdoor to
    # answer a shutdown, and the disk below is shared with the starts after
    # this one.
    notpm.crash()

with subtest("the code and the PINs on the splash, a wrong PIN said so"):
    target.start()
    on_console("nixie-attestation: code shown")
    asked("PIN (1 of 2)")
    target.screenshot("splash-code-and-pin")
    # The code, drawn large as two groups of three digits (OCR does not
    # always see the gap), under its caption.
    text = screen()
    assert "Attestation code" in text and re.search(r"\d{3} ?\d{3}", text), "no code on the splash"
    type_in("9999")
    asked("PIN not accepted (wrong PIN, or Secure Boot changed). PIN", again=True)
    target.screenshot("splash-wrong-pin")
    assert "did not open" in screen(), "no word of the wrong PIN"
    type_in("1234")
    # The passphrase layer asks for the security key's PIN instead.
    asked("Security key PIN (2 of 2)")
    target.screenshot("splash-security-key")
    type_in("123456")
    target.wait_for_unit("multi-user.target")
    # From the last question to the real root, by the kernel's clock: the
    # stretch that used to look stuck. The typing waits 2 s of it.
    console = target.get_console_log()

    def stamp(pat):
        m = re.search(r"\[\s*([0-9.]+)\][^\n]*" + pat, console)
        assert m, f"not on the console: {pat}"
        return float(m.group(1))

    took = stamp("Switching root") - stamp("asking for Security key PIN")
    print(f"from the security key's question to the real root: {took:.1f} s")
    assert took < 30, f"{took:.1f} s from the last question to the real root"
    target.succeed("journalctl -b -o cat | grep -i 'fido2'")
    # The secret is sealed for this very system, so nothing is resealed.
    out = target.succeed("journalctl -b -u nixie-attestation-reseal -o cat")
    assert "attestation sealed" not in out, out
    target.succeed("tpm2-totp calculate")
    # Sealed for another system, as after an update: without Secure Boot
    # (this OVMF cannot enforce it) the new chain is left for a person.
    target.succeed("printf /nix/store/an-older-system >/boot/nixie/attestation-generation")
    target.succeed("systemctl restart nixie-attestation-reseal")
    out = target.succeed("journalctl -b -u nixie-attestation-reseal -o cat")
    assert "not sealing" in out, out
    target.succeed("grep -qx /nix/store/an-older-system /boot/nixie/attestation-generation")
    # With Secure Boot reported on (a stand-in bootctl first on the
    # unit's PATH, for this test only), the unit reseals in its own
    # sandbox: the TPM and the ESP have to be reachable from it.
    env = target.succeed("systemctl show -p Environment --value nixie-attestation-reseal")
    path = next(w for w in env.split() if w.startswith("PATH="))[len("PATH="):]
    target.succeed(
        "mkdir -p /run/nixie-test-bin /run/systemd/system/nixie-attestation-reseal.service.d && "
        "printf '#!/bin/sh\\necho \"Secure Boot: enabled (user)\"\\n' >/run/nixie-test-bin/bootctl && "
        "chmod +x /run/nixie-test-bin/bootctl && "
        f"printf '[Service]\\nEnvironment=PATH=/run/nixie-test-bin:{path}\\n' >/run/systemd/system/nixie-attestation-reseal.service.d/test.conf && "
        "systemctl daemon-reload && systemctl restart nixie-attestation-reseal"
    )
    out = target.succeed("journalctl -b -u nixie-attestation-reseal -o cat")
    assert "attestation sealed to" in out, out
    target.succeed("test \"$(cat /boot/nixie/attestation-generation)\" = \"$(readlink -f /run/booted-system)\"")
    target.succeed("tpm2-totp calculate")
    target.succeed("rm -r /run/systemd/system/nixie-attestation-reseal.service.d /run/nixie-test-bin && systemctl daemon-reload")
    target.shutdown()

with subtest("another machine opens the disk with the recovery key and the passphrase"):
    # The installer VM has its own TPM and no security key: the outer
    # layer takes the recovery key, the inner one the passphrase once
    # the key has not turned up.
    installer.start()
    installer.wait_for_unit("multi-user.target")
    installer.succeed(
        "expect -c '"
        "set timeout 180; spawn nixie disk open /dev/vda2; "
        f"expect -re {{for disk}}; send \"{recovery}\\r\"; "
        "expect -re {for disk}; send \"hunter2\\r\"; "
        "expect {is open at}; expect eof; lassign [wait] pid spawn os status; exit $status' >&2"
    )
    installer.succeed("test -e /mnt/nixie/etc/NIXOS && test -d /mnt/nixie/nix/store")
    installer.fail("touch /mnt/nixie/written")
    # That disk's boot partition comes with it, which is what someone whose
    # machine will not start has come here to look at.
    installer.succeed("test -d /mnt/nixie/boot/EFI")
    report = installer.succeed("nixie secure-boot --at /mnt/nixie || true")
    print(report)
    assert "the system opened under /mnt/nixie" in report, report
    installer.succeed("nixie disk close >&2")
    installer.fail("test -e /dev/mapper/nixie-vda2-0 || mountpoint -q /mnt/nixie")
    installer.fail("mountpoint -q /mnt/nixie/boot")
    installer.shutdown()

with subtest("the duress passphrase typed at the PIN prompt wipes both layers"):
    target.start()
    asked("PIN (1 of 2)")
    type_in("wipe-me")
    target.wait_for_shutdown()
    installer.start()
    installer.wait_for_unit("multi-user.target")
    dump = installer.succeed("cryptsetup luksDump /dev/vda2")
    assert not re.search(r"^ +[0-9]+: luks2", dump, re.M), dump
    installer.shutdown()
