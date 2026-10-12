# Seviye 7: VLAN, trunk ve router-on-a-stick

## Tek cümleyle

- **VLAN:** Tek bir switch'i, birbirini göremeyen birkaç sanal switch'e böler.
- **Trunk:** İki switch arasındaki tek kablodan birden fazla VLAN'ı taşır; her paketin üstüne "hangi VLAN'a ait" etiketi yapıştırır.
- **Router-on-a-stick:** VLAN'ları birbirine bağlayan router; switch'e tek bir kabloyla bağlı.
- **SVI (multilayer switch):** Routing'i ayrı bir router yerine switch'in kendisi yapıyor.

> **Benzetme:** Bir ofis binası. VLAN'lar araya örülmüş **görünmez duvarlar**, trunk iki kat arasında etiketli kolileri taşıyan **kargo arabası**, router da iki odaya da kapısı açılan **sekreter**.

## Kurulum

```bash
sudo ./setup.sh           # iki switch, 6 bilgisayar, VLAN 10/20, trunk
sudo ./setup.sh --router  # ayrıca router-on-a-stick
sudo ./setup.sh --svi     # router yerine switch'in kendisi routing yapar (SVI)
```

---

## 1. VLAN: aynı switch, görünmez duvar

```
                    sw1
     ┌──────────┬──────────┬──────────┐
    pc1        pc2        pc3        pc4
  10.0.0.1   10.0.0.2   10.0.0.3   10.0.0.4
  └─── VLAN 10 ───┘     └─── VLAN 20 ───┘
```

Dört bilgisayar da **aynı subnet'te** (bilerek). Portları VLAN'lara atamak:

```bash
sudo bridge vlan del dev sw1-p1 vid 1
sudo bridge vlan add dev sw1-p1 vid 10 pvid untagged    # access port, VLAN 10
```

Cisco'daki `switchport mode access` + `switchport access vlan 10`. Kontrol: `bridge vlan show` (Cisco'da `show vlan brief`).

| Ping | VLAN atamadan önce | VLAN atadıktan sonra |
|---|---|---|
| pc1 → pc2 (ikisi de VLAN 10) | ✅ | ✅ |
| pc1 → pc3 (VLAN 10 → 20) | ✅ | ❌ |

```
$ sudo ip -n pc1 neigh
10.0.0.2 dev veth-pc1 lladdr 6e:3e:bf:7b:d0:71 STALE
10.0.0.3 dev veth-pc1 FAILED
```

pc1, pc3'ün MAC adresini ARP ile sordu ama cevap alamadı (`FAILED`). Switch ARP broadcast'ini **sadece aynı VLAN'daki** portlara iletiyor; soru pc3'e hiç ulaşmadı.

---

## 2. Trunk: kargo arabası

```
        sw1  ══════ trunk (VLAN 10 + 20) ══════  sw2
   ┌────┬────┬────┐                         ┌────┴────┐
  pc1  pc2  pc3  pc4                        pc5       pc6
  └ V10 ┘   └ V20 ┘                       VLAN 10   VLAN 20
```

```bash
sudo bridge vlan add dev sw1-trunk vid 10    # "pvid untagged" yok → etiketli
sudo bridge vlan add dev sw1-trunk vid 20
```

Cisco'daki `switchport mode trunk` + `switchport trunk allowed vlan 10,20`.

```
$ bridge vlan show
sw1-trunk     1 PVID Egress Untagged     ← native VLAN 1: etiketsiz
              10                         ← etiketli
              20                         ← etiketli
```

**Kabloda yakalanan** (`tcpdump -n -e -i sw1-trunk icmp`, kısaltılmış):

```
1a:62:e6:01:a7:b8 > 9e:02:4e:03:c0:04, ethertype 802.1Q (0x8100), length 102: vlan 10, ... 10.0.0.1 > 10.0.0.5: ICMP echo request
26:4c:e4:57:56:25 > 16:5d:58:7f:3b:b6, ethertype 802.1Q (0x8100), length 102: vlan 20, ... 10.0.0.3 > 10.0.0.6: ICMP echo request
```

| Ping | Sonuç | Kablodaki etiket |
|---|---|---|
| pc1 → pc5 (Satış → Satış) | ✅ | `vlan 10` |
| pc3 → pc6 (IT → IT) | ✅ | `vlan 20` |
| pc1 → pc6 (Satış → IT) | ❌ | Hiç ping paketi yok (ARP sorusu pc6'ya ulaşmadı) |

Etiket pakete **4 bayt** ekliyor: kabloda 102 bayt; etiketsiz olsa 98 olurdu. Access port'ta etiket sökülüyor, bilgisayar VLAN'dan habersiz.

---

## 3. Router-on-a-stick: sekreter

Router'ın kullanılabilmesi için **her VLAN'ın ayrı bir subnet'i** olmalı. Yoksa pc1, pc6'yı kendi ağında sanıp router'a hiç uğramaz ([Seviye 3](../03-router/)).

| VLAN | Bilgisayarlar | Subnet | Gateway |
|---|---|---|---|
| 10 (Satış) | pc1, pc2, pc5 → .11, .12, .15 | 10.0.10.0/24 | 10.0.10.1 |
| 20 (IT) | pc3, pc4, pc6 → .13, .14, .16 | 10.0.20.0/24 | 10.0.20.1 |

Router, switch'e **tek kabloyla** (trunk) bağlı; kablonun üzerinde iki sanal ayak var:

```bash
sudo ip -n r1 link add link r1-eth0 name r1-eth0.10 type vlan id 10
sudo ip -n r1 addr add 10.0.10.1/24 dev r1-eth0.10
sudo ip -n r1 link add link r1-eth0 name r1-eth0.20 type vlan id 20
sudo ip -n r1 addr add 10.0.20.1/24 dev r1-eth0.20
sudo ip netns exec r1 sysctl -qw net.ipv4.ip_forward=1
```

Cisco'daki `interface g0/0.10` + `encapsulation dot1Q 10` + `ip address 10.0.10.1 255.255.255.0`.

**Sonuç:**
```
$ sudo ip netns exec pc1 ping -c 2 10.0.20.16
64 bytes from 10.0.20.16: icmp_seq=1 ttl=63 time=0.510 ms     ← ttl 63: bir router'dan geçti
```

**Router'ın kablosunda** (`tcpdump -n -e -i sw1-p0 icmp`), tek bir ping'in yolculuğu:

```
1a:62:e6:01:a7:b8 > 6a:eb:0a:f6:3a:2c ... vlan 10 ... 10.0.10.11 > 10.0.20.16: ICMP echo request   ← pc1 → r1, Satış etiketiyle çıktı
6a:eb:0a:f6:3a:2c > 16:5d:58:7f:3b:b6 ... vlan 20 ... 10.0.10.11 > 10.0.20.16: ICMP echo request   ← r1 → pc6, IT etiketiyle geri indi
16:5d:58:7f:3b:b6 > 6a:eb:0a:f6:3a:2c ... vlan 20 ... 10.0.20.16 > 10.0.10.11: ICMP echo reply     ← cevap: pc6 → r1
6a:eb:0a:f6:3a:2c > 1a:62:e6:01:a7:b8 ... vlan 10 ... 10.0.20.16 > 10.0.10.11: ICMP echo reply     ← r1 → pc1
```

- Aynı paket **aynı kablodan iki kez** geçiyor: bir kez `vlan 10` ile yukarı, bir kez `vlan 20` ile aşağı.
- **IP adresleri değişmiyor, MAC adresleri değişiyor** (`pc1 → r1`, sonra `r1 → pc6`).

---

## 4. SVI: routing'i switch'in kendisi yapıyor

Router-on-a-stick'te VLAN'lar arası trafiğin tamamı router'a giden **tek kablodan** gidip geliyor; trafik artınca o kablo tıkanabiliyor.

> **Benzetme:** İki mahalle arasında duvar var. Router-on-a-stick'te karşıya geçmek için herkes şehir dışındaki köprüye giden **tek şeritli yolu** kullanıyor; araba çoğalınca trafik sıkışıyor. SVI'da duvarın ortasına **bir kapı** açılıyor; kimse şehir dışına çıkmıyor.

Router'ı (r1) sildim ve aynı gateway adreslerini switch'in kendisine verdim:

```bash
sudo ip netns del r1
sudo bridge vlan add dev sw1 vid 10 self               # switch'in kendisi VLAN 10'u duysun
sudo ip link add link sw1 name sw1.10 type vlan id 10  # interface vlan 10
sudo ip addr add 10.0.10.1/24 dev sw1.10
# (VLAN 20 için aynısı)
sudo sysctl -qw net.ipv4.ip_forward=1                  # ip routing
```

| Router-on-a-stick (r1) | SVI (sw1) | Kampüs projesi (DIST1) |
|---|---|---|
| `r1-eth0.10` → 10.0.10.1 | `sw1.10` → 10.0.10.1 | `interface vlan 10` → 192.168.10.1 |
| `ip_forward=1` (r1'de) | `ip_forward=1` (switch'te) | `ip routing` |

Aynı üç adım; tek fark gateway'in nerede olduğu.

### İlk denemede çalışmadı: eski MAC

```
$ sudo ip netns exec pc1 ping -c 2 10.0.20.16
2 packets transmitted, 0 received, 100% packet loss

$ sudo ip -n pc1 neigh
10.0.10.1 dev veth-pc1 FAILED
$ ip link show sw1.10 | grep ether
    link/ether 52:8c:68:53:ae:87
```

pc1, 10.0.10.1'in MAC adresini router-on-a-stick zamanından (r1'in MAC'i) hatırlıyordu. Paketi artık var olmayan cihaza gönderdi, cevap alamayınca kaydı `FAILED` yaptı. Taşınan bir arkadaşın eski numarasını aramak gibi. ARP tablosunu temizleyince düzeldi:

```
$ sudo ip -n pc1 neigh flush all
$ sudo ip -n pc6 neigh flush all
$ sudo ip netns exec pc1 ping -c 2 10.0.20.16
64 bytes from 10.0.20.16: icmp_seq=1 ttl=63 time=0.190 ms
64 bytes from 10.0.20.16: icmp_seq=2 ttl=63 time=0.181 ms

$ sudo ip -n pc1 neigh
10.0.10.1 dev veth-pc1 lladdr 52:8c:68:53:ae:87 REACHABLE      ← yeni sahip: sw1
```

- **`ttl=63`:** Ayrı bir router olmadığı halde routing yapıldı; TTL'i switch azalttı.
- Gerçek ağlarda bir router ya da sunucu değiştirildiğinde de aynı sorun yaşanıyor: cihazlar eski MAC'i bir süre hatırlıyor.

---

## Kendini test et

<details>
<summary><b>1. pc1 ile pc3 aynı subnet'teyken neden birbirine ulaşamadı?</b></summary>

VLAN, IP'den bir katman aşağıda (L2) çalışıyor. pc1, pc3'ün MAC adresini ARP broadcast'iyle sordu; switch bu broadcast'i sadece VLAN 10'daki portlara iletti. pc3 soruyu hiç duymadı, cevap veremedi. IP'lerin aynı subnet'te olması bir şey değiştirmiyor.

</details>

<details>
<summary><b>2. Trunk portunda <code>1 PVID Egress Untagged</code> ne demek?</b></summary>

**Native VLAN.** Trunk'tan etiketsiz gelen paketler VLAN 1'e ait sayılıyor. Cisco'da da trunk'ın native VLAN'ı varsayılan olarak 1 (`show interfaces trunk` → `Native vlan 1`). VLAN 10 ve 20'nin yanında `Untagged` yazmadığı için onlar etiketli gidiyor.

</details>

<details>
<summary><b>3. Router-on-a-stick için neden VLAN'lara ayrı subnet verdik?</b></summary>

Bir bilgisayar paketi default gateway'e **sadece hedef kendi subnet'inde değilse** verir. Herkes 10.0.0.0/24'teyken pc1, pc6'yı kendi ağında sanıp doğrudan ARP ile arardı; router'a hiç uğramazdı. Ayrı subnet'ler, VLAN'lar arası trafiğin router'dan geçmesini sağlıyor.

</details>

<details>
<summary><b>4. Router'ın kablosunda bir ping paketi neden iki kez görünüyor?</b></summary>

Router'ın tek kablosu var. Paket o kablodan `vlan 10` etiketiyle router'a çıkıyor, router onu `vlan 20` etiketiyle aynı kablodan geri indiriyor. Bu yöntemin zayıf yanı da bu: tüm VLAN'lar arası trafik aynı kablodan iki kez geçtiği için kablo darboğaz olabiliyor. [Kampüs projemde](https://github.com/ecemaydemir/campus_network_design) multilayer switch'te SVI kullanmanın sebebi bu; routing switch'in içinde, kabloya çıkmadan yapılıyor (Bölüm 4).

</details>

<details>
<summary><b>5. Router'ı SVI ile değiştirdikten sonra ping neden önce çalışmadı?</b></summary>

pc1, gateway'in (10.0.10.1) MAC adresini ARP tablosunda saklıyordu ve bu hâlâ eski router'ın MAC'iydi. Paketleri artık var olmayan bir cihaza gönderdi. ARP tablosu temizlenince pc1 "10.0.10.1 kimde?" diye yeniden sordu ve yeni sahibi (sw1) öğrendi.

</details>

---

## Docker'da karşılığı

- Her `docker network create` ayrı bir Linux bridge oluşturuyor. Farklı ağlardaki container'lar birbirini göremiyor; VLAN'lardaki görünmez duvarın Docker'daki karşılığı bu.
- Container'ları şirket ağındaki gerçek bir VLAN'a doğrudan bağlamak için `macvlan` ağı kullanılıyor: `docker network create -d macvlan -o parent=eth0.10 ...`. Buradaki `eth0.10`, router-on-a-stick'teki `r1-eth0.10` ile aynı tür bir VLAN alt arayüzü.

## Temizlik

```bash
sudo ./teardown.sh
```
