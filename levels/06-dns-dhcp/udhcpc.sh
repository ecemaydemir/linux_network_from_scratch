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
# DNS sunucusunu da bu namespace'e özel resolv.conf'a yazıyor:
#   /etc/netns/<namespace>/resolv.conf
# `ip netns exec` bu dosyayı namespace içinde /etc/resolv.conf olarak gösteriyor.
# (VM'in kendi /etc/resolv.conf dosyasına dokunmuyor.)

case "$1" in
  deconfig)
    ip addr flush dev "$interface"
    ;;
  bound|renew)
    echo "DHCP: $interface -> ip=$ip mask=$subnet router=$router dns=$dns lease=${lease}s"
    ip addr flush dev "$interface"
    ip addr add "$ip/$subnet" dev "$interface"
    [ -n "$router" ] && ip route replace default via "$router" dev "$interface"
    if [ -n "$dns" ]; then
      ns=$(ip netns identify 2>/dev/null)
      if [ -n "$ns" ]; then
        mkdir -p "/etc/netns/$ns"
        : > "/etc/netns/$ns/resolv.conf"
        for s in $dns; do echo "nameserver $s" >> "/etc/netns/$ns/resolv.conf"; done
        echo "DNS: /etc/netns/$ns/resolv.conf -> $dns"
      fi
    fi
    ;;
esac
exit 0
