host.wait_for_unit("incus.service")
host.wait_for_unit("incus-preseed.service")
host.wait_for_unit("prometheus.service")
host.succeed("mkdir -p /data/state/web && echo hello > /data/state/web/index.html")
host.succeed("nixie apply --yes --skip-host >&2")
host.wait_until_succeeds("incus list web -c s -f csv | grep -q RUNNING")
host.succeed("incus launch $(jq -r '.declared.web.image' /etc/nixie/guests.json) scratch")
host.succeed("openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 30 -subj /CN=media -keyout /root/client.key -out /root/client.crt 2>/dev/null && incus config trust add-certificate /root/client.crt")
host.succeed("sleep 20")  # a little history for the charts
host.succeed("python3 @script@ >&2")
# The second factor is a PAM module reading a file another unit writes:
# logging in before it exists is refused as a wrong password.
host.wait_for_unit("cockpit.socket")
host.wait_for_unit("nixie-oath-users.service")
host.succeed("python3 @cockpit@ >&2")
host.succeed("ls /tmp/media >&2")
host.copy_from_vm("/tmp/media", "media")
