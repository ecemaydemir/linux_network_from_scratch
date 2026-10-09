#!/usr/bin/env bash
# Seviye 3: iki subnet ve aralarında bir router namespace.
# Topoloji bilerek ÇALIŞMAYAN halde kuruluyor: gateway'ler yok, router'da iletim kapalı.
# Düzeltme adımları README'de.
set -euo pipefail

for n in pc1 pc2 r1; do
  ip netns add "$n"
  ip netns exec "$n" sysctl -qw net.ipv6.conf.all.disable_ipv6=1 net.ipv6.conf.default.disable_ipv6=1
done
ip netns exec r1 sysctl -qw net.ipv4.ip_forward=0

ip link add veth-pc1 type veth peer name r1-eth1
ip link set veth-pc1 netns pc1
ip link set r1-eth1 netns r1

ip link add veth-pc2 type veth peer name r1-eth2
ip link set veth-pc2 netns pc2
ip link set r1-eth2 netns r1

ip -n pc1 addr add 10.0.10.10/24 dev veth-pc1
ip -n r1  addr add 10.0.10.1/24  dev r1-eth1
ip -n r1  addr add 10.0.20.1/24  dev r1-eth2
ip -n pc2 addr add 10.0.20.10/24 dev veth-pc2

ip -n pc1 link set veth-pc1 up
ip -n r1  link set r1-eth1 up
ip -n r1  link set r1-eth2 up
ip -n pc2 link set veth-pc2 up

if [[ "${1:-}" == "--fixed" ]]; then
  ip -n pc1 route add default via 10.0.10.1
  ip -n pc2 route add default via 10.0.20.1
  ip netns exec r1 sysctl -qw net.ipv4.ip_forward=1
  echo "Hazır (çalışır halde). Test: sudo ip netns exec pc1 ping -c 3 10.0.20.10"
else
  echo "Hazır (bozuk halde). Adımlar için README'ye bak. Hepsi düzeltilmiş kurmak için: sudo ./setup.sh --fixed"
fi
