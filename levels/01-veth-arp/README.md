# Seviye 1: İki namespace, bir veth kablosu

## Topoloji

```
 ┌────────── pc1 ──────────┐          ┌────────── pc2 ──────────┐
 │ veth-pc1                │──────────│ veth-pc2                │
 │ 10.0.0.1/24             │   veth   │ 10.0.0.2/24             │
 │ MAC 1a:62:e6:01:a7:b8   │          │ MAC 6e:3e:bf:7b:d0:71   │
 └─────────────────────────┘          └─────────────────────────┘
```

- **Network namespace:** Kendi arayüzleri, IP adresleri, ARP ve routing tablosu olan yalıtılmış bir ağ ortamı. Burada her biri ayrı bir "bilgisayar" gibi davranıyor.
- **veth çifti:** İki ucu olan sanal bir kablo. Bir uçtan giren paket diğer uçtan çıkıyor.

MAC adresleri her kurulumda rastgele üretilir; yukarıdakiler benim çalıştırmamdaki değerler.

## Kurulum

```bash
sudo ./setup.sh
```

## Test

```bash
sudo ip netns exec pc2 tcpdump -i veth-pc2 -n -c 6 &
sudo ip netns exec pc1 ping -c 3 10.0.0.2
```

## Çıktı

tcpdump (pc2 tarafı, zaman damgasına göre sıralı):

```
11:06:37.601604 IP6 fe80::1862:e6ff:fe01:a7b8 > ff02::2: ICMP6, router solicitation, length 16
11:06:38.516640 ARP, Request who-has 10.0.0.2 tell 10.0.0.1, length 28
11:06:38.516730 ARP, Reply 10.0.0.2 is-at 6e:3e:bf:7b:d0:71, length 28
11:06:38.516735 IP 10.0.0.1 > 10.0.0.2: ICMP echo request, id 525, seq 1, length 64
11:06:38.516823 IP 10.0.0.2 > 10.0.0.1: ICMP echo reply, id 525, seq 1, length 64
11:06:38.622273 IP6 fe80::6c3e:bfff:fe7b:d071 > ff02::2: ICMP6, router solicitation, length 16
```

ping (pc1 tarafı):

```
64 bytes from 10.0.0.2: icmp_seq=1 ttl=64 time=0.255 ms
64 bytes from 10.0.0.2: icmp_seq=2 ttl=64 time=0.077 ms
64 bytes from 10.0.0.2: icmp_seq=3 ttl=64 time=0.071 ms

3 packets transmitted, 3 received, 0% packet loss
```

## Gözlemler

### 1. ARP, ilk paketten önce çalışıyor
pc1, 10.0.0.2'ye paket göndermeden önce hedefin MAC adresini bilmek zorunda. Önce broadcast ile `who-has 10.0.0.2` diye soruyor, pc2 kendi MAC adresiyle cevap veriyor ve ICMP paketi ancak bundan sonra gidiyor.

### 2. İlk ping yaklaşık 3 kat daha yavaş
`seq=1` 0.255 ms, sonrakiler yaklaşık 0.07 ms. Aradaki fark ARP çözümlemesinin süresi. Cevap pc1'in ARP tablosunda saklandığı için sonraki ping'lerde ARP tekrarlanmıyor:

```bash
sudo ip -n pc1 neigh              # pc2'nin MAC adresi tabloda
sudo ip -n pc1 neigh flush all    # tablo temizlenince ARP tekrar görünüyor
```

### 3. Benim göndermediğim paketler: IPv6 router solicitation
Arayüzler `up` olunca Linux, MAC adresinden **EUI-64** yöntemiyle otomatik bir IPv6 link-local adresi üretiyor ve ağda router olup olmadığını soruyor (`ff02::2` = tüm router'lar multicast adresi).

| | pc1 | pc2 |
|---|---|---|
| MAC | `1a:62:e6:01:a7:b8` | `6e:3e:bf:7b:d0:71` |
| Link-local | `fe80::1862:e6ff:fe01:a7b8` | `fe80::6c3e:bfff:fe7b:d071` |

MAC ortadan ikiye bölünüp araya `ff:fe` ekleniyor ve ilk baytın 7. biti (U/L biti) çevriliyor: `1a` → `18`, `6e` → `6c`.

### 4. TTL 64 ve hiç azalmıyor
Linux paketleri varsayılan olarak TTL 64 ile gönderiyor. Arada router olmadığı için değer değişmedi. Seviye 3'te araya router girdiğinde 63'e düşmesi beklenir.

## Karşılaşılan sorunlar

**`Cannot find device "veth-pc2"`**
`sudo ip -n pc1 addr add ... dev veth-pc2` komutu hata verdi, çünkü veth-pc2 artık pc2 namespace'inde. Her namespace yalnızca kendi arayüzlerini görebiliyor. Doğrusu `ip -n pc2 ...`.

**Yanlış IP verildiğinde `addr add` yetmiyor**
Linux'ta `ip addr add` mevcut adresin üzerine yazmıyor, arayüze ek bir adres daha ekliyor. Yanlış adresi önce silmek gerekiyor:

```bash
sudo ip -n pc1 addr del 10.0.0.2/24 dev veth-pc1
sudo ip -n pc1 addr add 10.0.0.1/24 dev veth-pc1
```

Cisco IOS'ta ise `ip address` komutu eski adresi değiştiriyor (secondary eklemek için ayrıca `secondary` anahtar kelimesi gerekiyor).

## Temizlik

```bash
sudo ./teardown.sh
```

Namespace silinince içindeki veth ucu da siliniyor; veth bir çift olduğu için diğer uç da otomatik olarak yok oluyor.
