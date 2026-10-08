#!/usr/bin/env bash
# Seviye 1: iki namespace'i bir veth kablosuyla bağlar.
set -euo pipefail

ip netns add pc1
ip netns add pc2

ip link add veth-pc1 type veth peer name veth-pc2
ip link set veth-pc1 netns pc1
ip link set veth-pc2 netns pc2

ip -n pc1 addr add 10.0.0.1/24 dev veth-pc1
ip -n pc2 addr add 10.0.0.2/24 dev veth-pc2

ip -n pc1 link set veth-pc1 up
ip -n pc2 link set veth-pc2 up

echo "Hazır. Test: sudo ip netns exec pc1 ping -c 3 10.0.0.2"
