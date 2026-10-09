# Seviye 3: İki subnet ve aralarında router

## Topoloji

```
   pc1                      r1 (router)                     pc2
10.0.10.10  ──────  10.0.10.1   │   10.0.20.1  ──────  10.0.20.10
            veth     r1-eth1    │    r1-eth2     veth
  Satış ağı: 10.0.10.0/24                  Sunucu ağı: 10.0.20.0/24
```

Router da bir network namespace. Onu router yapan şey iki farklı ağa birer ayağının olması ve paketleri bir ayağından diğerine iletmesine izin verilmesi.

## Kurulum

`setup.sh` topolojiyi **çalışmayan** halde kuruyor: gateway'ler yok ve router'da iletim kapalı. Aşağıdaki adımlar onu tek tek düzeltiyor.

```bash
sudo ./setup.sh
```

İki terminal kullandım: Pencere A'da router'ın içini dinledim, Pencere B'de trafik ürettim.

```bash
# Pencere A: router'a giren ve çıkan her ICMP paketini, kart ve yön bilgisiyle göster
sudo ip netns exec r1 tcpdump -n -i any icmp
```

## Adım 1: Gateway yok → paket hiç çıkmıyor

```
$ sudo ip netns exec pc1 ping -c 2 10.0.20.10
ping: connect: Network is unreachable

$ sudo ip -n pc1 route
10.0.10.0/24 dev veth-pc1 proto kernel scope link src 10.0.10.10
```

pc1'in routing tablosunda yalnızca kendi ağı var. Bu satırı ben eklemedim; karta IP verildiği anda çekirdek ekledi (`proto kernel`). 10.0.20.10 bu ağda değil ve "bilmediğim adresleri şuraya gönder" diyen bir satır da yok. Paket gönderilmeden reddediliyor.

### Cisco ile karşılaştırma

| Cisco `show ip route` | Anlamı | Linux |
|---|---|---|
| **C** 10.0.10.0/24 | Doğrudan bağlı ağ | `ip route` → `10.0.10.0/24 dev veth-pc1 proto kernel` |
| **L** 10.0.10.10/32 | Cihazın kendi adresi | `ip route show table local` → `local 10.0.10.10 dev veth-pc1` |
| **S\*** 0.0.0.0/0 | Default route | `ip route` → `default via 10.0.10.1` |

Linux, L satırlarını ana tabloda değil ayrı bir `local` tablosunda tutuyor:

```
$ sudo ip -n pc1 route show table local
local 10.0.10.10 dev veth-pc1 proto kernel scope host src 10.0.10.10
broadcast 10.0.10.255 dev veth-pc1 proto kernel scope link src 10.0.10.10
```

## Adım 2: pc1'e gateway → paket router'da kayboluyor

```bash
sudo ip -n pc1 route add default via 10.0.10.1
```

```
$ sudo ip netns exec pc1 ping -c 3 10.0.20.10
3 packets transmitted, 0 received, 100% packet loss
```

Hata türü değişti: `Network is unreachable` yerine paketler artık **gönderiliyor** ama cevap gelmiyor. Router'da yakalanan (ping id 725):

```
09:26:16.173784 r1-eth1 In  IP 10.0.10.10 > 10.0.20.10: ICMP echo request, id 725, seq 1, length 64
09:26:17.221653 r1-eth1 In  IP 10.0.10.10 > 10.0.20.10: ICMP echo request, id 725, seq 2, length 64
09:26:18.242596 r1-eth1 In  IP 10.0.10.10 > 10.0.20.10: ICMP echo request, id 725, seq 3, length 64
```

Paketler router'a giriyor (`r1-eth1 In`) ama `r1-eth2`'den hiç çıkmıyor.

**Sebep:** Router'ı bilerek `net.ipv4.ip_forward=0` ile kurdum. Linux varsayılan olarak bir bilgisayar gibi davranıyor: kendisine gelmeyen bir paketi başka bir karta iletmiyor, atıyor. Router'ın kendi routing tablosunda iki ağ da mevcut, yani yolu biliyor, ama iletmesine izin yok:

```
$ sudo ip -n r1 route
10.0.10.0/24 dev r1-eth1 proto kernel scope link src 10.0.10.1
10.0.20.0/24 dev r1-eth2 proto kernel scope link src 10.0.20.1
```

Bu, Cisco multilayer switch'te `ip routing` komutunun karşılığı. [Kampüs projemde](https://github.com/ecemaydemir/campus_network_design) de SVI'lar kurulu olsa bile `ip routing` olmadan VLAN'lar arası trafik geçmiyordu.

## Adım 3: Router'da iletimi aç → cevap gelmiyor

```bash
sudo ip netns exec r1 sysctl -w net.ipv4.ip_forward=1
```

Router'da yakalanan (ping id 751):

```
09:27:55.525456 r1-eth1 In  IP 10.0.10.10 > 10.0.20.10: ICMP echo request, id 751, seq 1, length 64
09:27:55.525819 r1-eth2 Out IP 10.0.10.10 > 10.0.20.10: ICMP echo request, id 751, seq 1, length 64
09:27:56.545474 r1-eth1 In  IP 10.0.10.10 > 10.0.20.10: ICMP echo request, id 751, seq 2, length 64
09:27:56.545592 r1-eth2 Out IP 10.0.10.10 > 10.0.20.10: ICMP echo request, id 751, seq 2, length 64
...
```

Router artık paketi iletiyor (`r1-eth2 Out`), ama hiç **echo reply** yok.

**Sebep:** pc2'nin de dönüş yolu yok.

```
$ sudo ip -n pc2 route
10.0.20.0/24 dev veth-pc2 proto kernel scope link src 10.0.20.10
```

pc2 isteği aldı, ama cevabı 10.0.10.10'a göndermek istediğinde Adım 1'de pc1'in yaşadığı durumun aynısını yaşıyor. Bu sefer hata ekranda görünmüyor, çünkü ping'i pc2 başlatmadı; cevap sessizce gönderilmiyor.

## Adım 4: pc2'ye gateway → çalışıyor

```bash
sudo ip -n pc2 route add default via 10.0.20.1
```

```
$ sudo ip netns exec pc1 ping -c 3 10.0.20.10
64 bytes from 10.0.20.10: icmp_seq=1 ttl=63 time=0.177 ms
64 bytes from 10.0.20.10: icmp_seq=2 ttl=63 time=0.234 ms
64 bytes from 10.0.20.10: icmp_seq=3 ttl=63 time=0.250 ms

3 packets transmitted, 3 received, 0% packet loss
```

Router'da bir ping'in tam turu (id 791):

```
09:29:49.769053 r1-eth1 In  IP 10.0.10.10 > 10.0.20.10: ICMP echo request, id 791, seq 1, length 64
09:29:49.769144 r1-eth2 Out IP 10.0.10.10 > 10.0.20.10: ICMP echo request, id 791, seq 1, length 64
09:29:49.769202 r1-eth2 In  IP 10.0.20.10 > 10.0.10.10: ICMP echo reply, id 791, seq 1, length 64
09:29:49.769208 r1-eth1 Out IP 10.0.20.10 > 10.0.10.10: ICMP echo reply, id 791, seq 1, length 64
```

## Özet

| Ping | Durum | Router'da görünen | Sonuç |
|---|---|---|---|
| — | pc1'de gateway yok | Hiçbir şey | `Network is unreachable` |
| id 725 | `ip_forward=0` | Sadece `eth1 In` | %100 kayıp |
| id 751 | `ip_forward=1`, pc2'de gateway yok | `eth1 In` → `eth2 Out` | %100 kayıp |
| id 791 | Her şey tamam | `In` → `Out` → `In` → `Out` | %0 kayıp, `ttl=63` |

## Gözlemler

### 1. TTL, router başına bir azalıyor
Seviye 1 ve 2'de `ttl=64` idi, burada `ttl=63`. Ping çıktısında görünen, **cevap** paketinin TTL'i: pc2 cevabı 64 ile gönderdi, router iletirken 1 azalttı. `traceroute` bu mekanizmayı kullanıyor: TTL'i 1, 2, 3... ile gönderip yoldaki her router'ın "TTL bitti" mesajını topluyor.

### 2. Router IP adreslerine dokunmuyor
Paketin kaynağı router'ın her iki tarafında da 10.0.10.10, hedefi 10.0.20.10. Router yalnızca hangi karttan çıkacağına karar veriyor. Seviye 4'te NAT eklendiğinde bu değişecek.

### 3. Hata mesajı, sorunun nerede olduğunu söylüyor
- `Network is unreachable`: sorun **göndericide**, paket hiç çıkmadı.
- `100% packet loss`: paket çıktı ama yolda bir yerde kayboldu. Nerede olduğunu bulmak için yol boyunca dinlemek gerekiyor.

### 4. Routing iki yönlü
Gidiş yolunun çalışması yeterli değil. Ağdaki her cihaz cevabı nereye göndereceğini de bilmeli. "Paket gidiyor ama cevap gelmiyor" durumunun en yaygın sebebi, karşı tarafta eksik bir route.

## Temizlik

```bash
sudo ./teardown.sh
```
