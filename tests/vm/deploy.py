key = "@key@"
age = "@age@"
site = "@site@"
toplevel = "@toplevel@"
disko = "@disko@"

# Not start_all: the installed node shares the disk this one writes, and two
# machines cannot hold the same image open. It is started once this has
# finished with it.
runner.start()
installer.start()
runner.wait_for_unit("multi-user.target")
installer.wait_for_unit("sshd.service")
installer.wait_for_unit("multi-user.target")

with subtest("the deploy installs the machine over SSH"):
    # As the identity ssh reaches for by itself: the deploy runs plain ssh,
    # so a key it is not told about is a key it does not use, and the machine
    # falls back to asking for a password nobody is there to type.
    # A writable copy: the site is a store path, and locking it -- which is
    # the first thing the deploy's evaluation does -- writes a flake.lock
    # beside it.
    runner.succeed(f"cp -r {site} /root/site && chmod -R u+w /root/site")
    runner.succeed("mkdir -p /root/.ssh && chmod 700 /root/.ssh")
    runner.succeed(f"install -m 600 {key} /root/.ssh/id_ed25519")
    runner.succeed(f"install -m 600 {age} /root/age.key")
    # A pipe to type into, held open by a writer of its own so the deploy's
    # own open does not wait for one. Loaded up front instead, the answer was
    # eaten before the question: gum asks the terminal for its colours as it
    # starts, and whatever is queued gets read as the reply.
    runner.succeed("mkfifo /root/answers")
    runner.succeed("setsid sh -c 'exec sleep 3600 >/root/answers' >/dev/null 2>&1 & sleep 1")
    # Under systemd, not simply in the background: a deploy takes longer
    # than a test command may, and run loose it left an empty log and no way
    # to tell a crash from slow work. A unit has a state to ask about.
    # script(1) opens the terminal gum asks on, and stty gives it a size --
    # script takes that from its own stdin, a pipe here, and gum's text
    # input panics drawing a placeholder into a terminal no columns wide.
    runner.succeed(
        # With a PATH: a transient unit is given a minimal one, and the
        # system profile is not on it.
        "printf '#!/bin/sh\\nexport PATH=/run/current-system/sw/bin:$PATH\\n"
        "stty rows 40 cols 120\\nexec nixie-deploy "
        "--site /root/site --host server --yes root@installer\\n' >/root/run-deploy.sh"
        " && chmod +x /root/run-deploy.sh"
    )
    runner.succeed(
        "systemd-run --unit=nixie-deploy --collect --property=StandardInput=file:/root/answers "
        f"--setenv=NIXIE_TOPLEVEL={toplevel} --setenv=NIXIE_DISKO={disko} "
                # -f: script writes the typescript as it goes, and without it the
        # file was empty for as long as the deploy ran, which is exactly
        # when it is worth reading.
        "script -qfec /root/run-deploy.sh /root/deploy.log"
    )
    # Phases 1 to 3 on the machine being installed, with the markers every
    # front end leaves: that is the install, and what follows the restart is
    # the setup generation, which the continuation entries cover.
    done = False
    answered = False
    for i in range(90):
        # The deploy restarts the target the moment phase 3 is done, so the
        # backdoor going away is its own next step and not a failure. The
        # markers before it say which.
        try:
            markers = installer.succeed("ls /var/lib/nixie/setup/ 2>/dev/null; true")
        except Exception as e:
            print(f"the installer went away, which is the restart the deploy asks for: {e}")
            done = True
            break
        if "3.done" in markers:
            done = True
            break
        # The site carries secrets for this host, so the one question a plain
        # install asks is where the key that reads them is. Answered when it
        # is on the screen, which is what a person does.
        if not answered and "age key" in runner.succeed("cat /root/deploy.log || true"):
            # A carriage return, which is what Enter sends: in raw mode the
            # line feed is not it, and the answer sat typed but unsubmitted.
            runner.succeed("printf '/root/age.key\\r' >/root/answers")
            answered = True
        if runner.succeed("systemctl is-active nixie-deploy || true").strip() != "active":
            print("the deploy is no longer running:")
            print(runner.succeed("systemctl status nixie-deploy --no-pager || true"))
            break
        if i % 5 == 4:
            print(f"--- {(i + 1) * 20} s in:")
            print(runner.succeed(
                "ls -l /root/deploy.log; tail -c 1500 /root/deploy.log; "
                "journalctl -u nixie-deploy --no-pager -n 15 | cat; "
                "ps -eo pid,stat,etimes,args | grep -E '[n]ixie-deploy|[s]sh |[n]ix-|[n]ix ' | head; true"
            ))
        # On the runner: the machine being installed is the one that goes
        # away, and waiting on it is waiting on the restart.
        runner.sleep(20)
    print(runner.succeed("cat /root/deploy.log || true")[-6000:])
    assert done, "the deploy never finished phase 3"

def restart_and_read(first):
    # Each restart ends the machine: a NixOS test runs qemu with -no-reboot,
    # so the setup generation finishing looks like the backdoor going away.
    # Whatever was read before that is the answer; the next attempt boots the
    # disk again, which now has one generation more.
    try:
        installed.start()
        installed.wait_for_unit("multi-user.target", timeout=900)
        if first:
            installed.succeed("test -e /etc/NIXOS")
            assert installed.succeed("hostname").strip() == "server", "another machine started"
        return installed.succeed("ls /var/lib/nixie/setup/ 2>/dev/null; true")
    except Exception as e:
        print(f"the machine went away, which is what the setup generation does: {e}")
        return ""
    finally:
        pass


with subtest("the machine it installed starts on its own, and carries itself to the end"):
    # Through the monitor: the installer is restarting into the system it was
    # just given, and the disk below it is the one this node opens. It may
    # have gone already, which is the same end.
    try:
        installer.crash()
    except Exception as e:
        print(f"the installer was already gone: {e}")
    # And written off, not merely unreachable: the driver runs `sync` on
    # every machine it still believes is up, which is a broken pipe when one
    # of them restarted itself out of the test.
    installer.wait_for_shutdown()
    seen = ""
    for attempt in range(12):
        read = restart_and_read(attempt == 0)
        print(f"attempt {attempt}: {read.split()}")
        if read:
            seen = read
            if "8.done" in seen:
                break
            # On the runner: this machine is the one that restarts, and
            # waiting on it is waiting on the restart.
            runner.sleep(30)
            continue
        try:
            installed.crash()
        except Exception:
            pass
    # Every phase, with nobody at the keyboard: 1 to 3 from the deploy over
    # SSH, 4 to 8 from the setup generation this leaves behind.
    for n in range(1, 9):
        assert f"{n}.done" in seen, f"phase {n} was never done: {seen.split()}"
    # And the generation that carried them is gone, as after the other paths.
    installed.fail("test -e /run/current-system/specialisation/setup")
