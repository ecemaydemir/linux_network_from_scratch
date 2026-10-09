# Seviye 4: İnternete çıkış (NAT / PAT)

## Topoloji

Seviye 3'teki ağa bir "internet kablosu" eklendi:

```
  pc1 (10.0.10.10) ─┐
                    ├── r1 (router + NAT) ──────── netlab VM ("ISP") ──── internet
  pc2 (10.0.20.10) ─┘        r1-wan                   host-r1
                         192.168.100.2             192.168.100.1
```

- **r1:** Evdeki modemin rolü. İçerideki özel adresleri kendi dış adresiyle maskeliyor.
- **netlab VM:** ISP rolü. OrbStack'in ağı bizim uydurduğumuz 192.168.100.0/24'ü tanımadığı için VM de ayrıca NAT yapıyor. Gerçek hayattaki karşılığı Carrier-Grade NAT (CGNAT).

## Kavram

- 10.0.0.0/8, 172.16.0.0/12 ve 192.168.0.0/16 **özel (private) adresler** (RFC 1918). İnternette yönlendirilmezler; aynı anda milyonlarca ağda kullanılırlar.
- **NAT**, paket dışarı çıkarken kaynak adresi router'ın dış adresiyle değiştirir ve bunu bir tabloya not eder. Cevap gelince tabloya bakıp hedefi geri çevirir.
- **PAT** (Cisco'da *NAT overload*), içerideki herkesin tek bir dış adresi paylaşmasını sağlar. Bağlantılar port numaralarıyla ayırt edilir.
- Linux'ta PAT'ın adı `MASQUERADE`, NAT tablosunu gösteren araç `conntrack`.

## Kurulum

```bash
sudo apt install -y iptables conntrack
sudo ./setup.sh          # r1'de NAT kapalı (Adım 1'in durumu)
sudo ./setup.sh --fixed  # r1'de NAT açık
```

`setup.sh`, Seviye 3'ün çalışır halini kurup üzerine WAN bağlantısını ekliyor.

## Adım 1: NAT olmadan internete çıkmak

```bash
# Pencere A
sudo ip netns exec r1 tcpdump -n -i any icmp
# Pencere B
sudo ip netns exec pc1 ping -c 3 8.8.8.8
```

```
3 packets transmitted, 0 received, 100% packet loss
```

Router'da yakalanan (id 1249):

```
09:46:38.111660 r1-eth1 In  IP 10.0.10.10 > 8.8.8.8: ICMP echo request, id 1249, seq 1, length 64
09:46:38.111874 r1-wan Out IP 10.0.10.10 > 8.8.8.8: ICMP echo request, id 1249, seq 1, length 64
```

Paket internet tarafından **10.0.10.10 kaynak adresiyle** çıkıyor. Bu özel bir adres; internette ona giden bir yol yok, dolayısıyla cevap da gelemez. (Bu lab'da paket büyük ihtimalle daha VM'de takılıyor, çünkü VM'in NAT kuralı sadece 192.168.100.0/24 kaynaklı paketleri maskeliyor. Sonuç aynı: özel adresle internete çıkılamaz.)

Hata mesajının `Network is unreachable` değil `100% packet loss` olması da önemli: pc1 tarafında her şey doğru, sorun yolun ilerisinde ([Seviye 3, Gözlem 3](../03-router/README.md#3-hata-mesajı-sorunun-nerede-olduğunu-söylüyor)).

## Adım 2: NAT'ı açmak

```bash
sudo ip netns exec r1 iptables -t nat -A POSTROUTING -o r1-wan -j MASQUERADE
```

"`r1-wan`'dan çıkan her paketin kaynak adresini, o kartın adresiyle değiştir." Cisco'daki karşılığı:

```
ip nat inside source list 1 interface Gi0/1 overload
```

```
$ sudo ip netns exec pc1 ping -c 3 8.8.8.8
64 bytes from 8.8.8.8: icmp_seq=1 ttl=108 time=52.7 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=108 time=49.0 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=108 time=43.3 ms

3 packets transmitted, 3 received, 0% packet loss
```

Router'da bir ping'in tam turu (id 1275):

```
09:48:10.072412 r1-eth1 In  IP 10.0.10.10 > 8.8.8.8: ICMP echo request, id 1275, seq 1, length 64
09:48:10.072544 r1-wan Out IP 192.168.100.2 > 8.8.8.8: ICMP echo request, id 1275, seq 1, length 64
09:48:10.125031 r1-wan In  IP 8.8.8.8 > 192.168.100.2: ICMP echo reply, id 1275, seq 1, length 64
09:48:10.125109 r1-eth1 Out IP 8.8.8.8 > 10.0.10.10: ICMP echo reply, id 1275, seq 1, length 64
```

| Satır | Ne oldu |
|---|---|
| `r1-eth1 In` | pc1'den geldi: kaynak 10.0.10.10 |
| `r1-wan Out` | **Kaynak değişti** → 192.168.100.2 |
| `r1-wan In` | Google cevabı router'ın dış adresine gönderdi |
| `r1-eth1 Out` | **Hedef geri çevrildi** → 10.0.10.10 |

Seviye 3'te router IP adreslerine hiç dokunmuyordu. NAT bu kuralın bilinçli bir istisnası. Google'ın gözünde konuştuğu cihaz 192.168.100.2; 10.0.10.10'un varlığından haberi yok.

## Adım 3: NAT tablosu (conntrack)

Router cevabın pc1'e ait olduğunu nasıl hatırlıyor?

```
$ sudo ip netns exec r1 conntrack -F
$ sudo ip netns exec pc1 ping -c 1 8.8.8.8
$ sudo ip netns exec r1 conntrack -L
icmp     1 18 src=10.0.10.10 dst=8.8.8.8 type=8 code=0 id=1302 src=8.8.8.8 dst=192.168.100.2 type=0 code=0 id=1302 mark=0 use=1
```

| Parça | Anlamı |
|---|---|
| `icmp 1` | Protokol ve IP başlığındaki numarası (ICMP 1, TCP 6, UDP 17) |
| `18` | Kaydın silinmesine kalan saniye (ICMP kayıtları 30 saniye yaşıyor) |
| 1. yarı: `src=10.0.10.10 dst=8.8.8.8 type=8` | Paketin içeriden çıkarken hali |
| 2. yarı: `src=8.8.8.8 dst=192.168.100.2 type=0` | **Beklenen cevabın** hali |
| `id=1302` | ICMP'de port olmadığı için bağlantıyı bu kimlik ayırt ediyor |

Dışarıdan gelen bir paket 2. yarıyla eşleşirse hedefi 1. yarıdaki kaynağa çevrilip içeri gönderiliyor. Eşleşen bir kayıt yoksa paket içeri giremiyor. NAT'ın "dışarıdan bağlantı başlatılamaz" özelliği buradan geliyor.

## Adım 4: PAT'ı yakalamak

pc1 ve pc2'yi **aynı kaynak portuyla** aynı sunucuya bağladım. Dışarıdan bakıldığında iki bağlantı birebir aynı görünecekti: aynı IP (192.168.100.2), aynı port (50000), aynı hedef (1.1.1.1:80).

```bash
sudo ip netns exec r1 conntrack -F
sudo ip netns exec pc1 curl -s -o /dev/null --local-port 50000 http://1.1.1.1
sudo ip netns exec pc2 curl -s -o /dev/null --local-port 50000 http://1.1.1.1
sudo ip netns exec r1 conntrack -L -p tcp
```

```
tcp  6 59 CLOSE_WAIT src=10.0.20.10 dst=1.1.1.1 sport=50000 dport=80 src=1.1.1.1 dst=192.168.100.2 sport=80 dport=29662 [ASSURED] mark=0 use=1
tcp  6 9 CLOSE src=10.0.10.10 dst=1.1.1.1 sport=50000 dport=80 src=1.1.1.1 dst=192.168.100.2 sport=80 dport=50000 [ASSURED] mark=0 use=1
```

| | İçeride (Cisco: *inside local*) | Dışarıda (Cisco: *inside global*) |
|---|---|---|
| pc1 | 10.0.10.10 : 50000 | 192.168.100.2 : **50000** |
| pc2 | 10.0.20.10 : 50000 | 192.168.100.2 : **29662** |

İlk gelen pc1 portunu korudu. pc2 aynı portla geldiğinde router, çakışmayı önlemek için onun dış portunu **29662** yaptı. Cloudflare'in 29662'ye gönderdiği cevap, tablodan pc2'ye ait olduğu anlaşılarak içeri iletiliyor.

**Router çakışma olmadıkça portu değiştirmiyor, çakışma olunca değiştiriyor.** Tek bir dış IP ile binlerce bağlantının aynı anda yönetilebilmesinin sebebi bu.

## Gözlemler

### 1. NAT, routing'in "IP'lere dokunma" kuralını bilinçli olarak bozuyor
Seviye 3'te kaynak ve hedef adresler router'ın iki tarafında da aynıydı. Burada giden paketin kaynağı, gelen paketin hedefi değişiyor.

### 2. Router'ın da default gateway'e ihtiyacı oldu
Seviye 3'te router her iki ağa da doğrudan bağlıydı, bilmediği bir yer yoktu. İnternet eklenince onun da bir postaneye ihtiyacı oldu: `ip -n r1 route add default via 192.168.100.1`.

### 3. TTL ve gecikme, yolun uzunluğunu gösteriyor
| | TTL | Süre |
|---|---|---|
| Seviye 3 (aynı makinede, 1 router) | 63 | ~0.2 ms |
| Seviye 4 (8.8.8.8) | 108 | ~48 ms |

TTL'in başlangıç değeri işletim sistemine göre değişiyor (Linux 64, Windows 128 vb.), bu yüzden 108'den kesin hop sayısı çıkarılamaz. Ama yolun artık onlarca router'dan oluştuğu açık.

### 4. ICMP'de port yok, ID var
`conntrack` ICMP bağlantılarını `id` alanıyla ayırt ediyor. PAT'ta port numarasının oynadığı rolü ICMP'de bu alan üstleniyor.

## Temizlik

```bash
sudo ./teardown.sh
```

VM'deki NAT kuralını ve tüm namespace'leri siliyor. VM'in `ip_forward` ayarını 1'de bırakıyor.
