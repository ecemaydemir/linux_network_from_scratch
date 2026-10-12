# Linux'ta Sıfırdan Ağ

Docker, Kubernetes ve cloud ağlarının altında yatan Linux yapı taşlarını (network namespace, veth, bridge, routing, iptables) hiçbir hazır araç kullanmadan elle kurup gözlemlediğim bir lab serisi.

Amaç, CCNA çalışırken öğrendiğim kavramların (ARP, switching, VLAN, default gateway, NAT, ACL) Linux'ta nasıl karşılık bulduğunu görmek ve her adımda Docker'ın arka planda tam olarak ne yaptığını kendi kurduğum ağla karşılaştırmak.

## Ortam

- macOS üzerinde OrbStack ile Ubuntu (arm64) sanal makinesi
- Araçlar: `iproute2`, `tcpdump`, `netcat`, `iptables`, `conntrack`

## Seviyeler

| # | Konu | CCNA karşılığı | Durum |
|---|------|----------------|-------|
| 1 | [İki namespace, bir veth kablosu](levels/01-veth-arp/) | Aynı subnet, ARP | ✅ |
| 2 | [Linux bridge ile switch](levels/02-bridge-switch/) | MAC öğrenme, flooding, switching | ✅ |
| 3 | [İki subnet ve router namespace](levels/03-router/) | Routing tablosu, default gateway, `ip routing`, TTL | ✅ |
| 4 | [TCP ve UDP](levels/04-tcp-udp/) | 3-way handshake, ACK, RST, port, UDP | ✅ |
| 5 | [İnternete çıkış](levels/05-nat/) | Private IP, NAT, PAT (overload), NAT tablosu | ✅ |
| 6 | DNS ve DHCP | DORA, lease, isim çözümleme | ⏳ |
| 7 | Firewall ve port yönlendirme | ACL, static NAT | ⏳ |
| 8 | Tüm topolojiyi script'e dökmek | Tekrarlanabilir altyapı | ⏳ |
| 9 | Docker ile karşılaştırma | — | ⏳ |
| + | VLAN (802.1Q) | VLAN, trunk, access port | ⏳ |

Her seviyenin klasöründe kurulum (`setup.sh`) ve temizlik (`teardown.sh`) script'leri, topoloji, gözlem notları ve o seviyenin **Docker'daki karşılığı** bulunuyor.

## Docker ile bağlantı

Bir Docker container'ı, ağ açısından bakıldığında bu projede kurduğum "bilgisayarlardan" (network namespace) biri. Docker'ın ağ katmanı, aşağıdaki yapı taşlarını otomatik olarak kuruyor:

| Seviye | Linux yapı taşı | Docker'daki karşılığı |
|---|---|---|
| 1 | network namespace + veth | Her container + içindeki `eth0` |
| 2 | Linux bridge | `docker0` ve her `docker network create` |
| 3 | Router, `ip_forward`, default gateway | Host, container'ların gateway'i (`172.17.0.1`) |
| 4 | TCP/UDP portları | `-p 8080:80` (TCP), `-p 53:53/udp` |
| 5 | `MASQUERADE` | Container'ların internete çıkışı |
| 6 | DNS | Container'ların birbirini isimle bulması |
| 7 | iptables, DNAT | Port yayınlama, ağ izolasyonu |

## Çalıştırma

```bash
cd levels/01-veth-arp
sudo ./setup.sh      # topolojiyi kurar
sudo ./teardown.sh   # her şeyi siler
```
