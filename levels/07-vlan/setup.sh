#!/usr/bin/env bash
# Seviye 7: VLAN, trunk ve router-on-a-stick.
#   sudo ./setup.sh           -> iki switch, 6 bilgisayar, VLAN 10/20, trunk. Herkes 10.0.0.0/24'te.
#   sudo ./setup.sh --router  -> ayrıca her VLAN'a ayrı subnet ve router-on-a-stick (r1).
#   sudo ./setup.sh --svi     -> her VLAN'a ayrı subnet; routing'i switch'in kendisi (sw1) yapar.
set -euo pipefail

noipv6() { sysctl -qw "net.ipv6.conf.$1.disable_ipv6=1"; }

# Switch'ler (VLAN farkında bridge)
for sw in sw1 sw2; do
  ip link add "$sw" type bridge vlan_filtering 1
  noipv6 "$sw"
  ip link set "$sw" up
done

# pc1-pc4 sw1'de, pc5-pc6 sw2'de
add_pc() {  # add_pc <no> <switch> <vlan>
  local i=$1 sw=$2 vid=$3
  ip netns add "pc$i"
  ip netns exec "pc$i" sysctl -qw net.ipv6.conf.all.disable_ipv6=1 net.ipv6.conf.default.disable_ipv6=1
  ip link add "veth-pc$i" type veth peer name "$sw-p$i"
  noipv6 "$sw-p$i"
  ip link set "veth-pc$i" netns "pc$i"
  ip link set "$sw-p$i" master "$sw"
  bridge vlan del dev "$sw-p$i" vid 1
  bridge vlan add dev "$sw-p$i" vid "$vid" pvid untagged     # access port
  ip link set "$sw-p$i" up
  ip -n "pc$i" addr add "10.0.0.$i/24" dev "veth-pc$i"
  ip -n "pc$i" link set "veth-pc$i" up
}
add_pc 1 sw1 10; add_pc 2 sw1 10; add_pc 3 sw1 20; add_pc 4 sw1 20
add_pc 5 sw2 10; add_pc 6 sw2 20

# sw1 <-> sw2 trunk
ip link add sw1-trunk type veth peer name sw2-trunk
for p in sw1-trunk sw2-trunk; do
  noipv6 "$p"
  ip link set "$p" master "${p%-trunk}"
  bridge vlan add dev "$p" vid 10
  bridge vlan add dev "$p" vid 20
  ip link set "$p" up
done

if [[ "${1:-}" == "--router" || "${1:-}" == "--svi" ]]; then
  # Her VLAN'a ayrı subnet: VLAN 10 -> 10.0.10.0/24, VLAN 20 -> 10.0.20.0/24
  for i in 1 2 5; do
    ip -n "pc$i" addr flush dev "veth-pc$i"
    ip -n "pc$i" addr add "10.0.10.1$i/24" dev "veth-pc$i"
    ip -n "pc$i" route add default via 10.0.10.1
  done
  for i in 3 4 6; do
    ip -n "pc$i" addr flush dev "veth-pc$i"
    ip -n "pc$i" addr add "10.0.20.1$i/24" dev "veth-pc$i"
    ip -n "pc$i" route add default via 10.0.20.1
  done
fi

if [[ "${1:-}" == "--svi" ]]; then
  # Multilayer switch: gateway'ler switch'in kendi üzerinde (SVI)
  for vid in 10 20; do
    bridge vlan add dev sw1 vid "$vid" self
    ip link add link sw1 name "sw1.$vid" type vlan id "$vid"
    ip addr add "10.0.$vid.1/24" dev "sw1.$vid"
    ip link set "sw1.$vid" up
  done
  sysctl -qw net.ipv4.ip_forward=1
  echo "Hazır (SVI). Test: sudo ip netns exec pc1 ping -c 2 10.0.20.16"
elif [[ "${1:-}" == "--router" ]]; then
  # Router-on-a-stick
  ip netns add r1
  ip netns exec r1 sysctl -qw net.ipv6.conf.all.disable_ipv6=1 net.ipv6.conf.default.disable_ipv6=1
  ip link add r1-eth0 type veth peer name sw1-p0
  noipv6 sw1-p0
  ip link set r1-eth0 netns r1
  ip link set sw1-p0 master sw1
  bridge vlan add dev sw1-p0 vid 10
  bridge vlan add dev sw1-p0 vid 20
  ip link set sw1-p0 up
  ip -n r1 link set r1-eth0 up
  ip -n r1 link add link r1-eth0 name r1-eth0.10 type vlan id 10
  ip -n r1 link add link r1-eth0 name r1-eth0.20 type vlan id 20
  ip -n r1 addr add 10.0.10.1/24 dev r1-eth0.10
  ip -n r1 addr add 10.0.20.1/24 dev r1-eth0.20
  ip -n r1 link set r1-eth0.10 up
  ip -n r1 link set r1-eth0.20 up
  ip netns exec r1 sysctl -qw net.ipv4.ip_forward=1
  echo "Hazır (router-on-a-stick). Test: sudo ip netns exec pc1 ping -c 2 10.0.20.16"
else
  echo "Hazır (VLAN + trunk). Test: sudo ip netns exec pc1 ping -c 2 10.0.0.5  /  10.0.0.6"
fi
