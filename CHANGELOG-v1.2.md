# Changelog v1.2 — Limit IP & Bandwidth + Auto-Suspend (wrwb Store)

Tanggal: 13 Oktober 2026
Dibuat oleh **wrwb Store**

## Ringkasan

Versi 1.2 menambahkan **fitur limit IP address dan limit bandwidth** yang diminta:
setiap pembuatan akun baru (WireGuard / SSH / Xray) kini menanyakan **Limit IP
concurrent** dan **Limit Bandwidth (GB/bulan)**. Jika dikosongkan (di-skip),
otomatis diisi nilai default **2 IP** dan **100 GB**.

Jika user terdeteksi **multi-login melebihi limit IP**, sistem otomatis:
1. **Suspend akun sementara selama 5 menit**, lalu
2. **Auto-clear semua sesi login user** agar perhitungan IP berikutnya fresh/benar.

## Poin Update

1. **Modul baru `lib/limits.sh`**
   - Database di `/var/lib/vpn-limits/` (`limits.db`, `usage.db`, `sessions.db`,
     `suspended.db`).
   - Default global: `DEFAULT_MAX_IP=2`, `DEFAULT_MAX_GB=100`,
     `SUSPEND_SECONDS_DEFAULT=300` (5 menit).
   - Deteksi sesi nyata dari sistem (bukan tebakan): sesi SSH via `who` +
     koneksi TCP `ss` ke port 22/143/444, endpoint WireGuard aktif via
     `wg show wg0 endpoints`, dan access log Xray bila tersedia.
   - Koleksi bandwidth WireGuard otomatis (delta `wg show wg0 dump` per peer,
     reset tiap bulan).
   - Suspend kedaluwarsa otomatis membersihkan sesi (perhitungan berikutnya benar).
2. **Prompt limit di pembuatan akun**
   - `add-client.sh [nama] [max_ip] [max_gb]` — tanya Limit IP & Bandwidth.
   - `add-ssh-user.sh [user] [pass] [hari] [max_ip] [max_gb]` — sama.
   - `add-xray-user.sh [nama] [max_ip] [max_gb]` — sama.
   - Kosongkan jawaban = default **2 IP / 100 GB**.
3. **Cleanup otomatis saat hapus akun**
   - `remove-client.sh`, `remove-ssh-user.sh`, `remove-xray-user.sh` kini
     memanggil `limits_remove` agar tidak ada data limit yatim.
4. **Monitor service `vpn-limits`**
   - `install.sh` otomatis mendaftarkan limit default client pertama (2 IP /
     100 GB) dan memasang service systemd `vpn-limits` (cek tiap 60 detik).
   - `menu.sh` item 16 + `check-limits.sh` untuk melihat tabel limit, pemakaian
     kuota, IP aktif, dan status SUSPEND/OVER-KUOTA.
   - `status.sh` menampilkan status monitor + user yang sedang di-suspend.
   - `uninstall.sh` membersihkan service, binary monitor, dan database limit.
5. **Branding wrwb Store**
   - Banner `install.sh`, banner + footer `menu.sh`, header semua skrip
     tambah/hapus akun, output `check-limits.sh`, `status.sh`, `uninstall.sh`,
     dan deskripsi service systemd kini mencantumkan **wrwb Store**.
6. **Kompatibilitas Debian 13 & Ubuntu 26.04**
   - `install_ssh_packages`: tambah `unzip` + fallback bila paket `dropbear`
     tidak tersedia (fungsi setup sudah skip aman).
   - Penanganan service `ssh` vs `sshd` sudah mencakup kedua nama unit.
   - `lib/limits.sh` hanya memakai sintaks POSIX/GNU yang tersedia di
     Debian 13 & Ubuntu 26.04 (`date -d`, `awk`, `grep -E`, `ss`, `who`).
   - Seluruh 21 file lolos `bash -n` tanpa error.

## Cara Pakai Singkat

```bash
# Buat akun dengan limit kustom (3 IP, 200 GB)
sudo ./add-client.sh hp-andi 3 200
sudo ./add-ssh-user.sh andi 'R4h4s1a!' 30 3 200
sudo ./add-xray-user.sh hp-andi 3 200

# Kosongkan = default 2 IP / 100 GB
sudo ./add-client.sh hp-budi

# Lihat semua limit + status suspend
sudo ./check-limits.sh
sudo ./check-limits.sh hp-andi
```

## Aturan Suspend

- Setiap 60 detik monitor menghitung **IP unik aktif** per user (jendela 10 menit).
- Jika IP aktif **> limit**, user masuk `suspended.db` selama **300 detik**,
  semua sesi di `sessions.db` dihapus, dan proses SSH user di-`pkill`.
- Setelah 5 menit, suspend kedaluwarsa otomatis + sesi dibersihkan lagi,
  sehingga login berikutnya dihitung dari nol (benar).
