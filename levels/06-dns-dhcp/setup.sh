#!/usr/bin/env bash
# Seviye 6: Seviye 5'in ağında r1'i DHCP + DNS sunucusu yapar (dnsmasq).
# Varsayılan: pc1'in IP'si yok (Bölüm 1'in başlangıcı). --fixed: pc1 adresini DHCP ile de alır.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

command -v dnsmasq >/dev/null || { echo "dnsmasq gerekli: sudo apt install -y dnsmasq-base busybox"; exit 1; }
command -v busybox >/dev/null || { echo "busybox gerekli: sudo apt install -y dnsmasq-base busybox"; exit 1; }

"$DIR/../05-nat/setup.sh" --fixed >/dev/null

# pc1'in elle verilmiş ayarlarını sil
ip -n pc1 addr flush dev veth-pc1
ip -n pc1 route flush dev veth-pc1

# r1: DHCP + DNS sunucusu (arka planda)
ip netns exec r1 dnsmasq --user=root --group=root \
  --pid-file=/run/r1-dnsmasq.pid --log-facility=/tmp/r1-dnsmasq.log \
  --log-dhcp --log-queries \
  --interface=r1-eth1 --bind-interfaces \
  --no-resolv --server=8.8.8.8 \
  --host-record=pc2.lab,10.0.20.10 \
  --dhcp-range=10.0.10.100,10.0.10.150,1h \
  --dhcp-option=option:router,10.0.10.1 \
  --dhcp-option=option:dns-server,10.0.10.1 \
  --dhcp-leasefile=/tmp/r1.leases

if [[ "${1:-}" == "--fixed" ]]; then
  ip netns exec pc1 busybox udhcpc -i veth-pc1 -f -q -s "$DIR/udhcpc.sh"
  echo "Hazır. Test: sudo ip netns exec pc1 ping -4 -c 2 google.com"
else
  echo "Hazır: r1'de dnsmasq çalışıyor (log: /tmp/r1-dnsmasq.log), pc1'in adresi yok."
  echo "Adres almak için: sudo ip netns exec pc1 busybox udhcpc -i veth-pc1 -f -q -s $DIR/udhcpc.sh"
fi
