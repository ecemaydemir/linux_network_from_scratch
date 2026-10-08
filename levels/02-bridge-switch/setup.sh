#!/usr/bin/env bash
# Seviye 2: üç namespace'i bir Linux bridge (switch) üzerinden bağlar.
# Deneylerin temiz olması için IPv6 kapalı.
set -euo pipefail

ip link add br0 type bridge
sysctl -qw net.ipv6.conf.br0.disable_ipv6=1
ip link set br0 up

for i in 1 2 3; do
  ip netns add "pc$i"
  ip netns exec "pc$i" sysctl -qw net.ipv6.conf.all.disable_ipv6=1 net.ipv6.conf.default.disable_ipv6=1
  ip link add "veth-pc$i" type veth peer name "br-pc$i"
  sysctl -qw "net.ipv6.conf.br-pc$i.disable_ipv6=1"
  ip link set "veth-pc$i" netns "pc$i"
  ip link set "br-pc$i" master br0
  ip link set "br-pc$i" up
  ip -n "pc$i" addr add "10.0.0.$i/24" dev "veth-pc$i"
  ip -n "pc$i" link set "veth-pc$i" up
done

echo "Hazır. Test: sudo ip netns exec pc1 ping -c 1 10.0.0.3 && bridge fdb show br br0 | grep -v permanent"
