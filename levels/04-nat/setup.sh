#!/usr/bin/env bash
# Seviye 4: Seviye 3'ün çalışır haline bir WAN bağlantısı ekler.
# Varsayılan: r1'de NAT KAPALI (Adım 1). --fixed: r1'de NAT açık.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

# Seviye 3'ü çalışır halde kur
"$DIR/../03-router/setup.sh" --fixed >/dev/null

# r1 <-> VM ("ISP") kablosu
ip link add host-r1 type veth peer name r1-wan
sysctl -qw net.ipv6.conf.host-r1.disable_ipv6=1
ip link set r1-wan netns r1
ip addr add 192.168.100.1/24 dev host-r1
ip link set host-r1 up
ip -n r1 addr add 192.168.100.2/24 dev r1-wan
ip -n r1 link set r1-wan up
ip -n r1 route add default via 192.168.100.1

# ISP tarafı: VM, 192.168.100.0/24'ü internete taşısın
sysctl -qw net.ipv4.ip_forward=1
WAN=$(ip route show default | awk '{print $5}')
iptables -t nat -C POSTROUTING -s 192.168.100.0/24 -o "$WAN" -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o "$WAN" -j MASQUERADE

if [[ "${1:-}" == "--fixed" ]]; then
  ip netns exec r1 iptables -t nat -A POSTROUTING -o r1-wan -j MASQUERADE
  echo "Hazır (NAT açık). Test: sudo ip netns exec pc1 ping -c 3 8.8.8.8"
else
  echo "Hazır (r1'de NAT kapalı). Adımlar için README'ye bak. NAT açık kurmak için: sudo ./setup.sh --fixed"
fi
