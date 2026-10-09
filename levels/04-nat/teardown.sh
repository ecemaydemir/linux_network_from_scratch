#!/usr/bin/env bash
# Seviye 4 topolojisini siler: VM'deki NAT kuralı, WAN kablosu ve Seviye 3 namespace'leri.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"

WAN=$(ip route show default | awk '{print $5}')
iptables -t nat -D POSTROUTING -s 192.168.100.0/24 -o "$WAN" -j MASQUERADE 2>/dev/null || true
ip link del host-r1 2>/dev/null || true

"$DIR/../03-router/teardown.sh" >/dev/null
echo "Temizlendi."
