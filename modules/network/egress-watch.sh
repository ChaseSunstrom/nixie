# Every 15 s (or at once on SIGUSR1, which `nixie egress use` sends): which
# exits work, and for every scope the exit it uses -- the one `nixie egress
# use` pinned, else the first working one in its list -- set as the rule for
# the scope's mark. Behind each is a blackhole, so a scope with nothing to use
# is cut off. State for `nixie egress status` goes to /run/nixie/egress.json.
set -uo pipefail
# A loop that must outlive any one failing command (writeShellApplication
# turns errexit on; a mark not in a Tor map made `nft delete` end it).
set +e
cfg=${NIXIE_EGRESS:-/etc/nixie/egress.json}
pins=/var/lib/nixie/egress
mkdir -p /run/nixie "$pins"
wgmark=$(jq -r .wgMark "$cfg")
t0=$(jq -r .table0 "$cfg")
allowlan=$(jq -r .allowLan "$cfg")
x() { jq -r --arg n "$1" ".exits[\$n].$2" "$cfg"; }

rule() { # priority, then the rule; replaces whatever that priority held
  while ip rule del prio "$1" 2>/dev/null; do :; done
  while ip -6 rule del prio "$1" 2>/dev/null; do :; done
  [ $# -gt 1 ] || return 0
  local p=$1
  shift
  ip rule add prio "$p" "$@"
  ip -6 rule add prio "$p" "$@" 2>/dev/null || true
}

# What does not depend on the exits: a tunnel's own packets and the exits'
# requests leave directly; anything with a route in the main table other
# than its default (the LAN, the guests' bridge) goes there; the tailnet
# stays Tailscale's.
rule 900 fwmark "$wgmark" lookup main
rule 910 lookup main suppress_prefixlength 0
while ip rule del prio 920 2>/dev/null; do :; done
ip rule add prio 920 to 100.64.0.0/10 lookup 52
ip route replace blackhole default table "$t0"
ip -6 route replace blackhole default table "$t0" 2>/dev/null || true

chosen_file=/run/nixie/egress-chosen.json
echo '{}' >"$chosen_file"

healthy() { # exit name
  local type iface ts now via
  type=$(x "$1" type)
  case $type in
    wireguard | nordvpn)
      iface=$(x "$1" iface)
      ts=$(wg show "$iface" latest-handshakes 2>/dev/null | awk '{print $2}' | sort -n | tail -1)
      now=$(date +%s)
      [ -n "$ts" ] && [ "$ts" -gt 0 ] && [ $((now - ts)) -lt 180 ]
      ;;
    tailnet)
      tailscale status --json 2>/dev/null | jq -e --arg n "$(x "$1" node)" '
        [.Peer[]? | select(.ExitNodeOption and .Online
          and (.HostName == $n or (.DNSName | startswith($n + ".")) or (.TailscaleIPs | index($n))))] | length > 0' >/dev/null
      ;;
    tor)
      # Up once its way out works (last round) and it has finished starting.
      via=$(x "$1" via)
      { [ "$via" = null ] || [ "$(jq -r --arg s "tor-$1" '.[$s] // ""' "$chosen_file")" = "$via" ]; } &&
        journalctl -u "nixie-tor-$1" -b -o cat --no-pager 2>/dev/null | grep 'Bootstrapped' | tail -1 | grep -q 'Bootstrapped 100%'
      ;;
    *) return 1 ;;
  esac
}

tor_leave() { # mark
  nft delete element inet nixie-egress tor_trans "{ $1 }" 2>/dev/null
  nft delete element inet nixie-egress tor_dns "{ $1 }" 2>/dev/null
  nft delete element inet nixie-egress tor_marks "{ $1 }" 2>/dev/null
  return 0
}

tailnet_set="unset"
wake=0
trap 'wake=1' USR1
while :; do
  health='{}'
  for e in $(jq -r '.exits | keys[]' "$cfg"); do
    h="false"
    ! healthy "$e" || h="true"
    health=$(jq --arg e "$e" --argjson h "$h" '. + {($e): $h}' <<<"$health")
  done
  chosen='{}'
  scopes='{}'
  slot="" # the one tailnet exit node tailscaled carries at a time (D42)
  count=$(jq '.scopes | length' "$cfg")
  for i in $(seq 0 $((count - 1))); do
    name=$(jq -r ".scopes[$i].name" "$cfg")
    mark=$(jq -r ".scopes[$i].mark" "$cfg")
    list=$(jq -r ".scopes[$i].list[]" "$cfg")
    pin=$(cat "$pins/$name" 2>/dev/null || true)
    use=""
    if [ -n "$pin" ]; then
      # Pinned: used even while down, so the kill switch holds.
      use=$pin
    elif [ -z "$list" ]; then
      use=direct
    else
      for e in $list; do
        [ "$(jq -r --arg e "$e" '.[$e]' <<<"$health")" = true ] || continue
        if [ "$(x "$e" type)" = tailnet ] && [ -n "$slot" ] && [ "$slot" != "$e" ]; then continue; fi
        use=$e
        break
      done
    fi
    if [ -n "$use" ] && [ "$use" != direct ] && [ "$(x "$use" type)" = tailnet ]; then slot=${slot:-$use}; fi
    tor_leave "$mark"
    if [ "$use" = direct ]; then
      rule $((1000 + i)) fwmark "$mark" lookup main
    elif [ -z "$use" ]; then
      rule $((1000 + i))
    elif [ "$(x "$use" type)" = tor ]; then
      # TCP and DNS are redirected to Tor before routing and the rest is
      # dropped (tor_marks); the rule only has to let the redirect happen.
      nft add element inet nixie-egress tor_trans "{ $mark : $(x "$use" transPort) }"
      nft add element inet nixie-egress tor_dns "{ $mark : $(x "$use" dnsPort) }"
      nft add element inet nixie-egress tor_marks "{ $mark }"
      rule $((1000 + i)) fwmark "$mark" lookup main
    else
      if [ "$(x "$use" type)" = tailnet ]; then
        ip route replace default dev tailscale0 table "$(x "$use" table)" 2>/dev/null || true
      fi
      rule $((1000 + i)) fwmark "$mark" lookup "$(x "$use" table)"
    fi
    rule $((2000 + i)) fwmark "$mark" lookup "$t0"
    chosen=$(jq --arg s "$name" --arg u "${use:-none}" '. + {($s): $u}' <<<"$chosen")
    scopes=$(jq --arg s "$name" --arg u "${use:-none}" --arg p "$pin" --argjson l "$(jq ".scopes[$i].list" "$cfg")" \
      '. + {($s): {using: $u, pinned: ($p != ""), list: $l}}' <<<"$scopes")
  done
  echo "$chosen" >"$chosen_file"
  # tailscaled carries the one tailnet exit node in use, or none.
  want=""
  [ -z "$slot" ] || want=$(x "$slot" node)
  if [ "$want" != "$tailnet_set" ] && command -v tailscale >/dev/null && [ -S /run/tailscale/tailscaled.sock ]; then
    tailscale set --exit-node="$want" --exit-node-allow-lan-access="$allowlan" 2>/dev/null && tailnet_set=$want
  fi
  servers=$(for e in $(jq -r '.exits | keys[]' "$cfg"); do
    printf '%s\t%s\n' "$e" "$(cat "/run/nixie-exit-$e/server" 2>/dev/null || true)"
  done | jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add // {}')
  jq -n --argjson h "$health" --argjson s "$scopes" --argjson v "$servers" \
    '{exits: ($h | with_entries(.value = {up: .value})), scopes: $s, servers: $v, at: (now | floor)}' >/run/nixie/egress.json.tmp &&
    mv /run/nixie/egress.json.tmp /run/nixie/egress.json
  wake=0
  for _ in $(seq 15); do
    [ "$wake" = 1 ] && break
    sleep 1
  done
done
