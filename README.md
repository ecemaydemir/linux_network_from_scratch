# Linux'ta Sıfırdan Ağ

Docker, Kubernetes ve cloud ağlarının altında yatan Linux yapı taşlarını (network namespace, veth, bridge, routing, iptables) hiçbir hazır araç kullanmadan elle kurup gözlemlediğim bir lab serisi.

Amaç, CCNA çalışırken öğrendiğim kavramların (ARP, switching, VLAN, default gateway, NAT, ACL) Linux'ta nasıl karşılık bulduğunu görmek ve sonunda Docker'ın arka planda tam olarak ne yaptığını kendi kurduğum ağla karşılaştırmak.

## Ortam

- macOS üzerinde OrbStack ile Ubuntu (arm64) sanal makinesi
- Araçlar: `iproute2`, `tcpdump`

## Seviyeler

| # | Konu | CCNA karşılığı | Durum |
|---|------|----------------|-------|
| 1 | [İki namespace, bir veth kablosu](levels/01-veth-arp/) | Aynı subnet, ARP | ✅ |
| 2 | [Linux bridge ile switch](levels/02-bridge-switch/) | MAC öğrenme, flooding, switching | ✅ |
| 3 | İki subnet ve router namespace | Default gateway, inter-VLAN routing | ⏳ |
| 4 | İnternete çıkış | NAT / PAT | ⏳ |
| 5 | Firewall ve port yönlendirme | ACL, static NAT | ⏳ |
| 6 | Tüm topolojiyi script'e dökmek | Tekrarlanabilir altyapı | ⏳ |
| 7 | Docker ile karşılaştırma | — | ⏳ |

Her seviyenin klasöründe kurulum (`setup.sh`) ve temizlik (`teardown.sh`) script'leri, topoloji ve gözlem notları bulunuyor.

## Çalıştırma

```bash
cd levels/01-veth-arp
sudo ./setup.sh      # topolojiyi kurar
sudo ./teardown.sh   # her şeyi siler
```
