# Seviye 6: DHCP ve DNS

> **Benzetme:** r1 bir otel.
> **Resepsiyon (DHCP)** oda numarası verir, **danışma masası (DNS)** isimleri adrese çevirir, **çıkış kapısı (gateway)** dışarıya açılır.
> Üçü de aynı binada: `10.0.10.1`. Hangisine gittiğini kapı numarası (port) belirler: DHCP 67, DNS 53.

## Kurulum

```bash
sudo apt install -y dnsmasq-base busybox
sudo ./setup.sh          # r1'de dnsmasq çalışır, pc1'in IP'si yok
sudo ./setup.sh --fixed  # pc1 adresini DHCP ile de alır
```

`dnsmasq` r1'de DHCP + DNS sunucusu, `busybox udhcpc` pc1'de DHCP istemcisi.

---

## 1. DHCP: odanı resepsiyondan al

Seviye 3'te pc1'in IP'sini ve gateway'ini **elle** yazmıştım. DHCP bunları otomatik dağıtıyor.

| Adım | Paket | Otelde |
|---|---|---|
| **D**iscover | pc1 → herkese | "Resepsiyon nerede? Oda lazım!" |
| **O**ffer | r1 → pc1 | "146 boş, ister misin?" |
| **R**equest | pc1 → herkese | "146'yı alıyorum!" |
| **A**ck | r1 → pc1 | "Tamam, 1 saatliğine senin." |

```bash
sudo ip -n pc1 addr flush dev veth-pc1      # pc1'in ayarlarını sil
sudo ip netns exec pc1 busybox udhcpc -i veth-pc1 -f -q -s ./udhcpc.sh
```

**Sonuç:** hiçbir şey yazmadan pc1 her şeyi aldı.

```
udhcpc: lease of 10.0.10.146 obtained from 10.0.10.1, lease time 3600
$ ip -n pc1 addr   →  inet 10.0.10.146/24
$ ip -n pc1 route  →  default via 10.0.10.1
```

**Gözlemler**
- **`0.0.0.0 → 255.255.255.255`:** Request paketinde pc1'in henüz adresi yok ("odasız misafir") ve resepsiyonun yerini bilmiyor ("herkese bağır").
- **İki Discover:** İlk Discover'a 3 saniyede cevap gelmeyince pc1 tekrar sordu. DHCP UDP kullandığı için tekrar denemek istemcinin işi ([Seviye 4](../04-tcp-udp/)).
- **Kira:** Adres 1 saatliğine verildi. Yarı sürede (30 dk) uzatma istenir; otelde "bir gece daha kalabilir miyim?" demek gibi.

<details>
<summary>Ayrıntılı çıktılar (tcpdump, dnsmasq log'u, kira defteri)</summary>

```
# tcpdump (r1-eth1), kısaltılmış
10.0.10.1.67 > 10.0.10.146.68: BOOTP/DHCP, Reply, xid 0xa824ae4f, secs 3
        DHCP-Message (53): Offer
        Lease-Time (51): 3600   RN (58): 1800   RB (59): 3150
        Subnet-Mask (1): 255.255.255.0
        Default-Gateway (3): 10.0.10.1
0.0.0.0.68 > 255.255.255.255.67: BOOTP/DHCP, Request from 36:32:83:d0:68:dd, xid 0xa824ae4f, secs 3
        DHCP-Message (53): Request
        Requested-IP (50): 10.0.10.146
10.0.10.1.67 > 10.0.10.146.68: BOOTP/DHCP, Reply, xid 0xa824ae4f, secs 3
        DHCP-Message (53): ACK

# dnsmasq log'u
DHCPDISCOVER(r1-eth1) 36:32:83:d0:68:dd
DHCPOFFER(r1-eth1) 10.0.10.146 36:32:83:d0:68:dd
DHCPDISCOVER(r1-eth1) 36:32:83:d0:68:dd
DHCPOFFER(r1-eth1) 10.0.10.146 36:32:83:d0:68:dd
DHCPREQUEST(r1-eth1) 10.0.10.146 36:32:83:d0:68:dd
DHCPACK(r1-eth1) 10.0.10.146 36:32:83:d0:68:dd

# kira defteri: bitiş zamanı, MAC, verilen IP
$ cat /tmp/r1.leases
1791800894 36:32:83:d0:68:dd 10.0.10.146 * 01:36:32:83:d0:68:dd
```

- `xid`: konuşmanın numarası; otelde rezervasyon numarası gibi.
- `RN` / `RB`: kiranın %50'sinde ve %87.5'inde yenileme denemeleri.
- CCNA notu: broadcast router'dan geçmez. DHCP sunucusu başka subnet'teyse router'da `ip helper-address` gerekir. Burada sunucu aynı subnet'te.

</details>

---

## 2. DNS: rehberden numarayı bul

> **Benzetme:** Telefon rehberi. "google.com" ismini "192.178.24.174" numarasına çevirir.

| Bu lab | Otelde |
|---|---|
| pc1 | Soru soran misafir |
| r1 (dnsmasq, port 53) | Danışma masası |
| `--host-record=pc2.lab,10.0.20.10` | Danışmanın kendi listesi |
| 8.8.8.8 | Danışmanın bilmediğinde aradığı merkez |

pc1 danışmanın yerini **DHCP'den** öğrendi (`dns=10.0.10.1`).

```
$ ping -4 pc2.lab     →  PING pc2.lab (10.0.20.10) ... ttl=63 time=0.173 ms
$ ping -4 google.com  →  PING google.com (192.178.24.174) ... ttl=108 time=46.3 ms
```

**r1'de ne oldu?**

| | pc2.lab | google.com |
|---|---|---|
| Kim bildi? | Danışman (kendi listesi) | Merkez (8.8.8.8) |
| r1 internete çıktı mı? | Hayır | Evet |
| Cevap süresi | 1.6 ms | 59 ms |

**Gözlemler**
- **DNS forwarding:** google.com'u 8.8.8.8'e **pc1 değil, r1 sordu**. Google pc1'i hiç görmedi; tıpkı merkezin, danışmaya soru soran misafiri tanımaması gibi.
- **Önbellek ve TTL:** Danışman cevapları not defterine yazıyor, ama her notun bir son kullanma süresi var. 6.5 dakika sonra google.com'un notu dolmuştu (yeniden soruldu), "bu IP kimin?" notu dolmamıştı (önbellekten 0.1 ms'de geldi).
- **Sızıntı:** Rehberde pc2.lab'ın IPv6 kaydı yoktu, dnsmasq bunu da 8.8.8.8'e sordu ("böyle bir isim yok" cevabı geldi). İç dahili numarayı Bilinmeyen Numaralar'a sormak gibi; gerçek ağda `--local=/lab/` ile engellenir.

<details>
<summary>Ayrıntılı çıktılar ve DNS satırlarını okuma</summary>

```
# pc2.lab: cevap r1'in kendi listesinden (sadece r1-eth1)
r1-eth1 In  IP 10.0.10.146.43734 > 10.0.10.1.53: 4000+ A? pc2.lab. (25)
r1-eth1 Out IP 10.0.10.1.53 > 10.0.10.146.43734: 4000* 1/0/0 A 10.0.20.10 (41)

# google.com: r1 merkeze soruyor (r1-wan)
r1-eth1 In  IP 10.0.10.146.49741 > 10.0.10.1.53: 13158+ A? google.com. (28)
r1-wan Out IP 192.168.100.2.51258 > 8.8.8.8.53: 40649+ [1au] A? google.com. (39)
r1-wan In  IP 8.8.8.8.53 > 192.168.100.2.51258: 40649 1/0/1 A 192.178.24.174 (55)
r1-eth1 Out IP 10.0.10.1.53 > 10.0.10.146.49741: 13158 1/0/0 A 192.178.24.174 (44)

# dnsmasq log'u
query[A] pc2.lab from 10.0.10.146
config pc2.lab is 10.0.20.10
query[A] google.com from 10.0.10.146
forwarded google.com to 8.8.8.8
reply google.com is 192.178.24.174
```

| Parça | Anlamı |
|---|---|
| `4000` | Sorunun numarası (bankadaki sıra numarası gibi); cevap aynı numarayla gelir |
| `A?` / `AAAA?` / `PTR?` | IPv4 adresi ne? / IPv6 adresi ne? / Bu IP kimin? |
| `*` | "Bu bilgi benim kendi kaydım" |
| `1/0/0` | İlk sayı: kaç cevap var |
| `NXDomain` | "Böyle bir isim yok" |

Tek bir `ping` üç soru sordurdu: `A?`, `AAAA?` ve ekranda ismi yazabilmek için `PTR?`. PTR'de adres tersten yazılıyor: `10.0.20.10` → `10.20.0.10.in-addr.arpa`.

</details>

---

## 3. "It's always DNS"

dnsmasq'ı durdurdum (pc1'in adresi kaybolmadı, kira 1 saatlik):

| Komut | Sonuç |
|---|---|
| `ping 8.8.8.8` | ✅ Çalıştı |
| `ping google.com` | ❌ `Temporary failure in name resolution` |

> **Benzetme:** Telefon hattın çalışıyor ama rehberin kayboldu. Numarasını ezbere bildiğini arayabilirsin, "Annem"i arayamazsın.

**Teşhis:** Önce IP ile dene, sonra isimle. Biri çalışıp diğeri çalışmıyorsa sorun DNS'te.

r1, 53. portta kimse dinlemediği için her soruya `ICMP udp port 53 unreachable` ("danışma kapalı" tabelası) ile cevap verdi; [Seviye 4'teki kapalı port](../04-tcp-udp/README.md#deney-3-kapalı-bir-porta-bağlanmak) deneyinin aynısı. pc1 bu tabelayı görünce 1 ms içinde vazgeçti.

<details>
<summary>Ayrıntılı çıktı</summary>

```
r1-eth1 In  IP 10.0.10.146.43078 > 10.0.10.1.53: 32952+ A? google.com. (28)
r1-eth1 Out IP 10.0.10.1 > 10.0.10.146: ICMP 10.0.10.1 udp port 53 unreachable, length 64
r1-eth1 In  IP 10.0.10.146.43078 > 10.0.10.1.53: 14013+ AAAA? google.com. (28)
r1-eth1 Out IP 10.0.10.1 > 10.0.10.146: ICMP 10.0.10.1 udp port 53 unreachable, length 64
(pc1 bir kez daha denedi, aynı cevap)
```

</details>

---

## Büyük resim: `ping google.com`

| Adım | Ne oldu | Seviye |
|---|---|---|
| 1 | pc1 adresini, gateway'i ve DNS sunucusunu DHCP ile aldı | 6 |
| 2 | "google.com kim?" diye r1'e sordu, r1 de 8.8.8.8'e | 6 |
| 3 | Paketi gateway'e (r1) verdi, önce ARP ile MAC'ini öğrendi | 3, 1 |
| 4 | r1 kaynak adresi NAT ile değiştirip internete çıkardı | 5 |

## Docker'da karşılığı

- **Docker DHCP kullanmıyor.** Odaları misafir gelmeden kendisi atayan bir otel gibi: IP'yi container oluşturulurken kendisi veriyor (IPAM).
- **Docker'ın kendi danışma masası var:** `docker network create` ile kurulan ağlarda container'lar `127.0.0.11`'e soruyor. Container isimlerini kendisi çözüyor (`ping db`), bilmediğini host'un DNS'ine soruyor. Buradaki dnsmasq'ın aynısı.
- Container içinde `Temporary failure in name resolution` çok yaygın; teşhis yukarıdakiyle aynı.
- Kubernetes'te bu rolü **CoreDNS** üstleniyor.

## Temizlik

```bash
sudo ./teardown.sh
```
