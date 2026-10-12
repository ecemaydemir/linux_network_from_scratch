#!/usr/bin/env bash
# Seviye 6 topolojisini siler: dnsmasq, pc1'in DNS ayarı, kira defteri ve Seviye 5.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"

[ -f /run/r1-dnsmasq.pid ] && kill "$(cat /run/r1-dnsmasq.pid)" 2>/dev/null
rm -f /run/r1-dnsmasq.pid /tmp/r1.leases /tmp/r1-dnsmasq.log
rm -rf /etc/netns/pc1

"$DIR/../05-nat/teardown.sh"
