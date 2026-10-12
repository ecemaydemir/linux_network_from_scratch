# Seviye 4: TCP ve UDP

Seviye 3'teki ağ (pc1 — r1 — pc2) üzerinde, katman 4'ün iki protokolünü paket seviyesinde karşılaştırdım.

## Kavram

| | TCP | UDP |
|---|---|---|
| Bağlantı | Önce el sıkışır (3-way handshake) | El sıkışmadan doğrudan gönderir |
| Teslim garantisi | Her bayt onaylanır (ACK), kaybolan tekrar gönderilir | Yok |
| Başlık boyutu | En az 20 bayt | 8 bayt |
| Örnek kullanım | HTTP, SSH, veritabanları | DNS, ses/görüntü, oyunlar |

## Kurulum

```bash
sudo apt install -y netcat-openbsd
sudo ./setup.sh     # Seviye 3'ün çalışır halini kurar
```

Üç terminal kullandım:

| Pencere | Rol | Komut |
|---|---|---|
| A | Dinleyici | `sudo ip netns exec pc2 tcpdump -n -i veth-pc2 ...` |
| B | Sunucu (pc2) | `sudo ip netns exec pc2 nc -l ...` |
| C | İstemci (pc1) | `sudo ip netns exec pc1 nc ...` |

## Deney 1: TCP bağlantısının tam ömrü

```bash
# A
sudo ip netns exec pc2 tcpdump -n -i veth-pc2 tcp port 8080
# B
sudo ip netns exec pc2 nc -l 8080
# C: bağlan, "merhaba" yaz, Enter, birkaç dakika sonra Ctrl+C
sudo ip netns exec pc1 nc 10.0.20.10 8080
```

pc2'de yakalanan (TCP seçenekleri okunabilirlik için kısaltıldı):

```
11:40:54.359863 IP 10.0.10.10.41450 > 10.0.20.10.8080: Flags [S], seq 3211363116, win 64240, options [mss 1460,sackOK,TS val 1627751782 ecr 0,nop,wscale 9], length 0
11:40:54.359972 IP 10.0.20.10.8080 > 10.0.10.10.41450: Flags [S.], seq 1729268487, ack 3211363117, win 65160, options [mss 1460,sackOK,...,wscale 9], length 0
11:40:54.360088 IP 10.0.10.10.41450 > 10.0.20.10.8080: Flags [.], ack 1, win 126, length 0
11:40:59.174311 IP 10.0.10.10.41450 > 10.0.20.10.8080: Flags [P.], seq 1:9, ack 1, win 126, length 8: HTTP
11:40:59.174337 IP 10.0.20.10.8080 > 10.0.10.10.41450: Flags [.], ack 9, win 128, length 0
11:43:19.081963 IP 10.0.10.10.41450 > 10.0.20.10.8080: Flags [F.], seq 9, ack 1, win 126, length 0
11:43:19.082449 IP 10.0.20.10.8080 > 10.0.10.10.41450: Flags [F.], seq 1, ack 10, win 128, length 0
11:43:19.082614 IP 10.0.10.10.41450 > 10.0.20.10.8080: Flags [.], ack 2, win 126, length 0
```

| # | Flag | Yön | Anlamı |
|---|---|---|---|
| 1 | `[S]` | pc1 → pc2 | SYN: "Konuşabilir miyiz?" |
| 2 | `[S.]` | pc2 → pc1 | SYN + ACK: "Evet." |
| 3 | `[.]` | pc1 → pc2 | ACK: "Tamam, başlıyorum." |
| 4 | `[P.]` | pc1 → pc2 | Veri: `merhaba` + satır sonu = 8 bayt |
| 5 | `[.]` | pc2 → pc1 | ACK 9: "8 baytı aldım, 9. baytı bekliyorum." |
| 6 | `[F.]` | pc1 → pc2 | FIN: "Ben bitirdim." |
| 7 | `[F.]` | pc2 → pc1 | FIN + ACK: "Anladım, ben de bitirdim." |
| 8 | `[.]` | pc1 → pc2 | ACK: "Tamam." |

**8 baytlık veri için 8 paket.** TCP'nin güvenilirliğinin bedeli bu.

### Bu çıktıdan öğrendiklerim

- **Ephemeral port:** pc1'in kaynak portu (41450) benim seçmediğim, işletim sisteminin rastgele verdiği bir port. Sunucunun portu (8080) ise sabit.
- **Rastgele başlangıç sıra numaraları:** İki taraf da kendi `seq` numarasını rastgele başlatıyor. pc2'nin `ack 3211363117` cevabı, pc1'in numarasının bir fazlası: "Sıradakini bekliyorum." 3. paketten sonra tcpdump numaraları 1'den başlayan göreli değerlerle gösteriyor.
- **ACK numarası "aldığım" değil, "beklediğim" baytı gösteriyor.** 8 bayt alındıktan sonra `ack 9`.
- **FIN de bir sıra numarası tüketiyor.** Veri 8 bayt olduğu halde pc2'nin FIN'i `ack 10` diyor; TCP "bitirdim" mesajını da onaylanması gereken bir bayt gibi sayıyor. Son paketteki `ack 2` de pc2'nin FIN'ini onaylıyor.
- **Kapanış kitaptaki gibi 4 değil, 3 paket.** Teoride FIN → ACK → FIN → ACK. pc2'nin gönderecek başka verisi olmadığı için ACK ile kendi FIN'ini tek pakette birleştirdi.
- **Bağlantı bir trafik değil, bir durum.** El sıkışma 11:40:54'te, veri 11:40:59'da, kapanış 11:43:19'da. Aradaki dakikalarda hiç paket yok ama bağlantı iki tarafın hafızasında açık kaldı.
- **`HTTP` etiketi yanıltıcı.** tcpdump, 8080 portunu genelde web sunucuları kullandığı için böyle tahmin ediyor. Port numarası bir gelenek, içerik hakkında garanti değil.

### TCP seçenekleri (SYN paketlerinde pazarlık ediliyor)

| Alan | Anlamı |
|---|---|
| `win 64240` | Alıcının şu an kabul edebileceği bayt miktarı (flow control) |
| `wscale 9` | `win` değerini 2⁹ = 512 ile çarp. Sonraki paketlerdeki `win 126` gerçekte ≈ 64 KB |
| `mss 1460` | Tek paketteki en fazla veri: 1500 (Ethernet MTU) − 20 (IP) − 20 (TCP) |
| `sackOK` | Kaybolan paket olursa sadece onu tekrar gönder (Selective ACK) |
| `TS val / ecr` | Zaman damgaları; gidiş-dönüş süresini ölçmek için |
| `nop` | Hizalama için boş dolgu |

## Deney 2: Aynı mesaj UDP ile

```bash
# A
sudo ip netns exec pc2 tcpdump -n -i veth-pc2 udp port 9090
# B
sudo ip netns exec pc2 nc -u -l 9090
# C: "merhaba" yaz, Enter, Ctrl+C
sudo ip netns exec pc1 nc -u 10.0.20.10 9090
```

```
11:48:00.736991 IP 10.0.10.10.35352 > 10.0.20.10.9090: UDP, length 8
```

| | TCP | UDP |
|---|---|---|
| Açılış | 3 paket | Yok |
| `merhaba` | 1 paket + 1 ACK | 1 paket, onay yok |
| Kapanış | 3 paket | Yok |
| **Toplam** | **8 paket** | **1 paket** |

Satırda `seq`, `ack`, `win` veya flag yok. UDP başlığı yalnızca kaynak port, hedef port, uzunluk ve checksum'dan oluşuyor. pc1, mesajın ulaştığını hiçbir zaman öğrenmedi.

## Deney 3: Kapalı bir porta bağlanmak

pc2'de 7777 numaralı portu dinleyen bir program yok.

```bash
# A
sudo ip netns exec pc2 tcpdump -n -i veth-pc2 'port 7777 or icmp'
# C
sudo ip netns exec pc1 nc -v -w 2 10.0.20.10 7777
echo merhaba | sudo ip netns exec pc1 nc -u -w 2 10.0.20.10 7777
```

pc1'in ekranı:

```
$ sudo ip netns exec pc1 nc -v -w 2 10.0.20.10 7777
nc: connect to 10.0.20.10 port 7777 (tcp) failed: Connection refused
$ echo merhaba | sudo ip netns exec pc1 nc -u -w 2 10.0.20.10 7777
$
```

pc2'de yakalanan:

```
11:49:38.110440 IP 10.0.10.10.41284 > 10.0.20.10.7777: Flags [S], seq 4055347136, win 64240, options [...], length 0
11:49:38.110527 IP 10.0.20.10.7777 > 10.0.10.10.41284: Flags [R.], seq 0, ack 4055347137, win 0, length 0
11:49:51.666125 IP 10.0.10.10.37920 > 10.0.20.10.7777: UDP, length 8
11:49:51.666307 IP 10.0.20.10 > 10.0.10.10: ICMP 10.0.20.10 udp port 7777 unreachable, length 44
```

- **TCP:** Portu dinleyen bir program olmasa da pc2'nin işletim sistemi **RST** (`[R.]`) ile cevap verdi: "Burada kimse yok." pc1'de `nc` hemen `Connection refused` dedi.
- **UDP:** UDP'nin "hayır" demek için bir flag'i yok. pc2 bir katman aşağıdan, **ICMP port unreachable** ile cevap verdi. Ama pc1'deki `nc` bu uyarıyı dinlemedi ve **hiçbir hata göstermeden** çıktı. UDP'de hata yönetimi tamamen uygulamaya kalmış.

## Hata mesajları ne söylüyor?

| Hata | Ne oldu | Muhtemel sebep |
|---|---|---|
| `Connection refused` | Makineye ulaşıldı, RST geldi | Servis çalışmıyor ya da yanlış port |
| `Connection timed out` | Hiç cevap gelmedi | Paketi sessizce atan bir firewall ya da yol yok |
| `Network is unreachable` | Paket hiç çıkmadı | Routing ([Seviye 3, Adım 1](../03-router/README.md#adım-1-gateway-yok--paket-hiç-çıkmıyor)) |

`Connection refused` aslında iyi bir işaret: ağ sağlam, sorun serviste. Seviye 6'da firewall kurarken bu farkı bilerek oluşturacağım (paketi sessizce atan DROP ile reddeden REJECT).

## Temizlik

```bash
sudo ./teardown.sh
```
