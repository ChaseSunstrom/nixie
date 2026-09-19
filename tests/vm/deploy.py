key = "@key@"
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
    # In the background, with its own log: run in the foreground it took the
    # whole budget and left nothing to read, and what is being watched for
    # is on the machine at the other end anyway. script(1) opens the
    # terminal gum asks on and stty gives it a size, because script takes
    # that from its own stdin -- a pipe here -- and gum's text input panics
    # drawing a placeholder into a terminal zero columns wide.
    runner.succeed(
        "printf 'nixie\\n' | setsid script -qec "
        f"'stty rows 40 cols 120; NIXIE_TOPLEVEL={toplevel} NIXIE_DISKO={disko} "
        f"nixie-deploy --site /root/site --host server --yes root@installer' "
        "/root/deploy.log >/dev/null 2>&1 & sleep 2"
    )
    # Phases 1 to 3 on the machine being installed, with the markers every
    # front end leaves: that is the install, and what follows the restart is
    # the setup generation, which the continuation entries cover.
    done = False
    for _ in range(90):
        if installer.succeed("test -e /var/lib/nixie/setup/3.done && echo y || echo n").strip() == "y":
            done = True
            break
        installer.sleep(20)
    print(runner.succeed("cat /root/deploy.log || true")[-4000:])
    assert done, "the deploy never finished phase 3"
    installer.succeed("test -e /var/lib/nixie/setup/1.done")
    installer.succeed("test -e /var/lib/nixie/setup/2.done")
