#!/bin/sh
# DHCP istemcisinin (busybox udhcpc) sunucudan aldığı bilgileri uygulayan script.
# udhcpc bu script'i ortam değişkenleriyle çağırıyor:
#   $interface  arayüz adı       (veth-pc1)
#   $ip         verilen IP       (10.0.10.1xx)
#   $subnet     subnet maskesi   (255.255.255.0)
#   $router     default gateway  (10.0.10.1)
#   $dns        DNS sunucusu     (10.0.10.1)
#   $lease      kira süresi (sn)
#
# Yaptığı iş, Seviye 3'te elle yazdığım komutların aynısı:
#   ip addr add ... / ip route add default via ...

case "$1" in
  deconfig)
    ip addr flush dev "$interface"
    ;;
  bound|renew)
    echo "DHCP: $interface -> ip=$ip mask=$subnet router=$router dns=$dns lease=${lease}s"
    ip addr flush dev "$interface"
    ip addr add "$ip/$subnet" dev "$interface"
    [ -n "$router" ] && ip route replace default via "$router" dev "$interface"
    ;;
esac
exit 0
