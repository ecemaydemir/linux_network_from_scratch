# Seviye 6: DHCP ve DNS

## Tek cümleyle

- **DHCP:** Ağa bağlanan cihaza adresini **otomatik** verir.
- **DNS:** İsmi (google.com) numaraya (IP adresi) **çevirir**.

Bu lab'da ikisini de router (r1) yapıyor, tıpkı evdeki modem gibi.

## Kurulum

```bash
sudo apt install -y dnsmasq-base busybox
sudo ./setup.sh          # r1'de DHCP + DNS sunucusu çalışır, pc1'in IP'si yok
sudo ./setup.sh --fixed  # pc1 adresini DHCP ile de alır
```

---

## 1. DHCP: adresi otomatik almak

Seviye 3'te pc1'in adresini ve gateway'ini **elle** yazmıştım:

```bash
ip addr add 10.0.10.10/24 dev veth-pc1
ip route add default via 10.0.10.1
```

Bu seviyede hiçbir şey yazmadım; pc1 bunları r1'den **kendisi istedi**.

**Otel benzetmesi:** Oda numaran olmadan otele giriyorsun.

| Adım | Otelde | Bu lab'da |
|---|---|---|
| Discover | "Resepsiyon nerede? Oda lazım!" (herkese bağırıyorsun) | pc1 → herkese |
| Offer | "146 boş, ister misin?" | r1 → pc1 |
| Request | "146'yı alıyorum!" | pc1 → herkese |
| Ack | "Tamam, 1 saatliğine senin." | r1 → pc1 |

**Sonuç:**

```
$ sudo ip netns exec pc1 busybox udhcpc -i veth-pc1 -f -q -s ./udhcpc.sh
udhcpc: lease of 10.0.10.146 obtained from 10.0.10.1, lease time 3600

$ sudo ip -n pc1 addr   →  inet 10.0.10.146/24     ← adres: kendiliğinden geldi
$ sudo ip -n pc1 route  →  default via 10.0.10.1   ← gateway: kendiliğinden geldi
```

---

## 2. DNS: ismi numaraya çevirmek

Tarayıcına `google.com` yazdığında bilgisayar Google'a doğrudan gidemez, çünkü internette her şey **numarayla** bulunur. Önce birine sorar: *"google.com'un numarası ne?"* Cevap gelir: *"192.178.24.174"*. Sonra o numaraya gider.

Bu lab'da:
- **Soran:** pc1
- **Cevaplayan:** r1 (danışma masası)
- **r1 bilmiyorsa:** 8.8.8.8'e sorar

> **8.8.8.8 nedir?** Google'ın internetteki DNS sunucusu: tek işi "şu ismin numarası ne?" sorularını cevaplamak olan bir bilgisayar. Herkes ücretsiz kullanabilir. Bu projede iki amaçla geçiyor:
> 1. **Ping hedefi:** `ping 8.8.8.8` = "internete çıkabiliyor muyum?" testi. Burada sadece her zaman açık olan bir adres.
> 2. **DNS sunucusu:** r1, bilmediği isimleri ona soruyor.

pc1, danışma masasının adresini (10.0.10.1) **DHCP'den** öğrendi. Resepsiyon, oda anahtarıyla birlikte "danışma şurada" notunu da verdi.

**Sonuç:**

```
$ sudo ip netns exec pc1 ping -4 -c 2 pc2.lab
PING pc2.lab (10.0.20.10) ...                    ← "pc2.lab" ismi 10.0.20.10'a çevrildi

$ sudo ip netns exec pc1 ping -4 -c 2 google.com
PING google.com (192.178.24.174) ...             ← "google.com" ismi 192.178.24.174'e çevrildi
```

---

## 3. Deney: danışma masasını kapatmak

r1'deki DNS sunucusunu (dnsmasq) durdurdum:

| Komut | Sonuç |
|---|---|
| `ping 8.8.8.8` | ✅ Çalıştı |
| `ping google.com` | ❌ `Temporary failure in name resolution` |

**Teşhis kuralı:** Önce IP adresiyle, sonra isimle dene. Biri çalışıp diğeri çalışmıyorsa sorun DNS'te. DevOps'ta bunun için bir şaka var: *"It's always DNS."*

---

## Kendini test et

Cevabı görmek için soruya tıkla.

<details>
<summary><b>1. DNS kapalıyken neden <code>ping 8.8.8.8</code> çalıştı ama <code>ping google.com</code> çalışmadı?</b></summary>

`8.8.8.8` zaten bir numara; çevirmeye gerek yok, pc1 doğrudan gidiyor.
`google.com` ise bir isim; önce numarasının sorulması lazım. Soracağı yer (r1'deki DNS) kapalı olduğu için çevrilemedi.

İnternet bağlantısı sağlamdı; bozuk olan sadece **çeviri**ydi.

</details>

<details>
<summary><b>2. r1, <code>pc2.lab</code> sorulduğunda internete çıkmadı ama <code>google.com</code> sorulduğunda 8.8.8.8'e gitti. Neden?</b></summary>

dnsmasq'ı başlatırken r1'in kendi listesine bir kayıt eklemiştim: `--host-record=pc2.lab,10.0.20.10`.
- **pc2.lab:** r1 cevabı kendi listesinde buldu ve hemen verdi (1.6 ms).
- **google.com:** r1'in listesinde yoktu, 8.8.8.8'e sordu ve cevabı pc1'e iletti (59 ms).

Danışman bildiğini kendisi söylüyor, bilmediği için merkezi arıyor.

</details>

<details>
<summary><b>3. pc1, DNS sunucusunun adresini nereden öğrendi?</b></summary>

DHCP'den. r1, pc1'e adres verirken `dns=10.0.10.1` bilgisini de gönderdi. DHCP ile DNS bu yüzden birlikte anlatılıyor.

</details>

<details>
<summary><b>4. Gateway ile DNS sunucusu neden aynı adres (10.0.10.1)?</b></summary>

Çünkü aynı cihaz (r1) iki ayrı iş yapıyor:
- **Gateway** = binanın çıkış kapısı. Paket r1'e uğrayıp başka yere gidiyor.
- **DNS sunucusu** = binanın danışma masası. Soru doğrudan r1'e soruluyor.

Hangisine gidildiğini port numarası belirliyor (DNS: 53, DHCP: 67). Evdeki modem de böyle: 192.168.1.1 hem gateway, hem DHCP, hem DNS.

</details>

---

## Ayrıntılar

<details>
<summary>DHCP: paketler ve gözlemler</summary>

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

- **`0.0.0.0 → 255.255.255.255`:** pc1'in henüz adresi yok ve sunucunun yerini bilmiyor, o yüzden herkese bağırıyor.
- **İki Discover:** İlkine 3 saniyede cevap gelmeyince pc1 tekrar sordu. DHCP UDP kullandığı için tekrar denemek istemcinin işi ([Seviye 4](../04-tcp-udp/)).
- **Kira:** 1 saat. Yarısında (30 dk) uzatma isteniyor (`RN`).
- **`xid`:** Konuşmanın numarası; otelde rezervasyon numarası gibi.
- **CCNA notu:** Broadcast router'dan geçmez. DHCP sunucusu başka subnet'teyse router'da `ip helper-address` gerekir.

</details>

<details>
<summary>DNS: paketler, satırları okuma ve gözlemler</summary>

```
# pc2.lab: cevap r1'in kendi listesinden (sadece r1-eth1)
r1-eth1 In  IP 10.0.10.146.43734 > 10.0.10.1.53: 4000+ A? pc2.lab. (25)
r1-eth1 Out IP 10.0.10.1.53 > 10.0.10.146.43734: 4000* 1/0/0 A 10.0.20.10 (41)

# google.com: r1 8.8.8.8'e soruyor (r1-wan)
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
| `4000` | Sorunun numarası; cevap aynı numarayla gelir |
| `A?` / `AAAA?` / `PTR?` | IPv4 adresi ne? / IPv6 adresi ne? / Bu IP kimin? |
| `*` | "Bu bilgi benim kendi kaydım" |
| `1/0/0` | İlk sayı: kaç cevap var |
| `NXDomain` | "Böyle bir isim yok" |

- **DNS forwarding:** google.com'u 8.8.8.8'e pc1 değil r1 sordu (kaynak `192.168.100.2`). Google pc1'i hiç görmedi.
- **Önbellek ve TTL:** r1 cevapları hatırlıyor ama her cevabın bir son kullanma süresi var. 6.5 dakika sonra google.com'un kaydının süresi dolmuştu (yeniden soruldu); "bu IP kimin?" (PTR) kaydı hâlâ geçerliydi (0.1 ms'de önbellekten geldi).
- **Sızıntı:** pc2.lab'ın IPv6 kaydı olmadığı için dnsmasq bunu 8.8.8.8'e sordu, `NXDomain` cevabı geldi. Gerçek ağda `--local=/lab/` ile iç isimlerin dışarıya sorulması engellenir.
- **Tek ping, üç soru:** `A?`, `AAAA?` ve ekranda ismi yazmak için `PTR?`. PTR'de adres tersten yazılıyor: `10.20.0.10.in-addr.arpa`.

</details>

<details>
<summary>"It's always DNS": paketler</summary>

```
r1-eth1 In  IP 10.0.10.146.43078 > 10.0.10.1.53: 32952+ A? google.com. (28)
r1-eth1 Out IP 10.0.10.1 > 10.0.10.146: ICMP 10.0.10.1 udp port 53 unreachable, length 64
r1-eth1 In  IP 10.0.10.146.43078 > 10.0.10.1.53: 14013+ AAAA? google.com. (28)
r1-eth1 Out IP 10.0.10.1 > 10.0.10.146: ICMP 10.0.10.1 udp port 53 unreachable, length 64
(pc1 bir kez daha denedi, aynı cevap)
```

53. portu dinleyen kimse kalmadığı için r1'in işletim sistemi "port unreachable" ile cevap verdi; [Seviye 4'teki kapalı port](../04-tcp-udp/README.md#deney-3-kapalı-bir-porta-bağlanmak) deneyinin aynısı. pc1 1 ms içinde vazgeçti.

</details>

---

## Docker'da karşılığı

- **Docker DHCP kullanmıyor:** Container oluşturulurken IP adresini kendisi seçip veriyor.
- **Docker'ın kendi DNS sunucusu var:** `docker network create` ile kurulan ağlarda container'lar `127.0.0.11`'e soruyor. Container isimlerini kendisi çeviriyor (`ping db` gibi), bilmediğini dışarıya soruyor. Buradaki r1'in yaptığının aynısı.
- Container içinde `Temporary failure in name resolution` hatası çok yaygın. Teşhis yukarıdakiyle aynı: IP ile dene, sonra isimle.

## Temizlik

```bash
sudo ./teardown.sh
```
