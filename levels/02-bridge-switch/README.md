# Seviye 2: Linux bridge ile switch

## Topoloji

```
        pc1            pc2            pc3
     10.0.0.1       10.0.0.2       10.0.0.3
         │              │              │
      br-pc1         br-pc2         br-pc3
         └──────────── br0 ────────────┘
                     (switch)
```

| Bilgisayar | IP | MAC | Switch portu |
|---|---|---|---|
| pc1 | 10.0.0.1 | `1a:62:e6:01:a7:b8` | `br-pc1` |
| pc2 | 10.0.0.2 | `6e:3e:bf:7b:d0:71` | `br-pc2` |
| pc3 | 10.0.0.3 | `26:4c:e4:57:56:25` | `br-pc3` |

- **Linux bridge (`br0`):** Yazılımsal bir layer 2 switch. Docker'ın `docker0` arayüzü de bir Linux bridge.
- `ip link set br-pcX master br0` komutu, kabloyu switch'in bir portuna takmanın karşılığı.
- Deneylerin temiz olması için IPv6 tüm arayüzlerde kapalı (nedeni aşağıda, Gözlem 3).

## Kurulum

```bash
sudo ./setup.sh
```

## Deney 1: Switch MAC adreslerini nasıl öğreniyor?

**Kural:** Switch'e bir frame geldiğinde, frame'in **kaynak** MAC adresini ve geldiği portu tablosuna yazar. Linux'ta bu tablo `bridge fdb show` ile görülüyor (Cisco'daki `show mac address-table`).

**Başlangıç: tablo boş**
```
$ bridge fdb show br br0 | grep -v permanent
$
```

**pc1 → pc2 ping'inden sonra**
```
$ sudo ip netns exec pc1 ping -c 1 10.0.0.2
$ bridge fdb show br br0 | grep -v permanent
1a:62:e6:01:a7:b8 dev br-pc1 master br0
6e:3e:bf:7b:d0:71 dev br-pc2 master br0
```

pc3 tabloda **yok**. Olanlar sırasıyla:
1. pc1'in ARP request'i `br-pc1`'den girdi → switch pc1'i öğrendi.
2. ARP request bir broadcast olduğu için switch onu pc2'ye **ve pc3'e** iletti.
3. pc3 "bu IP benim değil" deyip sessiz kaldı → hiçbir frame göndermediği için öğrenilmedi.
4. pc2 cevap verdi, cevap `br-pc2`'den girdi → switch pc2'yi öğrendi.

**pc1 → pc3 ping'inden sonra**
```
1a:62:e6:01:a7:b8 dev br-pc1 master br0
6e:3e:bf:7b:d0:71 dev br-pc2 master br0
26:4c:e4:57:56:25 dev br-pc3 master br0
```

pc3 cevap verdiği anda o da tabloya girdi.

**Sonuç:** Switch yalnızca **konuşan** cihazları öğrenebiliyor. Bir broadcast'i alıp susan cihaz, ağda olsa bile switch için görünmez.

## Deney 2: Switch frame'leri kime iletiyor?

pc1 pc3'e ping atarken **pc2'nin kartını** dinledim. ARP tabloları ve switch'in MAC tablosu önce temizlendi.

```bash
# Pencere A
sudo ip netns exec pc2 tcpdump -i veth-pc2 -n 'arp or icmp'

# Pencere B
sudo ip -n pc1 neigh flush all
sudo ip -n pc3 neigh flush all
sudo ip link set br0 type bridge ageing_time 0; sleep 1; sudo ip link set br0 type bridge ageing_time 30000
sudo ip netns exec pc1 ping -c 3 10.0.0.3
```

pc2'de yakalanan:
```
11:37:31.336451 ARP, Request who-has 10.0.0.3 tell 10.0.0.1, length 28
```

**Sadece bir paket.** 3 ping, 3 cevap ve bir ARP reply'ın hiçbiri pc2'ye ulaşmadı.

| Paket | Hedef MAC | Switch'in kararı | pc2 görüyor mu? |
|---|---|---|---|
| ARP request | `ff:ff:ff:ff:ff:ff` (broadcast) | Geldiği port hariç **tüm portlara** bas | ✅ |
| ARP reply | pc1 | pc1 tabloda (request'ten öğrenildi) → yalnızca `br-pc1` | ❌ |
| ICMP echo request/reply | pc3 / pc1 | İkisi de tabloda → yalnızca ilgili port | ❌ |

Switch'i hub'dan ayıran şey bu. Hub her frame'i her porta basardı; pc2 bütün ping'leri görürdü.

**Not:** Bir arayüzü dinlemek, o cihaza *ulaşan* trafiği gösterir; switch'ten *geçen* trafiğin hepsini değil. Switch'in tüm kararlarını görmek için switch portlarını dinlemek gerekir (Cisco'da SPAN / port mirroring). Linux'ta portlar ana makinede durduğu için hepsi tek komutla dinlenebiliyor:

```bash
sudo tcpdump -i any -n 'arp or icmp'
```

Çıktıda her frame'in hangi porttan girdiği (`In`) ve hangi porttan çıktığı (`Out`) görünüyor.

## Gözlemler

### 1. MAC adresleri rastgele değil
Seviye 1'i silip Seviye 2'yi sıfırdan kurdum, ama `veth-pc1` ve `veth-pc2` aynı MAC adreslerini aldı. Ubuntu'da systemd, sanal arayüzlerin MAC adresini **arayüzün adından ve makinenin kimliğinden** türetiyor (`MACAddressPolicy=persistent`). Aynı isim + aynı makine = aynı MAC.

### 2. MAC tablosunun ömrü
Kayıtlar varsayılan olarak 300 saniye (`ageing_time 30000`, saniyenin yüzde biri cinsinden) sonra siliniyor. Cisco switch'lerde de varsayılan 300 saniye. Tabloyu temizlemek için ömrü bir anlığına 0 yapıp geri almak işe yarıyor.

### 3. IPv6 açıkken "sessiz" cihaz bile tabloya giriyor
İlk denemede IPv6 açıktı ve pc2, hiçbir ping'e katılmadığı halde switch'in tablosunda görünüyordu. Sebebi, arayüz açılır açılmaz Linux'un kendiliğinden IPv6 router solicitation göndermesi (Seviye 1, Gözlem 3). Switch bu frame'in kaynak MAC'inden pc2'yi öğrendi. Deneyi temiz yapabilmek için IPv6'yı kapattım:

```bash
sysctl -w net.ipv6.conf.all.disable_ipv6=1
```

## Karşılaşılan sorunlar

**tcpdump hiçbir şey yakalamadı (`0 packets captured`, `Exit 124`)**
tcpdump'ı `timeout 8` ile arka planda başlatıp komutları tek tek yazdım. Ping'i çalıştırana kadar 8 saniye geçmişti, tcpdump çoktan kapanmıştı. `Exit 124`, `timeout` komutunun "süre doldu" kodu.

**Önce trafik, sonra dinleyici**
Komutları toplu yapıştırınca bu sefer tersi oldu: ping, tcpdump dinlemeye hazır olmadan başladı ve ilk ARP paketleri kaçtı.

**Çözüm:** İki ayrı terminal. Birinde süre sınırı olmadan dinle, diğerinde trafiği üret, işin bitince dinleyiciyi Ctrl+C ile durdur.

## Temizlik

```bash
sudo ./teardown.sh
```
