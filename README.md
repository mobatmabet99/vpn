# VPN Auto-Installer — WireGuard Multi-Distro Linux

Skrip **otomatisasi instalasi VPN siap pakai** berbasis **WireGuard** dengan opsi tambahan **OpenVPN** dan **Shadowsocks**. Dibuat modular, aman, dan kompatibel dengan banyak distro Linux — dari versi lama sampai terbaru.

> Dibuat untuk Linux Server (VPS / Bare Metal). Bukan untuk dijalankan di Windows — upload / clone repo ini ke server Linux Anda.

---

## ✨ Fitur Utama

| Fitur | Detail |
|---|---|
| 🔌 **Protokol utama** | WireGuard (modern, cepat, aman) dengan auto-generate keypair server + client, Pre-Shared Key (PSK), file `.conf` client & QR Code (PNG + ANSI terminal) |
| 🔌 **Protokol opsional** | OpenVPN (port 1194/UDP + profil `.ovpn`) dan Shadowsocks (AEAD `aes-256-gcm` + URI `ss://` + QR) |
| 🖥️ **Dukungan OS** | Ubuntu 20.04 / 22.04 / 24.04 / 26.04 LTS, Debian 10 / 11 / 12 / 13, CentOS / Rocky / AlmaLinux 8 / 9, RHEL 8/9, Fedora |
| 🛡️ **Firewall otomatis** | Membuka port VPN di **UFW** (Debian/Ubuntu) atau **firewalld** (RHEL/Rocky) |
| 🌐 **IP Forwarding** | Mengaktifkan `net.ipv4.ip_forward=1` + IPv6 forwarding secara persisten (`/etc/sysctl.d/99-vpn-forward.conf`) |
| 🔀 **NAT / Masquerade** | Aturan `iptables ... -j MASQUERADE` otomatis via `PostUp`/`PostDown` WireGuard agar internet client berjalan |
| 📦 **Modular** | Kode dipisah: `install.sh`, `add-client.sh`, `remove-client.sh`, `list-clients.sh`, `show-qr.sh`, `status.sh`, `menu.sh`, `uninstall.sh`, plus library di `lib/` |
| ⚠️ **Error handling** | Wajib root/sudo, cek `/dev/net/tun`, deteksi OS + peringatan distro belum teruji, cek port & dependensi, validasi nama client, backup konfigurasi lama |

---

## 📁 Struktur Repository

```
vpn/
├── install.sh          # Instalasi server WireGuard (+ opsi OpenVPN/Shadowsocks)
├── add-client.sh       # Tambah client WireGuard baru
├── remove-client.sh    # Hapus client WireGuard
├── list-clients.sh     # Daftar client + statistik trafik & handshake terakhir
├── show-qr.sh          # Tampilkan ulang QR Code / .conf client
├── status.sh           # Diagnostik: service, forwarding, TUN, NAT, firewall
├── menu.sh             # Menu interaktif (panel kontrol)
├── uninstall.sh        # Hapus bersih seluruh instalasi VPN
├── lib/
│   ├── common.sh       # Logging, deteksi OS, validasi, helper jaringan, params
│   ├── system.sh       # Instal paket, IP forwarding, firewall (UFW/firewalld)
│   ├── wireguard.sh    # Inti WireGuard: server conf, alokasi IP, CRUD client
│   ├── openvpn.sh      # Modul opsional OpenVPN + Easy-RSA
│   └── shadowsocks.sh  # Modul opsional Shadowsocks-rust
├── README.md
└── .gitattributes      # Memaksa LF endings agar skrip aman di Linux
```

File konfigurasi yang dihasilkan di server:

```
/etc/wireguard/wg0.conf            # Konfigurasi server
/etc/wireguard/params              # Parameter server (IP publik, port, DNS, ...)
                                     # (di-source oleh add/remove client)
/etc/wireguard/clients/<nama>/
    ├── <nama>.conf                # Profil client (import ke aplikasi WireGuard)
    ├── <nama>.png                 # QR code (untuk HP/tablet)
    ├── private.key / public.key
    └── preshared.key
```

---

## ⚙️ Prasyarat

1. **Server Linux** (VPS direkomendasikan) dengan salah satu OS yang didukung.
2. **Akses root** — semua skrip harus dijalankan sebagai root / via `sudo`.
3. **Perangkat TUN** tersedia (`/dev/net/tun`). Hampir semua VPS KVM sudah aktif. Untuk OpenVZ/LXC, aktifkan TUN di panel provider dulu.
4. **Koneksi internet** di server untuk download paket (apt/dnf) dan deteksi IP publik.
5. **Port UDP 51820** (default WireGuard) belum dipakai aplikasi lain dan terbuka di firewall cloud provider (contoh: Security Group AWS, Firewall DigitalOcean, dsb).

---

## 🚀 Cara Instalasi

### 1. Clone repository ke server Linux

```bash
git clone https://github.com/<username-anda>/vpn.git
cd vpn
chmod +x *.sh
```

### 2. Jalankan installer sebagai root

Mode interaktif (ditanya port, DNS, nama client, opsi OpenVPN/Shadowsocks):

```bash
sudo ./install.sh
```

Mode non-interaktif (langsung pakai default, cocok untuk automation):

```bash
sudo ./install.sh --yes
```

Dengan parameter kustom:

```bash
sudo ./install.sh --port 51820 --client hp-utama --dns "1.1.1.1, 1.0.0.1" --yes
```

Sekaligus pasang OpenVPN + Shadowsocks:

```bash
sudo ./install.sh --with-openvpn --with-shadowsocks --yes
```

Lihat semua opsi:

```bash
./install.sh --help
```

### 3. Apa yang dilakukan `install.sh` secara berurutan

1. Validasi root & keberadaan `/dev/net/tun`.
2. Deteksi OS (Ubuntu/Debian/RHEL/...) — menolak lanjut jika distro asing kecuali dipaksa.
3. Deteksi interface jaringan utama & IP publik server.
4. Instal paket: `wireguard`, `wireguard-tools`, `iptables`, `qrencode`, `curl`, `iproute2`.
5. Aktifkan IP forwarding IPv4 (+ IPv6 bila tersedia).
6. Buka port UDP di UFW / firewalld.
7. Generate server keypair WireGuard (`wg genkey | wg pubkey`).
8. Tulis `/etc/wireguard/wg0.conf` lengkap dengan aturan NAT `PostUp`/`PostDown`.
9. Simpan `/etc/wireguard/params` untuk dipakai skrip lain.
10. Buat client pertama + file `.conf` + QR Code (PNG & tampil di terminal).
11. Enable & start `wg-quick@wg0` via systemd.
12. (Opsional) Setup OpenVPN / Shadowsocks bila diminta.
13. Tampilkan ringkasan + QR code client pertama.

### 4. Alternatif: pakai menu interaktif

```bash
sudo ./menu.sh
```

Menu berisi: instal, tambah/hapus client, tampil QR, daftar client, cek status, instal OpenVPN/Shadowsocks, restart service, uninstall.

---

## 👤 Menambah Client / User Baru

```bash
# Interaktif (ditanya nama client)
sudo ./add-client.sh

# Langsung dengan nama
sudo ./add-client.sh hp-andi
sudo ./add-client.sh laptop-kerja
```

Aturan nama client: huruf, angka, `-`, `_` saja, maksimal 32 karakter (contoh valid: `hp-andi`, `laptop_kerja`, `tablet01`).

Hasil setiap client:

- `/etc/wireguard/clients/<nama>/<nama>.conf` — import ke aplikasi WireGuard (laptop/desktop).
- QR Code tampil di terminal + tersimpan sebagai PNG — scan dari aplikasi WireGuard di HP.
- IP dialokasikan otomatis dari subnet `10.66.66.0/24` (`10.66.66.2`, `.3`, dst.) + IPv6 `fd42:42:42::/64`.
- Peer langsung dimuat ke interface `wg0` yang sedang berjalan tanpa memutus koneksi lama.

### Cara pakai di perangkat client

- **Android / iOS:** instal aplikasi *WireGuard* → tambah tunnel → *Scan from QR code* → arahkan ke QR di terminal, atau import file `.png`/`.conf`.
- **Windows / macOS / Linux Desktop:** instal aplikasi *WireGuard* → *Import tunnel(s) from file* → pilih file `.conf` → *Activate*.

---

## 🗑️ Menghapus Client / User

```bash
# Interaktif (pilih dari daftar bernomor)
sudo ./remove-client.sh

# Langsung dengan nama
sudo ./remove-client.sh hp-andi
```

Skrip akan: menghapus peer dari interface `wg0` yang berjalan (via `wg set ... remove`), menghapus blok `[Peer]` dari `wg0.conf`, dan menghapus folder `/etc/wireguard/clients/<nama>/`. IP yang dibebaskan akan dipakai ulang oleh client baru berikutnya.

---

## 📋 Perintah Operasional Lainnya

```bash
# Daftar client + status handshake terakhir + pemakaian download/upload
sudo ./list-clients.sh

# Tampilkan ulang QR code & isi .conf client tertentu
sudo ./show-qr.sh hp-andi

# Diagnostik server (service, forwarding, TUN, NAT, firewall)
sudo ./status.sh

# Restart layanan WireGuard manual
sudo systemctl restart wg-quick@wg0
sudo wg show   # lihat handshake & transfer per peer

# Hapus bersih seluruh VPN dari server (dengan backup darurat di /root/)
sudo ./uninstall.sh
```

---

## 🛡️ Detail Keamanan & Jaringan

- **Kunci kriptografi:** setiap client punya keypair Curve25519 unik + Pre-Shared Key (PSK) untuk hardening terhadap serangan quantum.
- **File sensitif** (`wg0.conf`, `params`, private key) diset permission `600`, direktori `700`.
- **Server config** memakai `SaveConfig = false` agar edit manual via skrip tidak tertimpa.
- **NAT/Masquerade** di-`PostUp` saat `wg0` naik:
  ```bash
  iptables -I FORWARD -i %i -j ACCEPT
  iptables -I FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  iptables -t nat -I POSTROUTING -o <iface-utama> -j MASQUERADE
  ```
  (plus padanannya untuk `ip6tables`), dan dibersihkan otomatis di `PostDown`.
- **UFW:** bila aktif, port dibuka + `DEFAULT_FORWARD_POLICY` diubah ke `ACCEPT` agar forwarding jalan.
- **firewalld:** bila aktif, port dibuka + `masquerade` diaktifkan permanen.
- **PersistentKeepalive = 25** di profil client agar koneksi stabil di belakang NAT.

---

## ❓ Troubleshooting (FAQ)

| Gejala | Penyebab Umum & Solusi |
|---|---|
| `harus dijalankan sebagai root` | Jalankan dengan `sudo`, misal `sudo ./install.sh`. |
| `/dev/net/tun tidak tersedia` | VPS OpenVZ/LXC tanpa TUN. Aktifkan TUN di panel provider, atau pindah ke VPS KVM. |
| `wg-quick@wg0 gagal berjalan` | Lihat log: `journalctl -u wg-quick@wg0 -n 50 --no-pager`. Umumnya karena port bentrok — ganti port saat instalasi. |
| Client connect tapi tidak bisa internet | Pastikan forwarding aktif (`cat /proc/sys/net/ipv4/ip_forward` harus `1`), cek NAT (`iptables -t nat -L -n`), dan pastikan firewall cloud provider membuka port UDP. |
| `Port sudah dipakai` | Cek dengan `ss -lnup \| grep 51820`, pilih port lain via `./install.sh --port 51821`. |
| QR tidak tampil di terminal | Terminal tidak dukung ANSI-UTF8 — gunakan file PNG di `/etc/wireguard/clients/<nama>/`. |
| OS baru (mis. Ubuntu 26 / Debian 13) diperingatkan "belum teruji" | Lanjut dengan `y`, atau set `FORCE_OS=1`. Laporkan hasilnya via Issues agar daftar resmi diperbarui. |

---

## 🔧 Kustomisasi Cepat

- **Ganti port default:** edit `DEFAULT_PORT` di `install.sh`, atau instal dengan `--port <nomor>`.
- **Ganti subnet VPN:** edit `DEFAULT_SUBNET`/`DEFAULT_SERVER_IP` di `install.sh` dan `base_v4`/`base_v6` di `lib/wireguard.sh` (pastikan konsisten di `wg_write_server_conf` dan `wg_get_next_ip`).
- **Ganti DNS default:** edit `DEFAULT_DNS` di `install.sh`.
- **Nonaktifkan IPv6 client:** hapus `, ::/0` dari `AllowedIPs` saat generate profil (atau edit manual file `.conf` client).

---

## 🤝 Kontribusi

Pull request & Issues sangat diterima — terutama laporan kompatibilitas untuk distro baru (Ubuntu 26, Debian 13) dan perbaikan aturan firewall/NAT. Jalankan cek sintaks sebelum commit bila `bash` tersedia:

```bash
for f in *.sh lib/*.sh; do bash -n "$f" && echo "OK: $f"; done
```

---

## 📄 Lisensi

Bebas digunakan untuk keperluan pribadi maupun komersial. Disediakan "sebagaimana adanya" tanpa garansi. Pastikan kepatuhan terhadap hukum/ToS provider jaringan Anda saat menjalankan layanan VPN.
