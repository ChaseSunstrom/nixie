# Bring a WireGuard or NordVPN exit up (or down): its interface, marked so its
# own packets leave directly, and a default route in the exit's table. The
# secret arrives as a credential. usage: nixie-exit-up up|down <name>
set -euo pipefail
umask 077
cfg=${NIXIE_EGRESS:-/etc/nixie/egress.json}
action=$1
name=$2
x() { jq -r --arg n "$name" ".exits[\$n].$1" "$cfg"; }
type=$(x type)
iface=$(x iface)
table=$(x table)
mark=$(jq -r .wgMark "$cfg")
dir=${RUNTIME_DIRECTORY:-/run/nixie-exit-$name}
ip link del "$iface" 2>/dev/null || true
[ "$action" = up ] || exit 0

conf=$dir/wg.conf
addr=""
dns=""
case $type in
  wireguard)
    src=$CREDENTIALS_DIRECTORY/secret
    # wg-quick's own keys are not wg's; the addresses and resolvers are.
    addr=$(sed -n 's/^[[:space:]]*Address[[:space:]]*=[[:space:]]*//Ip' "$src" | tr ',' ' ')
    dns=$(sed -n 's/^[[:space:]]*DNS[[:space:]]*=[[:space:]]*//Ip' "$src" | tr ',' ' ')
    grep -viE '^[[:space:]]*(Address|DNS|MTU|Table|PreUp|PostUp|PreDown|PostDown|SaveConfig)[[:space:]]*=' "$src" >"$conf"
    ;;
  nordvpn)
    api=$(jq -r .nordApi "$cfg")
    token=$(tr -d '[:space:]' <"$CREDENTIALS_DIRECTORY/secret")
    key=$(curl -fsS --max-time 20 -u "token:$token" "$api/v1/users/services/credentials" | jq -r .nordlynx_private_key)
    filter='filters[servers_technologies][identifier]=wireguard_udp'
    country=$(x country)
    if [ -n "$country" ]; then
      id=$(curl -fsS --max-time 20 "$api/v1/servers/countries" | jq -r --arg c "${country^^}" '.[] | select(.code == $c) | .id')
      [ -n "$id" ] || { echo "NordVPN has no country $country" >&2; exit 1; }
      filter="$filter&filters[country_id]=$id"
    fi
    server=$(curl -fsSg --max-time 20 "$api/v1/servers/recommendations?$filter&limit=1")
    station=$(jq -r '.[0].station' <<<"$server")
    public=$(jq -r '.[0].technologies[] | select(.identifier == "wireguard_udp") | .metadata[] | select(.name == "public_key") | .value' <<<"$server")
    [ -n "$key" ] && [ "$key" != null ] && [ -n "$public" ] || { echo "NordVPN gave no server or key; is the token right?" >&2; exit 1; }
    printf '[Interface]\nPrivateKey = %s\n[Peer]\nPublicKey = %s\nEndpoint = %s:51820\nAllowedIPs = 0.0.0.0/0, ::/0\n' "$key" "$public" "$station" >"$conf"
    # NordLynx gives every client this address; its resolvers are Nord's.
    addr=10.5.0.2/32
    dns="103.86.96.100 103.86.99.100"
    jq -r '.[0].hostname' <<<"$server" >"$dir/server"
    ;;
  *)
    echo "exit $name is a $type exit, which has no interface" >&2
    exit 1
    ;;
esac

ip link add "$iface" type wireguard
wg setconf "$iface" "$conf"
rm -f "$conf"
wg set "$iface" fwmark "$mark"
# A handshake every 25 s is how the watcher tells a live exit from a dead one.
for peer in $(wg show "$iface" peers); do wg set "$iface" peer "$peer" persistent-keepalive 25; done
for a in $addr; do ip addr add "$a" dev "$iface"; done
ip link set "$iface" up
ip route replace default dev "$iface" table "$table"
ip -6 route replace default dev "$iface" table "$table" 2>/dev/null || true
# shellcheck disable=SC2086 # one resolver per line
printf '%s\n' $dns >"$dir/dns"
echo "exit $name up on $iface"
