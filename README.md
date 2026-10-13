# VPN Auto-Installer — Multi-Protokol Linux (WireGuard + SSH + Xray + OpenVPN + Shadowsocks)

> Dibuat oleh **wrwb Store** — Limit default 2 IP & 100 GB, auto-suspend 5 menit jika multi-login.

> 📖 English version (default): [README.en.md](README.en.md)
>
> **Baru di v1.3:** installer bilingual **English (default) / Indonesia**.
> Saat instalasi Anda ditanya bahasa — tekan Enter saja = otomatis **English**.
> Detail: [CHANGELOG-v1.3.md](CHANGELOG-v1.3.md).

Skrip **otomatisasi instalasi VPN siap pakai** berbasis **WireGuard** sebagai mesin utama, dengan **SSH VPN** dan **Xray-core** terpasang **secara default**, plus opsi **OpenVPN**, **v2ray-core**, dan **Shadowsocks**. Dibuat modular, aman, dan kompatibel dengan banyak distro Linux — dari versi lama sampai terbaru.

> Dibuat untuk Linux Server (VPS / Bare Metal). Bukan untuk dijalankan di Windows — clone repo ini ke server Linux Anda.
>
> **Baru di v1.2:** setiap akun baru menanyakan **Limit IP** dan **Limit Bandwidth**
> (default **2 IP** & **100 GB/bulan** bila di-skip). Multi-login melebihi limit =
> **auto-suspend 5 menit + auto-clear sesi**. Detail: [CHANGELOG-v1.2.md](CHANGELOG-v1.2.md).

---

## 🌐 Bahasa / Language

- Bahasa default: **English**. Saat instalasi, tekan **Enter** saja = English.
- Pilih **2) Indonesia** untuk installer Bahasa Indonesia.
- Non-interaktif / automation:
  ```bash
  sudo ./install.sh --yes                 # English (default)
  sudo ./install.sh --lang id --yes       # Bahasa Indonesia
  VPN_LANG=id sudo ./install.sh --yes     # via env var
  ```
- Pilihan tersimpan di `/etc/vpn/lang` dan dipakai semua skrip (`add-client.sh`, `menu.sh`, `status.sh`, ...).
- Ganti kapan saja: `sudo ./menu.sh` → menu **17) Ganti bahasa**, atau `sudo ./menu.sh --lang en|id`.

---

## ✨ Fitur Utama

| Fitur | Detail |
|---|---|
| 🔌 **Protokol utama** | WireGuard (ChaCha20-Poly1305, MTU 1420) dengan auto-generate keypair server + client, Pre-Shared Key (PSK), file `.conf` client & QR Code (PNG + ANSI terminal) |
| 🔑 **SSH VPN (default ON)** | OpenSSH hardening + Dropbear (port 143) + SSH over TLS/Stunnel (port 444) + SSH over WebSocket (port 80). Manajemen akun: `add-ssh-user.sh` / `remove-ssh-user.sh` (dengan masa berlaku) |
| ⚡ **Xray-core (default ON)** | v26.3.27 stabil — 5 inbound sekaligus: VMess WS (10001), VLESS WS (10002), Trojan WS (10003), VLESS TCP XTLS-Vision (10004), **VLESS TCP XTLS-Vision + REALITY (443)**. 1 UUID berlaku untuk semua protokol + link & QR otomatis |
| 🔄 **Alternatif engine** | v2ray-core v5.53.0 (ganti via `--with-v2ray` atau `XRAY_ENGINE=v2ray`); OpenVPN 2.7/2.6 (cipher `AES-256-GCM` + `CHACHA20-POLY1305`, auth `SHA512`, TLS min 1.3, profil `.ovpn`) sebagai pengganti SSH |
| 👻 **Shadowsocks (opsional)** | shadowsocks-rust v1.25.0, cipher AEAD-2022 `2022-blake3-aes-256-gcm` + URI `ss://` + QR |
| 🖥️ **Dukungan OS** | Ubuntu 20.04 / 22.04 / 24.04 / 26.04 LTS, Debian 10 / 11 / 12 / 13, CentOS / Rocky / AlmaLinux 8 / 9, RHEL 8/9, Fedora |
| 🛡️ **Firewall otomatis** | Membuka semua port VPN (UDP + TCP) di **UFW** (Debian/Ubuntu) atau **firewalld** (RHEL/Rocky) |
| 🌐 **IP Forwarding** | Mengaktifkan `net.ipv4.ip_forward=1` + IPv6 forwarding secara persisten (`/etc/sysctl.d/99-vpn-forward.conf`) |
| 🚀 **Optimasi throughput** | `MTU = 1420` di server & client, TCP BBR + buffer 25 MB via sysctl |
| 🔀 **NAT / Masquerade** | Aturan `iptables ... -j MASQUERADE` otomatis via `PostUp`/`PostDown` WireGuard agar internet client berjalan |
| 📦 **Modular** | `install.sh`, `add-client.sh`, `remove-client.sh`, `list-clients.sh`, `show-qr.sh`, `add-ssh-user.sh`, `remove-ssh-user.sh`, `add-xray-user.sh`, `remove-xray-user.sh`, `check-limits.sh`, `status.sh`, `menu.sh` (0-17), `uninstall.sh`, plus library di `lib/` (termasuk `lib/lang.sh`, `lib/limits.sh`) |
| 🌐 **Bilingual (v1.3)** | English default, Indonesia opsional. Satu codebase via `T "English" "Indonesia"` di `lib/lang.sh`, tersimpan di `/etc/vpn/lang` |
| ⚠️ **Error handling** | Wajib root/sudo, cek `/dev/net/tun`, deteksi OS + peringatan distro belum teruji, cek port & dependensi, validasi nama client/user, backup konfigurasi lama |
| ⏱️ **Limit & suspend (v1.2)** | Limit IP concurrent + bandwidth GB/bulan per akun (default 2 IP & 100 GB). Multi-login > limit = auto-suspend 5 menit + auto-clear sesi. Monitor systemd `vpn-limits` tiap 60 detik |

---

## 📁 Struktur Repository

```
vpn/
├── install.sh              # Instalasi: WireGuard + SSH + Xray (default ON)
├── add-client.sh           # Tambah client WireGuard baru (tanya limit IP & bandwidth)
├── remove-client.sh        # Hapus client WireGuard (+ bersihkan data limit)
├── list-clients.sh         # Daftar client WG + statistik trafik & handshake
├── show-qr.sh              # Tampilkan ulang QR Code / .conf client WG
├── add-ssh-user.sh         # Buat akun SSH VPN (masa berlaku + limit IP & bandwidth)
├── remove-ssh-user.sh      # Hapus akun SSH VPN (+ bersihkan data limit)
├── add-xray-user.sh        # Buat user Xray/V2Ray + limit IP & bandwidth
├── remove-xray-user.sh     # Hapus user Xray/V2Ray (+ bersihkan data limit)
├── check-limits.sh         # Lihat limit IP, kuota, IP aktif & status suspend
├── status.sh               # Diagnostik: service, forwarding, TUN, NAT, firewall, limit, bahasa
├── menu.sh                 # Menu interaktif 0-17 (panel kontrol wrwb Store, termasuk ganti bahasa)
├── uninstall.sh            # Hapus bersih seluruh instalasi VPN (+ monitor limit, + /etc/vpn/lang)
├── README.md               # Dokumentasi Indonesia (file ini)
├── README.en.md            # Dokumentasi English (default)
├── CHANGELOG-v1.2.md       # Catatan rilis v1.2 (limit IP & bandwidth)
├── CHANGELOG-v1.3.md       # Catatan rilis v1.3 (bilingual EN/ID)
├── lib/
│   ├── lang.sh             # Inti bilingual v1.3: T "EN" "ID", /etc/vpn/lang
│   ├── common.sh           # Logging, deteksi OS, validasi, helper jaringan, params
│   ├── system.sh           # Instal paket, IP forwarding, firewall (UFW/firewalld)
│   ├── wireguard.sh        # Inti WireGuard: server conf, alokasi IP, CRUD client
│   ├── ssh.sh              # Modul SSH: OpenSSH+Dropbear+Stunnel+WebSocket, CRUD akun
│   ├── xray.sh             # Modul Xray/V2Ray: VMess/VLESS/Trojan+XTLS/REALITY
│   ├── limits.sh           # Modul v1.2: limit IP & bandwidth + auto-suspend 5 menit
│   ├── openvpn.sh          # Modul alternatif OpenVPN + Easy-RSA
│   └── shadowsocks.sh      # Modul opsional Shadowsocks-rust
├── README.md
└── .gitattributes          # Memaksa LF endings agar skrip aman di Linux
```

File konfigurasi yang dihasilkan di server:

```
/etc/wireguard/wg0.conf            # Konfigurasi server WireGuard
/etc/wireguard/params              # Parameter server (di-source skrip WG lain)
/etc/wireguard/clients/<nama>/
    ├── <nama>.conf                # Profil client (import ke aplikasi WireGuard)
    ├── <nama>.png                 # QR code (untuk HP/tablet)
    └── private.key / public.key / preshared.key
/etc/ssh-vpn/params                # Port SSH/Dropbear/TLS/WS + IP publik
/etc/ssh-vpn/accounts.db           # Database akun SSH (user:dibuat:kedaluwarsa)
/etc/xray/config.json              # Konfigurasi Xray/V2Ray (5 inbound)
```

```
/etc/xray/params                   # UUID server, kunci REALITY, port inbound
/etc/xray/accounts.db              # Database user Xray (nama:uuid:dibuat)
/etc/vpn/lang                      # v1.3 pilihan bahasa ("en" atau "id")
```

---

## ⚙️ Prasyarat

1. **Server Linux** (VPS direkomendasikan) dengan salah satu OS yang didukung.
2. **Akses root** — semua skrip harus dijalankan sebagai root / via `sudo`.
3. **Perangkat TUN** tersedia (`/dev/net/tun`). Hampir semua VPS KVM sudah aktif. Untuk OpenVZ/LXC, aktifkan TUN di panel provider dulu.
4. **Koneksi internet** di server untuk download paket (apt/dnf) dan binary GitHub (Xray/Shadowsocks).
5. **Port bebas & terbuka** di firewall cloud provider: UDP 51820 (WireGuard), TCP 22/80/143/444 (SSH), TCP 443/10001-10004 (Xray).
6. **Python 3** di server (umumnya sudah bawaan; dipakai modul Xray untuk edit JSON aman).

---

## 🚀 Cara Instalasi

### 1. Clone repository ke server Linux

```bash
git clone https://github.com/mobatmabet99/vpn.git
cd vpn
chmod +x *.sh
```

### 2. Jalankan installer sebagai root

Mode interaktif — Anda memilih bahasa instalasi (**default: English**, tekan Enter saja),
layanan login (SSH/OpenVPN, **default: SSH**) dan engine tunnel (Xray/V2Ray, **default: Xray**):

```bash
sudo ./install.sh
```

```
Choose installation language / Pilih bahasa instalasi:
  1) English (default)
  2) Indonesia
Select [1-2] / Pilih [1-2] (default 1 - English):
```

Mode non-interaktif — langsung default penuh (**WireGuard + SSH + Xray**, English, cocok untuk automation):

```bash
sudo ./install.sh --yes
```

Varian non-interaktif lain:

```bash
# WireGuard + OpenVPN + V2Ray (tanpa SSH & Xray)
sudo ./install.sh --with-openvpn --with-v2ray --yes

# Default + Shadowsocks sekalian
sudo ./install.sh --with-shadowsocks --yes

# Installer Bahasa Indonesia, non-interaktif
sudo ./install.sh --lang id --yes

# Minimalis: hanya WireGuard
sudo ./install.sh --no-ssh --no-xray --yes

# Pilih engine via environment variable
XRAY_ENGINE=v2ray sudo ./install.sh --yes
```

Lihat semua opsi:

```bash
./install.sh --help
```

| Flag | Efek |
|---|---|
| `--with-ssh` / `--no-ssh` | Pasang / jangan pasang SSH VPN (default: pasang) |
| `--with-openvpn` | Pasang OpenVPN **pengganti** SSH (saling eksklusif, bisa dikombinasi manual) |
| `--with-xray` / `--with-v2ray` / `--no-xray` | Pilih engine tunnel (default: Xray). `--with-v2ray` = engine v2ray-core |
| `--with-shadowsocks` | Tambah Shadowsocks sekalian (default: tidak) |
| `--lang en\|id` | Bahasa instalasi (default: en). Juga via env `VPN_LANG=en\|id` |
| `-p/-c/-d/-y` | Port WG, nama client pertama, DNS, mode non-interaktif |

### 3. Apa yang dilakukan `install.sh` secara berurutan

1. Validasi root & keberadaan `/dev/net/tun`.
2. Tanya bahasa instalasi (default English), simpan ke `/etc/vpn/lang`.
3. Deteksi OS (Ubuntu/Debian/RHEL/...) — distro asing diberi peringatan dan diminta konfirmasi, kecuali dipaksa.
4. Deteksi interface jaringan utama & IP publik server.
5. Tanya/pakai parameter (port, DNS, nama client, pilihan SSH-vs-OpenVPN, pilihan Xray-vs-V2Ray).
6. Validasi port & nama client, lalu cek apakah port UDP sudah dipakai aplikasi lain.
6. Instal paket WireGuard + aktifkan IP forwarding & optimasi throughput (BBR, buffer TCP).
7. Buka port UDP WireGuard di UFW / firewalld.
8. Generate server keypair, tulis `wg0.conf` (MTU 1420 + NAT `PostUp`/`PostDown`), simpan `params`.
9. Buat client WireGuard pertama + `.conf` + QR Code, lalu enable & start `wg-quick@wg0`.
10. **Pasang SSH VPN** (default): OpenSSH hardening + Dropbear:143 + Stunnel:444 + WebSocket:80.
11. **Pasang Xray-core** (default): 5 inbound VMess/VLESS/Trojan + XTLS-Vision + REALITY:443 + link koneksi & QR.
12. (Opsional) OpenVPN / Shadowsocks bila diminta.
13. Tampilkan ringkasan + perintah cepat.

### 4. Alternatif: pakai menu interaktif

```bash
sudo ./menu.sh
sudo ./menu.sh --lang id   # paksa Bahasa Indonesia untuk sesi ini
```

Menu 0–17: instal WG, tambah/hapus client WG, tampil QR, daftar client, cek status, instal SSH / OpenVPN / Xray / V2Ray / Shadowsocks, kelola akun SSH, kelola user Xray, mulai ulang service, cek limit, ganti bahasa (17), uninstall.

---

## 👤 WireGuard — Tambah / Hapus Client

```bash
sudo ./add-client.sh                 # interaktif (tanya limit IP & bandwidth)
sudo ./add-client.sh hp-andi         # langsung (limit default 2 IP / 100 GB)
sudo ./add-client.sh hp-andi 3 200   # langsung (limit 3 IP / 200 GB)
sudo ./remove-client.sh hp-andi      # hapus (peer dihapus live + IP dipakai ulang)
sudo ./list-clients.sh               # daftar + handshake terakhir + trafik up/down
sudo ./show-qr.sh hp-andi            # tampilkan ulang QR + .conf
```

Aturan nama: huruf, angka, `-`, `_` saja, maksimal 32 karakter.

- **Android / iOS:** aplikasi *WireGuard* → tambah tunnel → *Scan from QR code*.
- **Windows / macOS / Linux Desktop:** aplikasi *WireGuard* → *Import tunnel(s) from file* → pilih `.conf` → *Activate*.

---

## 🔑 SSH VPN — Kelola Akun

Layanan default kedua setelah WireGuard. Port: OpenSSH **22**, Dropbear **143**, SSH-over-TLS **444**, SSH-over-WS **80**.

```bash
sudo ./add-ssh-user.sh                    # interaktif (tanya limit IP & bandwidth)
sudo ./add-ssh-user.sh andi               # password acak, berlaku 30 hari (limit default)
sudo ./add-ssh-user.sh andi 'R4h4s1a!' 90 # password sendiri, berlaku 90 hari
sudo ./add-ssh-user.sh andi '' 30 3 200   # limit 3 IP / 200 GB
sudo ./remove-ssh-user.sh andi            # hapus (sesi aktif ikut dimatikan)
```

Contoh koneksi dari laptop/HP:

```bash
ssh -p 22 andi@IP-SERVER
```

Untuk aplikasi tunneling (HTTP Custom, dsb.): gunakan host `IP-SERVER`, port WS `80` dengan payload WebSocket standar, atau port TLS `444` untuk SSH over TLS.

---

## ⚡ Xray / V2Ray — Kelola User (VMess / VLESS / Trojan + XTLS / REALITY)

Satu user = 1 UUID yang langsung aktif di **semua 5 inbound**:

| # | Protokol | Port | Cocok untuk |
|---|---|---|---|
| 1 | **VLESS + TCP + XTLS-Vision + REALITY** | 443 | **Utama** — paling efisien & anti-blokir, tanpa domain/TLS sendiri (SNI `www.microsoft.com`) |
| 2 | VLESS + TCP + XTLS-Vision | 10004 | Cepat di jaringan bersih / balik TLS terminator sendiri |
| 3 | VMess + WebSocket (`/vmess`) | 10001 | Kompatibilitas client lama |
| 4 | VLESS + WebSocket (`/vless`) | 10002 | Balik CDN/reverse-proxy (Cloudflare dsb.) |
| 5 | Trojan + WebSocket (`/trojan`) | 10003 | Samaran trafik HTTPS |

```bash
sudo ./add-xray-user.sh hp-andi       # buat user + cetak 5 link + QR REALITY (limit default)
sudo ./add-xray-user.sh hp-andi 3 200 # buat user dengan limit 3 IP / 200 GB
sudo ./remove-xray-user.sh hp-andi    # hapus dari semua inbound
```

Aplikasi client yang disarankan: Android **v2rayNG / NekoBox**, iOS **Streisand / FoXray / Shadowrocket**, Desktop **Nekoray / Hiddify**. Prioritas: **VLESS REALITY > VLESS XTLS > VMess/VLESS/Trojan WS**. Salin link diawali `vless://...security=reality...` untuk hasil terbaik.

Ganti engine default (`xray` → `v2ray`) saat instal: `sudo ./install.sh --with-v2ray --yes` atau `XRAY_ENGINE=v2ray sudo ./install.sh --yes`.

---

## ⏱️ Limit IP & Bandwidth — Auto-Suspend 5 Menit (v1.2, wrwb Store)

Setiap akun baru menanyakan **Limit IP concurrent** dan **Limit Bandwidth
(GB/bulan)**. Kosongkan jawaban = default **2 IP** & **100 GB**.

```bash
sudo ./check-limits.sh          # tabel semua user: limit, kuota terpakai, IP aktif, status
sudo ./check-limits.sh hp-andi  # cek satu user saja
```

Aturan main:

- Monitor systemd `vpn-limits` berjalan tiap **60 detik**, menghitung **IP unik
  aktif** per user (SSH via `who`/`ss`, WireGuard via endpoint aktif, Xray via
  access log) dalam jendela 10 menit.
- Jika IP aktif **melebihi limit** → user di-**suspend 5 menit** (300 detik),
  semua sesi di database **dibersihkan**, dan proses SSH user dimatikan.
- Setelah 5 menit, suspend kedaluwarsa **otomatis** + sesi dibersihkan lagi,
  sehingga login berikutnya dihitung dari nol (benar).
- Pemakaian bandwidth WireGuard dikumpulkan otomatis dari `wg show` dan
  di-reset tiap awal bulan. Status `OVER-KUOTA` tampil di `check-limits.sh`.
- Menghapus akun (`remove-*.sh`) otomatis menghapus data limitnya.

---

## 📋 Perintah Operasional Lainnya

```bash
# Diagnostik server (service, forwarding, TUN, NAT, firewall, bahasa, limit)
sudo ./status.sh

# Mulai ulang layanan WireGuard manual
sudo systemctl restart wg-quick@wg0
sudo wg show   # lihat handshake & transfer per peer

# Ganti bahasa (menu 17)
sudo ./menu.sh

# Hapus bersih seluruh VPN dari server (dengan backup darurat di /root/)
sudo ./uninstall.sh
```

---

## 🛡️ Detail Keamanan & Jaringan

- **WireGuard:** keypair Curve25519 unik per client + PSK (quantum-resistance), file sensitif `600`/direktori `700`, `SaveConfig = false`, `MTU = 1420`, `PersistentKeepalive = 25`.
- **SSH:** `PermitRootLogin no`, `MaxAuthTries 3`, `PasswordAuthentication yes` (untuk akun VPN), user `nologin` + tanggal kedaluwarsa, sesi user mati saat akun dihapus.
- **Xray/REALITY:** kunci x25519 + shortId acak per server, `dest`/`SNI` domain besar TLSv1.3+H2, fingerprint `chrome`, flow `xtls-rprx-vision` (menghindari TLS-in-TLS).
- **OpenVPN:** `data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305`, `auth SHA512`, `tls-version-min 1.3`, `tls-crypt`, Easy-RSA 3 PKI + CRL revocation.
- **NAT/Masquerade** di-`PostUp` saat `wg0` naik:
  ```bash
  iptables -I FORWARD -i %i -j ACCEPT
  iptables -I FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  iptables -t nat -I POSTROUTING -o <iface-utama> -j MASQUERADE
  ```
  (plus padanannya untuk `ip6tables`), dan dibersihkan otomatis di `PostDown`.
- **UFW:** bila aktif, semua port dibuka + `DEFAULT_FORWARD_POLICY` diubah ke `ACCEPT`.
- **firewalld:** bila aktif, semua port dibuka + `masquerade` permanen.

---

## ❓ Troubleshooting (FAQ)

| Gejala | Penyebab Umum & Solusi |
|---|---|
| `harus dijalankan sebagai root` | Jalankan dengan `sudo`, misal `sudo ./install.sh`. |
| `/dev/net/tun tidak tersedia` | VPS OpenVZ/LXC tanpa TUN. Aktifkan TUN di panel provider, atau pindah ke VPS KVM. |
| `wg-quick@wg0 gagal berjalan` | Lihat log: `journalctl -u wg-quick@wg0 -n 50 --no-pager`. Umumnya karena port bentrok — ganti port saat instalasi. |
| Client connect tapi tidak bisa internet | Pastikan forwarding aktif (`cat /proc/sys/net/ipv4/ip_forward` harus `1`), cek NAT (`iptables -t nat -L -n`), dan pastikan firewall cloud provider membuka port UDP. |
| `Port sudah dipakai` | Instalasi otomatis memberi peringatan — cek dengan `ss -lnup \| grep 51820`, pilih port lain via `./install.sh --port 51821`. |
| Service `xray` gagal start | Validasi config: `/usr/local/bin/xray run -test -config /etc/xray/config.json`; lihat log `journalctl -u xray -n 50 --no-pager` (umumnya port 443 bentrok dengan web server). |
| REALITY tidak connect | Pastikan jam server akurat (NTP), SNI `serverNames` cocok dengan `serverName` client, dan `pbk`/`sid` disalin persis dari link server. |
| QR tidak tampil di terminal | Terminal tidak dukung ANSI-UTF8 — gunakan file PNG di `/etc/wireguard/clients/<nama>/` atau salin link Xray manual. |
| OS baru (mis. Ubuntu 26 / Debian 13) diperingatkan "belum teruji" | Lanjut dengan `y`, atau set `FORCE_OS=1`. Laporkan hasilnya via Issues agar daftar resmi diperbarui. |
| Bahasa salah | Jalankan ulang `sudo ./menu.sh` → 17, atau `VPN_LANG=id sudo ./status.sh`, atau `echo id \| sudo tee /etc/vpn/lang`. |

---

## 🔧 Kustomisasi Cepat

- **Ganti port default:** edit `DEFAULT_PORT` di `install.sh`, atau instal dengan `--port <nomor>`.
- **Ganti subnet VPN:** edit `DEFAULT_SUBNET`/`DEFAULT_SERVER_IP` di `install.sh` dan `base_v4`/`base_v6` di `lib/wireguard.sh` (pastikan konsisten di `wg_write_server_conf` dan `wg_get_next_ip`).
- **Ganti DNS default:** edit `DEFAULT_DNS` di `install.sh`.
- **Ganti bahasa default:** tidak perlu edit kode — gunakan `--lang en|id`, `VPN_LANG=id`, atau menu 17. File: `/etc/vpn/lang`.
- **Ganti versi Xray/V2Ray:** edit `XRAY_VERSION_DEFAULT` (`v26.3.27`) / `V2RAY_VERSION_DEFAULT` (`v5.53.0`) di `lib/xray.sh` — cek rilis terbaru di [Xray-core releases](https://github.com/XTLS/Xray-core/releases) dan [v2ray-core releases](https://github.com/v2fly/v2ray-core/releases).
- **Ganti port inbound Xray:** edit `XPORT_VMESS_WS` / `XPORT_VLESS_WS` / `XPORT_TROJAN_WS` / `XPORT_VLESS_XTLS` / `XPORT_VLESS_REALITY` di `lib/xray.sh` sebelum instalasi.
- **Ganti SNI REALITY:** edit `XREALITY_SNI_DEFAULT` / `XREALITY_DEST_DEFAULT` di `lib/xray.sh` (syarat: domain asing, TLSv1.3 + H2, tidak redirect).
- **Ganti versi Shadowsocks:** edit `SS_VERSION_DEFAULT` di `lib/shadowsocks.sh` (default: `v1.25.0`, cek [shadowsocks-rust releases](https://github.com/shadowsocks/shadowsocks-rust/releases)).
- **Ganti cipher Shadowsocks:** edit `SS_METHOD_DEFAULT` di `lib/shadowsocks.sh` (default AEAD-2022 `2022-blake3-aes-256-gcm`; hemat CPU: `2022-blake3-aes-128-gcm`).
- **Nonaktifkan IPv6 client:** hapus `, ::/0` dari `AllowedIPs` saat generate profil (atau edit manual file `.conf` client).
- **Ganti default limit:** edit `DEFAULT_MAX_IP` (2) / `DEFAULT_MAX_GB` (100) di `lib/limits.sh`; durasi suspend via `SUSPEND_SECONDS_DEFAULT` (300 = 5 menit).

---

## 🤝 Kontribusi

Pull request & Issues sangat diterima — terutama laporan kompatibilitas untuk distro baru (Ubuntu 26, Debian 13) dan perbaikan aturan firewall/NAT. Jalankan cek sintaks sebelum commit bila `bash` tersedia:

```bash
for f in *.sh lib/*.sh; do bash -n "$f" && echo "OK: $f"; done
```

---

## 📄 Lisensi

Bebas digunakan untuk keperluan pribadi maupun komersial. Disediakan "sebagaimana adanya" tanpa garansi. Pastikan kepatuhan terhadap hukum/ToS provider jaringan Anda saat menjalankan layanan VPN.

---
Dibuat oleh **wrwb Store** — v1.3 (Bilingual EN/ID, default English + Limit 2 IP & 100 GB, auto-suspend 5 menit).
