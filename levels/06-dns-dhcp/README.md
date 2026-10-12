# Seviye 6: DHCP ve DNS

Seviye 5'teki internete çıkan ağda, router'ı (r1) bir ev modemi gibi çalıştırdım: aynı cihaz hem gateway, hem DHCP sunucusu, hem DNS sunucusu.

```
                 r1 = 10.0.10.1
       ┌─────────────────────────────────┐
pc1 ── │ gateway   (paketleri iletir)    │ ── internet
       │ DHCP      (UDP 67, adres dağıtır)│
       │ DNS       (UDP 53, isim çevirir) │
       └─────────────────────────────────┘
```

Aynı IP adresindeki üç görev, port numarasıyla ayrılıyor ([Seviye 4](../04-tcp-udp/)).

## Kurulum

```bash
sudo apt install -y dnsmasq-base busybox
sudo ./setup.sh          # r1'de dnsmasq çalışır, pc1'in IP'si yok (Adım 1'in durumu)
sudo ./setup.sh --fixed  # pc1 adresini DHCP ile de alır
```

- **dnsmasq:** Küçük bir DHCP + DNS sunucusu. Birçok ev modeminde de çalışan program.
- **busybox udhcpc:** Küçük bir DHCP istemcisi. Sunucudan aldığı bilgileri [`udhcpc.sh`](udhcpc.sh) ile uyguluyor; bu script'in yaptığı iş, Seviye 3'te elle yazdığım `ip addr add` ve `ip route add default` komutlarının aynısı.

---

# Bölüm 1: DHCP

## Kavram

Seviye 3'te pc1'e IP adresini, maskeyi ve gateway'i elle girdim. DHCP bu bilgileri otomatik dağıtıyor. İstemci ile sunucu arasındaki konuşma 4 adım (**DORA**):

| Adım | Kimden → kime | Anlamı |
|---|---|---|
| **D**iscover | pc1 → herkes (broadcast) | "Ağda DHCP sunucusu var mı?" |
| **O**ffer | r1 → pc1 | "10.0.10.146'yı önerebilirim." |
| **R**equest | pc1 → herkes (broadcast) | "10.0.10.146'yı alıyorum." |
| **A**ck | r1 → pc1 | "Onaylandı, 1 saatliğine senin." |

Otel benzetmesi: oda numarası olmadan lobiye giriyorsun ve "resepsiyon nerede?" diye bağırıyorsun (Discover). Resepsiyon bir oda öneriyor (Offer), sen kabul ediyorsun (Request), resepsiyon onaylayıp anahtarı veriyor (Ack).

## Deney

pc1'in elle verilmiş adresini ve route'larını sildim; yeni bağlanmış, hiçbir ayarı olmayan bir cihaz gibi oldu:

```bash
sudo ip -n pc1 addr flush dev veth-pc1
sudo ip -n pc1 route flush dev veth-pc1
```

Üç pencere:

```bash
# A: dinleyici
sudo ip netns exec r1 tcpdump -n -v -i r1-eth1 'udp port 67 or udp port 68'

# B: DHCP sunucusu (r1)
sudo ip netns exec r1 dnsmasq --no-daemon --log-dhcp --user=root --group=root \
  --port=0 --interface=r1-eth1 --bind-interfaces \
  --dhcp-range=10.0.10.100,10.0.10.150,1h \
  --dhcp-option=option:router,10.0.10.1 \
  --dhcp-leasefile=/tmp/r1.leases

# C: DHCP istemcisi (pc1)
sudo ip netns exec pc1 busybox udhcpc -i veth-pc1 -f -q -s ./udhcpc.sh
```

`--port=0`, dnsmasq'ın DNS kısmını kapalı tutuyor (Bölüm 2'de açılıyor).

### pc1 (istemci)

```
udhcpc: started, v1.37.0
udhcpc: broadcasting discover
udhcpc: broadcasting discover
udhcpc: broadcasting select for 10.0.10.146, server 10.0.10.1
udhcpc: lease of 10.0.10.146 obtained from 10.0.10.1, lease time 3600
DHCP: veth-pc1 -> ip=10.0.10.146 mask=255.255.255.0 router=10.0.10.1 dns= lease=3600s
```

### r1 (dnsmasq log'u)

```
dnsmasq-dhcp: DHCPDISCOVER(r1-eth1) 36:32:83:d0:68:dd
dnsmasq-dhcp: DHCPOFFER(r1-eth1) 10.0.10.146 36:32:83:d0:68:dd
dnsmasq-dhcp: DHCPDISCOVER(r1-eth1) 36:32:83:d0:68:dd
dnsmasq-dhcp: DHCPOFFER(r1-eth1) 10.0.10.146 36:32:83:d0:68:dd
dnsmasq-dhcp: DHCPREQUEST(r1-eth1) 10.0.10.146 36:32:83:d0:68:dd
dnsmasq-dhcp: DHCPACK(r1-eth1) 10.0.10.146 36:32:83:d0:68:dd
```

### Kablodaki paketler (tcpdump, kısaltılmış)

```
12:28:14.061015 IP 10.0.10.1.67 > 10.0.10.146.68: BOOTP/DHCP, Reply, xid 0xa824ae4f, secs 3
        Your-IP 10.0.10.146
        DHCP-Message (53): Offer
        Lease-Time (51): 3600
        RN (58): 1800
        RB (59): 3150
        Subnet-Mask (1): 255.255.255.0
        Default-Gateway (3): 10.0.10.1

12:28:14.061639 IP 0.0.0.0.68 > 255.255.255.255.67: BOOTP/DHCP, Request from 36:32:83:d0:68:dd, xid 0xa824ae4f, secs 3
        DHCP-Message (53): Request
        Requested-IP (50): 10.0.10.146
        Server-ID (54): 10.0.10.1
        Parameter-Request (55):
          Subnet-Mask (1), Default-Gateway (3), Domain-Name-Server (6), Hostname (12)
          Domain-Name (15), BR (28), NTP (42)

12:28:14.062255 IP 10.0.10.1.67 > 10.0.10.146.68: BOOTP/DHCP, Reply, xid 0xa824ae4f, secs 3
        DHCP-Message (53): ACK
        Lease-Time (51): 3600
        Subnet-Mask (1): 255.255.255.0
        Default-Gateway (3): 10.0.10.1
```

### Sonuç: hiçbir şey yazmadan

```
$ sudo ip -n pc1 addr show veth-pc1
    inet 10.0.10.146/24 scope global veth-pc1
$ sudo ip -n pc1 route
default via 10.0.10.1 dev veth-pc1
10.0.10.0/24 dev veth-pc1 proto kernel scope link src 10.0.10.146
$ sudo ip netns exec pc1 ping -c 2 8.8.8.8
64 bytes from 8.8.8.8: icmp_seq=1 ttl=108 time=66.5 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=108 time=72.3 ms
```

dnsmasq'ın kira defteri:

```
$ cat /tmp/r1.leases
1791800894 36:32:83:d0:68:dd 10.0.10.146 * 01:36:32:83:d0:68:dd
```

"36:32:83:d0:68:dd MAC adresli cihaza 10.0.10.146 verildi; kira, ilk sayıdaki zamanda (Unix zamanı) bitiyor."

## DHCP gözlemleri

### 1. Request paketi: `0.0.0.0` → `255.255.255.255`
**Benzetme:** Henüz odası olmayan bir misafir, lobide herkesin duyacağı şekilde "146 numaralı odayı alıyorum!" diye bağırıyor. Kendi oda numarası olmadığı için kendini "odasız misafir" (`0.0.0.0`) olarak tanıtıyor, kime söylediğini bilmediği için de herkese (`255.255.255.255`) bağırıyor.

pc1 "10.0.10.146'yı alıyorum" derken bile bu adres henüz onun değil; ACK gelene kadar kaynak adresi `0.0.0.0` ("kim olduğumu bilmiyorum"). Sunucunun adresini de bilmediği için hedef `255.255.255.255` (herkes). Request'in broadcast olması, ağda birden fazla DHCP sunucusu varsa hangi teklifin kabul edildiğini hepsinin öğrenmesini sağlıyor.

### 2. İki Discover, iki Offer: UDP'de güvenilirlik uygulamanın işi
**Benzetme:** Resepsiyonist, 146 numaralı odayı vermeden önce odaya gidip kapıyı çalıyor: "İçeride kimse var mı?" Biraz bekliyor. Bu sırada misafir sabırsızlanıp "Resepsiyon nerede?" diye bir kez daha bağırıyor.

pc1 ilk Discover'a 3 saniye içinde cevap alamadı ve tekrar denedi (ikinci Offer'daki `secs 3`). İki Offer da aynı anda (12:28:14.06) gitti. dnsmasq, bir adresi teklif etmeden önce o adresin başka biri tarafından kullanılmadığını ping ile kontrol edip cevap bekliyor; muhtemel sebep bu. DHCP UDP kullandığı için, TCP'deki gibi protokolün kendisi tekrar göndermiyor; istemci kendi zamanlayıcısıyla yeniden deniyor ([Seviye 4](../04-tcp-udp/)).

Aynı istemci daha sonra adres yenilediğinde tek Discover yeterli oldu: dnsmasq'ın defterinde pc1'in MAC'i zaten kayıtlıydı ve aynı adresi hemen teklif etti.

### 3. Kira süreleri

**Benzetme:** Otelde 1 gecelik konaklama. Konaklamanın yarısında resepsiyona uğrayıp "bir gece daha kalabilir miyim?" diye soruyorsun (T1). Resepsiyonist ortada yoksa, çıkış saatine az kala hangi görevliyi bulursan ona soruyorsun (T2). Kimse uzatmazsa süre dolunca odayı boşaltıyorsun.


| Seçenek | Değer | Anlamı |
|---|---|---|
| Lease-Time (51) | 3600 sn | Adres 1 saatliğine kiralandı |
| RN / T1 (58) | 1800 sn | Sürenin yarısında aynı sunucudan yenilemeyi dene |
| RB / T2 (59) | 3150 sn | %87.5'te hâlâ yenilenmediyse herhangi bir sunucuya sor |

### 4. `xid`: konuşmanın kimliği
**Benzetme:** Rezervasyon numarası. Aynı anda lobide birçok misafir varsa, resepsiyon hangi cevabın kime ait olduğunu bu numarayla takip ediyor.

Dört mesajın hepsinde `xid 0xa824ae4f`. Aynı anda birden fazla istemci adres isterse cevaplar bu numarayla eşleşiyor (TCP'deki sıra numaraları, ICMP'deki `id` gibi).

### 5. İstemci bir istek listesi gönderiyor
**Benzetme:** Misafir sadece oda istemiyor; "Wi-Fi şifresi, kahvaltı saati, danışma masası nerede?" gibi bir soru listesi de veriyor.

`Parameter-Request` alanında pc1 maske, gateway, **DNS sunucusu**, hostname gibi bilgiler istiyor. Ama son satırda `dns=` boş: dnsmasq'ın DNS kısmı kapalıydı ve DNS sunucusu bildirilmemişti.

### CCNA notu
Broadcast'ler router'dan geçmiyor. DHCP sunucusu istemciyle aynı subnet'te değilse router'ın isteği sunucuya iletmesi gerekiyor (Cisco'da `ip helper-address`). Burada DHCP sunucusu doğrudan istemcinin subnet'inde (r1-eth1) olduğu için buna gerek kalmadı.

---

# Bölüm 2: DNS

## Kavram: internetin telefon rehberi

Bilgisayarlar birbirini **IP adresiyle** buluyor (8.8.8.8, 10.0.20.10...). İnsanlar ise **isim** hatırlıyor (google.com). Aradaki çeviriyi yapan sisteme DNS deniyor.

**Benzetme:** Telefonunda "Annem" diye kayıtlı birini aradığında telefon aslında bir numarayı arıyor. Rehber, ismi numaraya çeviriyor. DNS de internetin rehberi: "google.com" ismini "192.178.24.174" numarasına çeviriyor.

### Bu lab'da kim kimdir?

| Gerçek dünya | Bu lab |
|---|---|
| Rehbere bakmak isteyen kişi | **pc1** |
| Binanın danışma masası | **r1** üzerindeki dnsmasq (10.0.10.1, port 53) |
| Danışmanın elindeki kendi listesi | `--host-record=pc2.lab,10.0.20.10` |
| Danışmanın bilmediğinde aradığı merkez | **8.8.8.8** (Google'ın DNS sunucusu) |
| Danışmanın not defteri | dnsmasq'ın **önbelleği** (cache) |

### DNS'e sorulabilecek üç soru

| Soru türü | Telefon benzetmesi | Örnek |
|---|---|---|
| `A?` | "Ayşe'nin numarası ne?" (IPv4) | `A? google.com` → `192.178.24.174` |
| `AAAA?` | "Ayşe'nin yeni tip numarası ne?" (IPv6) | `AAAA? google.com` → `2a00:1450:...` |
| `PTR?` | "Bu numara kimin?" (ters soru) | `PTR? 10.0.20.10` → `pc2.lab` |

DNS soruları genelde **tek bir UDP paketiyle** gidip **tek bir UDP paketiyle** geliyor, port 53 üzerinden. [Seviye 4](../04-tcp-udp/)'teki "el sıkışmadan, kartpostal gibi gönder" modeli. Kısa bir soru için önce 3 paketlik bir el sıkışma yapmak israf olurdu.

### Danışma masası nerede? DHCP söylüyor

pc1'in bir isim sorabilmesi için önce **kime soracağını** bilmesi lazım. Bu bilgiyi DHCP veriyor. Bölüm 1'de `dns=` satırının boş kalmasının sebebi buydu: resepsiyon oda numarasını (IP) ve çıkış kapısını (gateway) söylemişti, ama danışma masasının yerini söylememişti.

---

## Deney 1: Danışma masasını açmak

dnsmasq'ı bu sefer DNS kısmı da açık olarak başlattım:

```bash
sudo ip netns exec r1 dnsmasq --no-daemon --log-dhcp --log-queries --user=root --group=root \
  --interface=r1-eth1 --bind-interfaces \
  --no-resolv --server=8.8.8.8 \
  --host-record=pc2.lab,10.0.20.10 \
  --dhcp-range=10.0.10.100,10.0.10.150,1h \
  --dhcp-option=option:router,10.0.10.1 \
  --dhcp-option=option:dns-server,10.0.10.1 \
  --dhcp-leasefile=/tmp/r1.leases
```

| Seçenek | Ne yapıyor | Benzetme |
|---|---|---|
| `--log-queries` | Her soruyu ekrana yaz | Danışman her soruyu deftere not ediyor |
| `--no-resolv --server=8.8.8.8` | Bilinmeyen isimleri sadece 8.8.8.8'e sor | "Bilmediğin bir şey olursa merkezi ara" |
| `--host-record=pc2.lab,10.0.20.10` | Rehbere bir kayıt ekle | Danışmanın elindeki kendi listesi |
| `--dhcp-option=option:dns-server,10.0.10.1` | DHCP ile "DNS sunucusu benim" diye duyur | Resepsiyon, anahtarla birlikte "danışma masası şurada" notunu da veriyor |

pc1 adresini yeniden istediğinde bu sefer danışma masasının yerini de öğrendi:

```
DHCP: veth-pc1 -> ip=10.0.10.146 mask=255.255.255.0 router=10.0.10.1 dns=10.0.10.1 lease=3600s
DNS: /etc/netns/pc1/resolv.conf -> 10.0.10.1
```

`dns=10.0.10.1` artık dolu. İkinci satır, bu bilginin pc1'in DNS ayar dosyasına yazıldığını gösteriyor. (Linux'ta "isimleri kime soracağım" bilgisi `/etc/resolv.conf` dosyasında duruyor. `ip netns exec`, `/etc/netns/pc1/resolv.conf` dosyasını pc1'in içinde `/etc/resolv.conf` olarak gösteriyor; böylece pc1'in ayarı VM'inkinden ayrı tutulabiliyor.)

### Gateway ile DNS sunucusu neden aynı adres?

pc1'in hem gateway'i hem DNS sunucusu **10.0.10.1**. Çünkü aynı cihaz (r1) iki ayrı iş yapıyor:

| Görev | Benzetme | Ne oluyor |
|---|---|---|
| Gateway | Binanın **çıkış kapısı** | pc1 başka bir ağa paket gönderiyor; paket r1'e *uğrayıp geçiyor*, hedef başkası |
| DNS sunucusu | Binanın **danışma masası** | pc1 bir soru soruyor; soru doğrudan *r1'in kendisine*, hedef r1 |

Tek bir binada hem kapı hem danışma olabilir; hangisine gittiğin, hangi kapıyı (portu) çaldığına bağlı. Evindeki modem de aynı: 192.168.1.1 hem gateway, hem DHCP, hem DNS sunucusu.

---

## Deney 2: İsimle ping

İki terminal: birinde r1'in içini dinledim, diğerinde ping attım.

```bash
# Dinleyici: r1'in iki tarafını birden (-i any) dinle, sadece DNS (udp port 53)
sudo ip netns exec r1 tcpdump -n -i any udp port 53

# pc1: isimle ping
sudo ip netns exec pc1 ping -4 -c 2 pc2.lab
sudo ip netns exec pc1 ping -4 -c 2 google.com
```

### pc1'in gördüğü

```
PING pc2.lab (10.0.20.10) 56(84) bytes of data.
64 bytes from pc2.lab (10.0.20.10): icmp_seq=1 ttl=63 time=1.47 ms
64 bytes from pc2.lab (10.0.20.10): icmp_seq=2 ttl=63 time=0.173 ms

PING google.com (192.178.24.174) 56(84) bytes of data.
64 bytes from lcsofa-as-in-f14.1e100.net (192.178.24.174): icmp_seq=1 ttl=108 time=65.6 ms
64 bytes from lcsofa-as-in-f14.1e100.net (192.178.24.174): icmp_seq=2 ttl=108 time=46.3 ms
```

- `pc2.lab (10.0.20.10)`: ping, paketi göndermeden **önce** DNS'e sordu ve ismi numaraya çevirdi. Paketler bu numaraya gidiyor; isim sadece insanlar için.
- `lcsofa-as-in-f14.1e100.net`: ping, cevap veren adresin ismini de merak edip **ters soru** (PTR) sordu. `sofa` → Sofya'daki bir Google sunucusu. `1e100.net`, Google'ın kendi alan adı (1×10¹⁰⁰ = googol).

### tcpdump satırlarını okumayı öğrenmek

Bir DNS satırı şöyle görünüyor:

```
r1-eth1 In  IP 10.0.10.146.43734 > 10.0.10.1.53: 4000+ A? pc2.lab. (25)
```

| Parça | Anlamı |
|---|---|
| `r1-eth1 In` | Paket r1'e, Satış ağı tarafından **girdi** |
| `10.0.10.146.43734` | Soran: pc1, rastgele seçtiği kaynak portu 43734 |
| `10.0.10.1.53` | Sorulan: r1, DNS portu 53 |
| `4000` | **Sorunun numarası.** Cevap da aynı numarayla geliyor; pc1 hangi cevabın hangi soruya ait olduğunu böyle anlıyor (bankada sıra numarası gibi) |
| `+` | "Sen bilmiyorsan, bilen birine sorup bul" |
| `A? pc2.lab.` | Soru: "pc2.lab'ın IPv4 adresi ne?" |
| `(25)` | Mesajın boyutu (bayt) |

Cevap satırı:

```
r1-eth1 Out IP 10.0.10.1.53 > 10.0.10.146.43734: 4000* 1/0/0 A 10.0.20.10 (41)
```

| Parça | Anlamı |
|---|---|
| `4000` | Aynı numara: "4000 numaralı sorunun cevabı" |
| `*` | "Bu bilgi **benim kendi kaydım**, başkasından duymadım" |
| `1/0/0` | İlk sayı önemli: **1 cevap** var (diğerleri ek bilgi sayıları) |
| `A 10.0.20.10` | Cevap: "pc2.lab = 10.0.20.10" |

### Sahne 1: pc2.lab, danışman kendi listesinden cevaplıyor

```
12:35:40.451031 r1-eth1 In  IP 10.0.10.146.43734 > 10.0.10.1.53: 4000+ A? pc2.lab. (25)
12:35:40.452645 r1-eth1 Out IP 10.0.10.1.53 > 10.0.10.146.43734: 4000* 1/0/0 A 10.0.20.10 (41)
```

dnsmasq log'u aynı şeyi kendi ağzından söylüyor:
```
dnsmasq: query[A] pc2.lab from 10.0.10.146
dnsmasq: config pc2.lab is 10.0.20.10
```

**Hikâye:** pc1 danışmaya geliyor: "pc2.lab nerede?" Danışman elindeki listeye bakıyor (`config` = "kendi ayarlarımdan"), cevabı hemen veriyor. Kimseyi aramıyor.

- Sadece **2 satır**, ikisi de `r1-eth1`'de: soru r1'den dışarı hiç çıkmadı.
- Süre: **1.6 ms**.

### Sahne 2: google.com, danışman merkezi arıyor

```
12:35:41.576442 r1-eth1 In  IP 10.0.10.146.49741 > 10.0.10.1.53: 13158+ A? google.com. (28)
12:35:41.576953 r1-wan Out IP 192.168.100.2.51258 > 8.8.8.8.53: 40649+ [1au] A? google.com. (39)
12:35:41.635048 r1-wan In  IP 8.8.8.8.53 > 192.168.100.2.51258: 40649 1/0/1 A 192.178.24.174 (55)
12:35:41.635455 r1-eth1 Out IP 10.0.10.1.53 > 10.0.10.146.49741: 13158 1/0/0 A 192.178.24.174 (44)
```

```
dnsmasq: query[A] google.com from 10.0.10.146
dnsmasq: forwarded google.com to 8.8.8.8
dnsmasq: reply google.com is 192.178.24.174
```

**Hikâye:**
1. pc1 danışmaya soruyor: "google.com nerede?" (`r1-eth1 In`, soru no. 13158)
2. Danışmanın listesinde yok. Telefonu açıp merkezi arıyor: "google.com nerede?" (`r1-wan Out`, 8.8.8.8'e, **kendi adına**, yeni soru no. 40649)
3. Merkez cevap veriyor: "192.178.24.174" (`r1-wan In`)
4. Danışman cevabı pc1'e iletiyor (`r1-eth1 Out`, pc1'in soru numarası 13158 ile)

Bunun adı **DNS forwarding** (yönlendirme). Dikkat edilecek iki şey:
- 8.8.8.8'e soruyu **pc1 değil, r1 soruyor** (kaynak `192.168.100.2`). Google, pc1'in varlığından habersiz; tıpkı merkezin, danışmaya soru soran misafiri tanımaması gibi.
- Süre: **59 ms.** Merkezi aramak, listeye bakmaktan 35 kat yavaş.

| | pc2.lab | google.com |
|---|---|---|
| Cevabı kim biliyordu? | r1'in kendisi | 8.8.8.8 |
| r1'deki satır sayısı | 2 | 4 |
| r1-wan'a çıktı mı? | Hayır | Evet |
| Süre | 1.6 ms | 59 ms |

### Sahne 3: tek ping, üç soru

Tek bir `ping pc2.lab` komutu aslında üç soru sordurdu:

```
12:35:40.451031 r1-eth1 In  ... 4000+ A? pc2.lab.                    ← "IPv4 adresi ne?"
12:35:40.451281 r1-eth1 In  ... 44449+ AAAA? pc2.lab.                ← "IPv6 adresi ne?"
12:35:40.550599 r1-eth1 In  ... 18650+ PTR? 10.20.0.10.in-addr.arpa. ← "10.0.20.10 kimin?"
```

- **Neden IPv6'yı da sordu?** `ping -4` sadece IPv4 kullanacak olsa da, Linux'un isim çözme kütüphanesi her ihtimale karşı ikisini birden soruyor. Restorana "menüde ne var?" diye sorarken hem öğle hem akşam menüsünü istemek gibi.
- **`PTR?` sorusundaki ters adres:** `10.0.20.10` adresi `10.20.0.10.in-addr.arpa` diye **tersten** yazılmış. Bu DNS'in ters sorgu formatı. Ping bu soruyu, ekranda `pc2.lab (10.0.20.10)` yazabilmek için sordu.

### Sahne 4: uydurma bir isim internete sızdı

```
12:35:40.452957 r1-wan Out IP 192.168.100.2.43647 > 8.8.8.8.53: 34882+ [1au] AAAA? pc2.lab. (36)
12:35:40.547852 r1-wan In  IP 8.8.8.8.53 > 192.168.100.2.43647: 34882 NXDomain 0/1/1 (111)
```
```
dnsmasq: query[AAAA] pc2.lab from 10.0.10.146
dnsmasq: forwarded pc2.lab to 8.8.8.8
dnsmasq: reply pc2.lab is NODATA-IPv6
```

Danışmanın listesinde pc2.lab'ın **IPv4** adresi vardı ama **IPv6** adresi yoktu. "Bilmediğim bir şey" deyip merkezi aradı. Merkez de `NXDomain` dedi: "Böyle bir isim yok." Doğal, çünkü `.lab` gerçek bir uzantı değil, bizim uydurduğumuz bir isim.

**Benzetme:** Şirketin iç dahili numarasını sorduğunda danışmanın bunu Bilinmeyen Numaralar'a sorması gibi. Hem gereksiz hem de iç bilgiyi dışarı sızdırıyor. Gerçek bir ağda dnsmasq'a "`.lab` bizim iç alanımız, dışarıya sorma" denir: `--local=/lab/`.

### Sahne 5: bir numaranın iki ismi

```
12:35:41.796396 r1-wan In  IP 8.8.8.8.53 > 192.168.100.2.38335: 49843 2/0/1 PTR lcsofa-as-in-f14.1e100.net., PTR mct04s02-in-f14.1e100.net. (126)
```

`2/0/1`: **2 cevap.** 192.178.24.174'ün iki ismi var. Bir telefon numarasının rehberde iki farklı isimle kayıtlı olması gibi. Ping ekranda ilkini gösterdi.

---

## Deney 3: Önbellek (not defteri)

6.5 dakika sonra aynı ping'i tekrarladım:

```
12:42:12.872308 r1-wan Out IP 192.168.100.2.37865 > 8.8.8.8.53: 6253+ [1au] A? google.com. (39)
12:42:12.928813 r1-wan In  IP 8.8.8.8.53 > 192.168.100.2.37865: 6253 1/0/1 A 192.178.24.174 (55)
...
12:42:13.008473 r1-eth1 In  IP 10.0.10.146.38466 > 10.0.10.1.53: 13874+ PTR? 174.24.178.192.in-addr.arpa. (45)
12:42:13.008571 r1-eth1 Out IP 10.0.10.1.53 > 10.0.10.146.38466: 13874 2/0/0 PTR lcsofa-as-in-f14.1e100.net., PTR mct04s02-in-f14.1e100.net. (124)
```

- `A? google.com`: danışman **yine merkezi aradı** (`r1-wan` satırları var).
- `PTR? 174.24.178.192...`: danışman **merkezi aramadı**, `r1-wan` satırı yok, cevap **0.1 ms**'de geldi.

**Neden biri önbellekten geldi, diğeri gelmedi?**

**Benzetme:** Danışman her cevabı not defterine yazıyor, ama her notun yanına bir **son kullanma tarihi** de yazıyor. Merkez cevabı verirken "bu bilgi 5 dakika geçerli" ya da "bu bilgi 1 gün geçerli" diyor. Süre dolan not silinip merkez yeniden aranıyor.

- google.com'un adresi sık değişiyor (Google, trafiği sunucular arasında sürekli kaydırıyor). Bu yüzden son kullanma süresi kısa. 6.5 dakika sonra **süresi dolmuştu.**
- "Bu numara kimin?" (PTR) bilgisi nadiren değişiyor, süresi çok daha uzun. **Hâlâ geçerliydi.**

Bu son kullanma süresinin adı da **TTL**. IP paketlerindeki TTL ile adı aynı ama farklı şeyler: orada "en fazla kaç router'dan geçebilirim", burada "bu bilgi kaç saniye geçerli".

---

## Deney 4: "It's always DNS"

DevOps dünyasında yaygın bir şaka var: *"It's always DNS."* (Sorun her zaman DNS'tir.) Bunun sebebini görmek için danışma masasını kapattım: dnsmasq'ı durdurdum.

(pc1'in adresi kaybolmadı: kira 1 saatlikti. Resepsiyon kapansa da odanın anahtarı hâlâ sende.)

```
$ sudo ip netns exec pc1 ping -4 -c 2 8.8.8.8
64 bytes from 8.8.8.8: icmp_seq=1 ttl=108 time=97.2 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=108 time=51.2 ms

$ sudo ip netns exec pc1 ping -4 -c 2 google.com
ping: google.com: Temporary failure in name resolution
```

| Komut | Sonuç | Neden |
|---|---|---|
| `ping 8.8.8.8` | ✅ Çalıştı | Numarayı zaten biliyorsun, rehbere gerek yok |
| `ping google.com` | ❌ `Temporary failure in name resolution` | İsmi numaraya çevirecek kimse yok |

**Benzetme:** Telefon hattın çalışıyor, numarasını ezbere bildiğin herkesi arayabiliyorsun. Ama rehberin kayboldu; "Annem"i arayamıyorsun çünkü numarasını bilmiyorsun.

**İnternet çalışıyor, sadece isimler çözülemiyor.** Gerçek hayatta "internet gitti!" şikâyetlerinin önemli bir kısmı bu. Teşhis yöntemi de bu kadar basit:
1. IP adresiyle dene (`ping 8.8.8.8`)
2. İsimle dene (`ping google.com`)
3. Biri çalışıp diğeri çalışmıyorsa sorun DNS'te.

### Kablodaki paketler

r1'de yakalanan (`'udp port 53 or icmp'`):

```
12:43:01.757496 r1-eth1 In  IP 10.0.10.146.43078 > 10.0.10.1.53: 32952+ A? google.com. (28)
12:43:01.757759 r1-eth1 Out IP 10.0.10.1 > 10.0.10.146: ICMP 10.0.10.1 udp port 53 unreachable, length 64
12:43:01.757797 r1-eth1 In  IP 10.0.10.146.43078 > 10.0.10.1.53: 14013+ AAAA? google.com. (28)
12:43:01.757807 r1-eth1 Out IP 10.0.10.1 > 10.0.10.146: ICMP 10.0.10.1 udp port 53 unreachable, length 64
12:43:01.757825 r1-eth1 In  IP 10.0.10.146.35178 > 10.0.10.1.53: 32952+ A? google.com. (28)
12:43:01.757881 r1-eth1 Out IP 10.0.10.1 > 10.0.10.146: ICMP 10.0.10.1 udp port 53 unreachable, length 64
12:43:01.757888 r1-eth1 In  IP 10.0.10.146.35178 > 10.0.10.1.53: 14013+ AAAA? google.com. (28)
12:43:01.757892 r1-eth1 Out IP 10.0.10.1 > 10.0.10.146: ICMP 10.0.10.1 udp port 53 unreachable, length 64
```

**Hikâye:**
1. pc1 danışma masasına geliyor ve soruyor: "google.com nerede?" (`A?`)
2. Masa boş. Ama binanın görevlisi (r1'in işletim sistemi) bir tabela gösteriyor: **"Danışma kapalı"** (`ICMP udp port 53 unreachable`).
3. pc1 aynı soruyu IPv6 için de deniyor (`AAAA?`), aynı tabela.
4. pc1 bir kez daha deniyor (bu sefer farklı bir kaynak portundan: 35178), yine aynı tabela.
5. pc1 vazgeçiyor: `Temporary failure in name resolution`.

Bu, [Seviye 4'teki kapalı UDP port deneyinin](../04-tcp-udp/README.md#deney-3-kapalı-bir-porta-bağlanmak) aynısı: bir porta UDP paketi geldiğinde onu dinleyen program yoksa, kernel ICMP "port unreachable" ile cevap veriyor.

Bir fark var: Seviye 4'te `nc` bu uyarıyı **dinlememiş** ve hata göstermeden çıkmıştı. Burada pc1'in DNS istemcisi uyarıyı **dinledi** ve hemen vazgeçti. Bütün deneme **1 milisaniye** sürdü (12:43:01.7575 → .7579). Tabela olmasaydı, yani soru sessizce kaybolsaydı, pc1 her denemede birkaç saniye bekleyecekti. Bu farkı Seviye 7'de firewall kurarken bilerek yaratacağım (paketi sessizce atan DROP ile "kapalı" tabelası gösteren REJECT).

---

## Büyük resim: `ping google.com` yazdığında olan her şey

Bu seviyede üst üste kurulan her katman, tek bir komutta birlikte çalışıyor:

| # | Adım | Seviye |
|---|---|---|
| 1 | pc1, adresini, gateway'ini ve DNS sunucusunu **DHCP** ile aldı | 6 |
| 2 | pc1, "google.com kim?" diye r1'e **DNS** ile sordu (UDP 53) | 6, 4 |
| 3 | r1 bilmediği için 8.8.8.8'e sordu ve cevabı iletti | 6 |
| 4 | pc1, 192.178.24.174'ün kendi ağında olmadığını gördü, paketi **gateway**'e (r1) verdi | 3 |
| 5 | Paketi göndermeden önce r1'in MAC adresini **ARP** ile öğrendi | 1 |
| 6 | r1, paketi `r1-wan`'dan çıkarırken kaynak adresi **NAT** ile kendi adresine çevirdi | 5 |
| 7 | Cevap geldi, r1 NAT tablosuna bakıp pc1'e iletti | 5 |

Bir bilgisayar Wi-Fi'ye bağlanıp bir siteyi açtığında olan şeyin tamamı bu.

## Docker'da karşılığı

Otel benzetmesiyle: Docker, misafirlerin lobide bağırıp oda istediği bir otel değil; **odaları misafir gelmeden önce kendisi atayan** bir otel. Danışma masası (DNS) ise her katta var.

- **Docker DHCP kullanmıyor.** Container oluşturulurken Docker ağdaki boş adreslerden birini kendisi seçip doğrudan atıyor (IPAM). Adresler `docker network inspect <ağ>` ile görülüyor. AWS gibi cloud ortamlarındaki sanal makineler ise IP'lerini DHCP ile alıyor.
- **Docker'ın kendi DNS sunucusu var.** `docker network create` ile oluşturulan ağlarda her container'ın `/etc/resolv.conf` dosyasında `nameserver 127.0.0.11` yazıyor. Bu, Docker'ın yerleşik DNS sunucusu ve buradaki dnsmasq'ın yaptığının aynısını yapıyor:
  - Container isimlerini kendisi çözüyor (`ping db` → db container'ının IP'si), tıpkı `--host-record=pc2.lab,...` gibi.
  - Bilmediği isimleri host'un DNS sunucularına iletiyor, tıpkı `--server=8.8.8.8` gibi.
- Varsayılan `docker0` ağında container'lar birbirini isimle bulamıyor; bu yerleşik DNS yalnızca kullanıcının oluşturduğu ağlarda çalışıyor.
- Container içinde `Temporary failure in name resolution` hatası çok yaygın ve teşhisi bu seviyedeki gibi: IP ile çalışıp isimle çalışmıyorsa sorun DNS'te.
- Kubernetes'te aynı rolü **CoreDNS** üstleniyor: servis isimlerini cluster içinde çözüyor, diğerlerini dışarıya iletiyor.

## Temizlik

```bash
sudo ./teardown.sh
```

dnsmasq'ı durduruyor, pc1'in DNS ayar dosyasını ve kira defterini siliyor, Seviye 5'in topolojisini kaldırıyor.
