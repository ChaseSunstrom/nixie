applied = "@applied@"
site = "@site@"


# Both machines start from the same site, in a bare repository they share the
# way a real site shares one over git.
def prepare(m):
    m.wait_for_unit("multi-user.target")
    m.succeed("nix-env --profile /nix/var/nix/profiles/system --set \"$(readlink -f /run/current-system)\"")
    m.succeed(f"mkdir -p /etc/nixie && cp -r {site} /etc/nixie/site && chmod -R u+w /etc/nixie/site")
    m.succeed(
        "git init -q --bare -b main /srv/site.git && "
        "git -C /etc/nixie/site init -q -b main && "
        "git -C /etc/nixie/site add -A && "
        "git -C /etc/nixie/site -c user.name=t -c user.email=t@e commit -qm 'the site as installed' && "
        "git -C /etc/nixie/site remote add origin /srv/site.git && "
        "git -C /etc/nixie/site push -q origin HEAD:main"
    )
    # A system built by `mkSite` records the commit it came from, and that is
    # what "behind" is measured against; one built here has none, so the
    # check falls back to the checkout's own commit, which is the same thing
    # for this machine.
    return m.succeed("git -C /etc/nixie/site rev-parse HEAD").strip()


def push_a_change(m, message):
    """What another machine of the site does: commit and push."""
    m.succeed(
        "rm -rf /tmp/laptop && git clone -q /srv/site.git /tmp/laptop && "
        f"echo '# {message}' >>/tmp/laptop/site.nix && "
        "git -C /tmp/laptop add -A && "
        f"git -C /tmp/laptop -c user.name=laptop -c user.email=l@e commit -qm '{message}' && "
        "git -C /tmp/laptop push -q origin HEAD:main"
    )


start_all()

with subtest("a machine that is up to date says so, and shows nothing"):
    prepare(notify)
    notify.succeed("nixie update --check >&2")
    assert notify.succeed("jq -r .available /run/nixie/update.json").strip() == "false"
    notify.succeed("nixie notices --write")
    quiet = notify.succeed("cat /run/nixie/notices.json")
    assert notify.succeed("jq -r '.notices | length' /run/nixie/notices.json").strip() == "0", quiet

with subtest("notify: the change another machine pushed is seen, and waits"):
    push_a_change(notify, "tighten the firewall")
    notify.succeed("systemctl start nixie-update.service")
    state = notify.succeed("cat /run/nixie/update.json")
    print(state)
    assert '"available":true' in state.replace(" ", "")
    assert "tighten the firewall" in state
    # Said on every surface that shows it: the notices file the panel, the
    # host page and the desktop read, `nixie doctor`, and a login.
    notices = notify.succeed("nixie notices --json")
    print(notices)
    assert '"id":"update"' in notices.replace(" ", "") and "tighten the firewall" in notices
    doctor = notify.succeed("nixie doctor || true")
    assert "commit(s) waiting" in doctor, doctor
    login = notify.succeed("bash -lic true 2>&1 || true")
    assert "newer site" in login, login
    # And nothing was applied: that is what "notify" means.
    notify.fail("test -e /etc/nixie-applied-update")

with subtest("notify: a person applies it, and the machine is up to date again"):
    notify.succeed(f"NIXIE_TOPLEVEL={applied} nixie update --now >&2")
    notify.succeed("test -e /etc/nixie-applied-update")
    # The checkout followed the repository, and the next check is quiet.
    assert notify.succeed("git -C /etc/nixie/site log -1 --format=%s").strip() == "tighten the firewall"
    notify.succeed("nixie update --check >&2")
    assert notify.succeed("jq -r .available /run/nixie/update.json").strip() == "false"
    notify.succeed("nixie notices --write")
    assert notify.succeed("jq -r '.notices | length' /run/nixie/notices.json").strip() == "0"

with subtest("auto: the machine applies it by itself and confirms it"):
    prepare(auto)
    push_a_change(auto, "open the door for the printer")
    # The service switches to a prebuilt system here, as the tests that
    # apply do; a real machine builds the site it has just fetched.
    auto.succeed(
        "mkdir -p /run/systemd/system/nixie-update.service.d && "
        f"printf '[Service]\\nEnvironment=NIXIE_TOPLEVEL={applied}\\n' >/run/systemd/system/nixie-update.service.d/test.conf && "
        "systemctl daemon-reload"
    )
    # Auto mode confirms what it applied when doctor passes, so this machine
    # has to be one doctor passes on.
    auto.succeed("nixie doctor >&2")
    auto.succeed("systemctl start nixie-update.service")
    auto.succeed("test -e /etc/nixie-applied-update")
    # Applied with a way back, then confirmed because doctor passed: no
    # rollback timer is left running.
    journal = auto.succeed("journalctl -u nixie-update.service -o cat")
    print(journal)
    auto.fail("systemctl is-active nixie-apply-confirm.timer")
    auto.fail("test -e /run/nixie/apply-pending.json")
    assert auto.succeed("jq -r .available /run/nixie/update.json").strip() == "false"

with subtest("encryption cannot be turned on or off on an installed machine"):
    # The one setting `apply` refuses, because it is the one that cannot be
    # changed without erasing the disk. A prebuilt system answers from its
    # own layout, which is how apply reads it without evaluating anything.
    other = notify.succeed(
        "mkdir -p /tmp/flipped/etc/nixie && "
        "jq '.features.encryption = (.features.encryption | not)' "
        "/run/current-system/etc/nixie/layout.json >/tmp/flipped/etc/nixie/layout.json && "
        "echo /tmp/flipped"
    ).strip()
    out = notify.fail(f"NIXIE_TOPLEVEL={other} nixie apply --yes 2>&1")
    print(out)
    assert "cannot be changed on an installed system" in out, out
    assert "reinstall from the ISO" in out, out
    # And it says so before touching anything: no pending apply is left.
    notify.fail("test -e /run/nixie/apply-pending.json")

with subtest("a service that failed is said the same way"):
    # Nothing else on this machine is broken: the earlier subtests showed no
    # notices at all, so this one is the notice.
    notify.succeed(
        "systemd-run --unit=nixie-broken-test --service-type=oneshot "
        "/run/current-system/sw/bin/false || true"
    )
    notify.wait_until_succeeds("systemctl is-failed nixie-broken-test.service")
    notices = notify.succeed("nixie notices --json")
    print(notices)
    assert '"id":"units"' in notices.replace(" ", ""), notices
    assert "nixie-broken-test" in notices, notices
    doctor = notify.succeed("nixie doctor || true")
    assert "FAILED:" in doctor and "nixie-broken-test" in doctor, doctor
    notify.succeed("systemctl reset-failed nixie-broken-test.service")
    assert notify.succeed("nixie notices --json | jq -r '.notices | length'").strip() == "0"
