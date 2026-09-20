key = "@key@"
age = "@age@"
site = "@site@"
toplevel = "@toplevel@"
disko = "@disko@"
kexec = "@kexec@"
plain_address = "@plainAddress@"

runner.start()
plain.start()
runner.wait_for_unit("multi-user.target")
plain.wait_for_unit("sshd.service")
plain.wait_for_unit("multi-user.target")

with subtest("the deploy kexecs a machine that is not the ISO, and installs it"):
    # What the deploy looks for before it decides which branch to take.
    plain.fail("test -e /etc/nixie-iso")

    runner.succeed(f"cp -r {site} /root/site && chmod -R u+w /root/site")
    runner.succeed("mkdir -p /root/.ssh && chmod 700 /root/.ssh")
    runner.succeed(f"install -m 600 {key} /root/.ssh/id_ed25519")
    runner.succeed(f"install -m 600 {age} /root/age.key")
    # A pipe to type into, held open by a writer of its own so the deploy's
    # own open does not wait for one. Loaded up front instead, the answer is
    # eaten before the question: gum asks the terminal for its colours as it
    # starts and reads whatever is queued as the reply.
    runner.succeed("mkfifo /root/answers")
    runner.succeed("setsid sh -c 'exec sleep 3600 >/root/answers' >/dev/null 2>&1 & sleep 1")
    # A PATH and a HOME: a transient unit is given neither, and
    # nixos-anywhere -- which only this branch reaches -- reads HOME for the
    # throwaway key it logs in with. script(1) opens the terminal gum asks
    # on, -f flushes it so the log can be read while it runs, and stty gives
    # it a size, because script takes that from its own stdin.
    runner.succeed(
        "printf '#!/bin/sh\\nexport PATH=/run/current-system/sw/bin:$PATH HOME=/root\\n"
        "stty rows 40 cols 120\\nexec nixie-deploy "
        f"--site /root/site --host server --yes root@{plain_address}\\n' >/root/run.sh"
        " && chmod +x /root/run.sh"
    )
    runner.succeed(
        "systemd-run --unit=kexec-deploy --collect --property=StandardInput=file:/root/answers "
        f"--setenv=NIXIE_TOPLEVEL={toplevel} --setenv=NIXIE_DISKO={disko} --setenv=NIXIE_KEXEC={kexec} "
        "script -qfec /root/run.sh /root/deploy.log"
    )

    # Past the kexec the machine is an installer in RAM with no backdoor of
    # its own, so it is asked over SSH from the runner -- with the host key
    # ignored, because the kexec gave it a new one.
    ssh = f"ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 root@{plain_address}"
    kexeced = done = answered = False
    for i in range(120):
        screen = runner.succeed("cat /root/deploy.log || true")
        # The site carries secrets for this host, so the one question a
        # plain install asks is where the key that reads them is. Answered
        # when it is on the screen, which is what a person does, and with a
        # carriage return, which is what Enter sends.
        if not answered and "age key" in screen:
            runner.succeed("printf '/root/age.key\\r' >/root/answers")
            answered = True
        if not kexeced and "machine will boot into nixos" in screen:
            kexeced = True
            print("the machine was kexeced into the installer")
        if runner.succeed(f"{ssh} test -e /var/lib/nixie/setup/3.done 2>/dev/null && echo y || echo n").strip() == "y":
            done = True
            break
        if runner.succeed("systemctl is-active kexec-deploy || true").strip() != "active":
            print("the deploy is no longer running:")
            print(runner.succeed("systemctl status kexec-deploy --no-pager || true"))
            break
        if i % 5 == 4:
            print(f"--- {(i + 1) * 20} s in:")
            print(runner.succeed("tail -c 900 /root/deploy.log; true"))
        # On the runner: the machine being installed is the one that goes
        # away, and waiting on it is waiting on the kexec.
        runner.sleep(20)
    print(runner.succeed("cat /root/deploy.log || true")[-6000:])
    assert kexeced, "the deploy never kexeced the machine; it took the ISO branch"
    assert done, "the install never finished phase 3 on the kexeced machine"
    for marker in ("1.done", "2.done"):
        runner.succeed(f"{ssh} test -e /var/lib/nixie/setup/{marker}")
    # It stays up on a kernel the driver cannot talk to, so it is stopped
    # through the monitor rather than left for the driver's closing sync.
    try:
        plain.crash()
    except Exception as e:
        print(f"the kexeced machine was already gone: {e}")
    plain.wait_for_shutdown()
