# Changelog — VPN Auto-Installer Multi-Protocol

**Oleh**: wrwb Store  
**Repository**: VPN Multi-Protocol Linux Installer

Dokumen ini merangkum semua rilis dari v1.2 hingga v4.6. Detail lengkap setiap versi ada di folder `changelogs/`.

---

## 📚 Navigasi Cepat

- [v4.6 (Latest - 14 Oktober 2026)](#v46---dynamic-firewall-handling) — **Dynamic Firewall Handling**
- [v4.5 (14 Oktober 2026)](#v45---comprehensive-environment--access-checks--arm64-support) — Environment Checks + ARM64 Support
- [v4.4 (14 Oktober 2026)](#v44---enhanced-distro--package-manager-detection) — Enhanced OS Detection (20+ distros)
- [v4.3 (14 Oktober 2026)](#v43---organized-changelog-structure) — Organized Changelog Structure
- [v4.2 (14 Oktober 2026)](#v42---xhttp-transport-ultimate-http-stealth) — **XHTTP Transport (Port 80/443)**
- [v4.1 (14 Oktober 2026)](#v41---donation-support) — Donation Support (QRIS)
- [v4.0 (14 Oktober 2026)](#v40---grpc-support--xray-v261010) — gRPC Support + Xray v26.10.10
- [v3.3 (13 Oktober 2026)](#v33---telegram-bot-enhancements) — Telegram Bot Enhancements
- [v3.2 (13 Oktober 2026)](#v32---web-dashboard-polish) — Web Dashboard Polish
- [v3.1 (13 Oktober 2026)](#v31---auto-backup--monitoring) — Auto Backup & Monitoring
- [v3.0 (13 Oktober 2026)](#v30---web-dashboard--telegram-bot) — Web Dashboard + Telegram Bot
- [v2.0 (13 Oktober 2026)](#v20---ip--bandwidth-limits) — IP & Bandwidth Limits
- [v1.4 (13 Oktober 2026)](#v14---trilingual-support) — Trilingual Support (EN/ID/ZH)
- [v1.3 (13 Oktober 2026)](#v13---shadowsocks-support) — Shadowsocks Support
- [v1.2 (13 Oktober 2026)](#v12---initial-release) — Initial Release

---

## v4.6 — Dynamic Firewall Handling

**Tanggal**: 14 Oktober 2026
**Detail**: [changelogs/v4.6.md](changelogs/v4.6.md)

### 🔥 Highlight

**Penanganan Firewall Secara Dinamis — hanya tambah aturan bila filtering aktif**

- ✅ **Auto-detect backend**: UFW → firewalld → iptables → nft → none
- ✅ **Skip aturan bila tidak perlu** — VPS default (semua ACCEPT) tidak disentuh
- ✅ **Dukungan nftables native** — aturan di chain `inet filter input` yang ada
- ✅ **Idempotent** — re-run tidak pernah membuat aturan duplikat
- ✅ **Batch open/close** — setup Xray 10 port cukup 1 reload
- ✅ **Bug fix**: `close_firewall_port` kini benar-benar menghapus aturan iptables/nft

---

## v4.5 — Comprehensive Environment & Access Checks + ARM64 Support

**Tanggal**: 14 Oktober 2026  
**Detail**: [changelogs/v4.0-v4.5.md](changelogs/v4.0-v4.5.md)

### ✅ Highlight

**5-Step Comprehensive Environment Validation + Full ARM64 Support**

- ✅ **5-step environment check** — Root, CPU arch, Virtualization, TUN/TAP, OS
- ✅ **ARM64/aarch64 full support** — Oracle Cloud, AWS Graviton, Hetzner CAX, Raspberry Pi
- ✅ **Smart virtualization detection** — KVM, QEMU, VMware, Xen, Hyper-V, OpenVZ, LXC
- ✅ **TUN/TAP validation** — Auto-check dengan specific error messages
- ✅ **CPU architecture validation** — x86_64, aarch64, armv7 supported
- ✅ **Consolidated checks** — Clean, informative, user-friendly

### 5-Step Environment Check

1. **Root Access** — Verify UID 0
2. **CPU Architecture** — Detect x86_64 (amd64) or aarch64 (arm64)
3. **Virtualization Type** — KVM, QEMU, VMware, Xen, Hyper-V, OpenVZ, LXC
4. **TUN/TAP Device** — Check `/dev/net/tun` availability
5. **OS Detection** — Distro, version, package manager, kernel

### ARM64 VPS Support (NEW)

**Fully supported ARM64 providers**:
- Oracle Cloud ARM (Ampere Altra)
- AWS Graviton (a1, t4g, c6g, m6g)
- Hetzner Cloud CAX
- Scaleway ARM
- Raspberry Pi 4/5 (64-bit)
- Apple Silicon (via Linux VM)

### CPU Architecture Support

| Architecture | Status | Binary | Notes |
|--------------|--------|--------|-------|
| x86_64 (amd64) | ✅ Full | `64` | Most common |
| aarch64 (arm64) | ✅ Full | `arm64-v8a` | **NEW in v4.5** |
| armv7 (arm32) | ⚠️ Limited | `arm32-v7a` | WireGuard OK |
| i386 (32-bit) | ❌ Not supported | - | Use 64-bit |

---

## v4.4 — Enhanced Distro & Package Manager Detection

**Tanggal**: 14 Oktober 2026  
**Detail**: [changelogs/v4.0-v4.4.md](changelogs/v4.0-v4.4.md)

### 🔍 Highlight

**Auto-Detection & Auto-Adaptation untuk 20+ Linux Distros**

- ✅ **Auto-detect package manager** — apt/dnf/yum/pacman/zypper/apk/emerge/xbps/nix-env
- ✅ **Fallback detection** — jika OS tidak dikenali, detect dari command yang ada
- ✅ **20+ distro support** — Ubuntu, Debian, RHEL, Rocky, Alma, Fedora, Arch, Manjaro, Alpine, Gentoo, Void, SUSE, dll
- ✅ **Smart adaptation** — auto-pilih package manager yang tepat

### Distro Baru yang Didukung

**Debian Family**: Devuan, MX Linux, Deepin, Parrot OS  
**RHEL Family**: Scientific, Oracle, EuroLinux, CloudLinux  
**Arch Family**: Garuda, Artix, CachyOS  
**SUSE Family**: OpenSUSE Leap/Tumbleweed, SLES  
**Other**: Gentoo (emerge), Void Linux (xbps), NixOS (nix-env)

### Fallback Mechanism

Jika OS ID tidak dikenali:
1. Cek `apt-get` → Debian-based
2. Cek `dnf` → RHEL-based (modern)
3. Cek `yum` → RHEL-based (legacy)
4. Cek `pacman` → Arch-based
5. Cek `zypper` → SUSE-based
6. Cek `apk` → Alpine

---

## v4.3 — Organized Changelog Structure

**Tanggal**: 14 Oktober 2026

### Highlight

- 📚 **Reorganized changelogs** ke folder `changelogs/`
- 📖 **Master CHANGELOG.md** dengan complete version history
- 📊 **Protocol evolution table** (5 → 13 protocols)
- 🎯 **Quick navigation** untuk semua versions

---

## v4.2 — XHTTP Transport (Ultimate HTTP Stealth)

**Tanggal**: 14 Oktober 2026  
**Detail**: [changelogs/v4.0-v4.2.md](changelogs/v4.0-v4.2.md)

### 🚀 Highlight

**XHTTP: Transport terbaru Xray yang paling mirip HTTP real**

- ✅ **4 protokol XHTTP baru** di port 80/443 (paling stealth)
- ✅ **13 total protokol per user** (9 existing + 4 XHTTP baru)
- 🏆 **VLESS REALITY XHTTP @ Port 443** — Ultimate stealth, best choice
- ✅ **Traffic indistinguishable dari HTTP biasa** — bypass DPI
- ✅ **CDN compatible** — Cloudflare/Nginx/Caddy

### Protokol Baru

1. **VLESS + XHTTP + REALITY @ Port 443** (path `/reality-xhttp`) 🏆
2. **VMess + XHTTP @ Port 80** (path `/vmess-xhttp`)
3. **VLESS + XHTTP @ Port 80** (path `/vless-xhttp`)
4. **Trojan + XHTTP @ Port 80** (path `/trojan-xhttp`)

### Breaking Changes

- **SSH WebSocket pindah dari port 80 → 8080** (menghindari konflik dengan XHTTP)

### Port Mapping v4.2

- **Port 80**: VMess/VLESS/Trojan XHTTP (shared path routing)
- **Port 443**: VLESS REALITY TCP + VLESS REALITY XHTTP 🏆
- **Port 8080**: SSH WebSocket (moved from 80)
- **Port 10001-10008**: WebSocket & gRPC transports

---

## v4.1 — Donation Support

**Tanggal**: 14 Oktober 2026  
**Detail**: [changelogs/v4.0-v4.2.md](changelogs/v4.0-v4.2.md)

### Highlight

- ❤️ **Menu donasi QRIS** di `menu.sh` (menu #18)
- 📱 **QRIS image** dengan support display di terminal (catimg/viu)
- 📖 **Section donasi** di semua README (ID/EN/ZH)
- 🎨 Footer version update: v3 → v4.1

---

## v4.0 — gRPC Support + Xray v26.10.10

**Tanggal**: 14 Oktober 2026  
**Detail**: [changelogs/v4.0-v4.2.md](changelogs/v4.0-v4.2.md)

### Highlight

- ✅ **4 protokol gRPC baru** (HTTP/2 based, excellent for CDN)
- ✅ **Xray-core v26.10.10** (update dari v26.3.27, Oktober 2026)
- ✅ **9 total protokol per user** (5 existing + 4 gRPC baru)
- ✅ **Sangat stabil** di Debian 13 Trixie & Ubuntu 26.04 LTS

### Protokol gRPC Baru

1. **VMess + gRPC** @ Port 10005
2. **VLESS + gRPC** @ Port 10006
3. **Trojan + gRPC** @ Port 10007
4. **VLESS REALITY + gRPC** @ Port 10008 ⭐

### Keunggulan gRPC

- HTTP/2 based — multiplexing, header compression
- Latency rendah, lebih responsif dari WebSocket
- Cocok untuk CDN & reverse proxy
- Anti-deteksi (traffic tampak seperti HTTP/2 biasa)

---

## v3.3 — Telegram Bot Enhancements

**Tanggal**: 13 Oktober 2026  
**Detail**: [changelogs/v3.3.md](changelogs/v3.3.md)

### Highlight

- ✅ Telegram Bot commands expansion
- ✅ Better notification system
- ✅ User management via Telegram

---

## v3.2 — Web Dashboard Polish

**Tanggal**: 13 Oktober 2026  
**Detail**: [changelogs/v3.2.md](changelogs/v3.2.md)

### Highlight

- ✅ UI/UX improvements
- ✅ Real-time stats
- ✅ Mobile responsive design

---

## v3.1 — Auto Backup & Monitoring

**Tanggal**: 13 Oktober 2026  
**Detail**: [changelogs/v3.1.md](changelogs/v3.1.md)

### Highlight

- ✅ Automated daily backups
- ✅ System monitoring dashboard
- ✅ Email/Telegram alerts

---

## v3.0 — Web Dashboard + Telegram Bot

**Tanggal**: 13 Oktober 2026  
**Detail**: [changelogs/v3.0.md](changelogs/v3.0.md)

### Highlight

- 🎉 **Web Dashboard** (browser-based management)
- 🤖 **Telegram Bot** (remote management)
- 📊 **Real-time monitoring** (bandwidth, users, connections)
- 🔐 **Secure authentication** (password + 2FA)

---

## v2.0 — IP & Bandwidth Limits

**Tanggal**: 13 Oktober 2026  
**Detail**: [changelogs/v2.0.md](changelogs/v2.0.md)

### Highlight

- ✅ **Limit 2 IP simultan per user** (multi-login protection)
- ✅ **Limit 100 GB bandwidth per bulan** (quota management)
- ✅ **Auto-suspend 5 menit** bila multi-login
- ✅ **Bandwidth tracking** per user (WireGuard)

---

## v1.4 — Trilingual Support

**Tanggal**: 13 Oktober 2026  
**Detail**: [changelogs/v1.4.md](changelogs/v1.4.md)

### Highlight

- 🌐 **3 bahasa**: English, Indonesia, 中文 (Mandarin)
- ✅ **Dynamic language switching** (menu 17)
- ✅ **Persistent language preference** (`/etc/vpn/lang`)

---

## v1.3 — Shadowsocks Support

**Tanggal**: 13 Oktober 2026  
**Detail**: [changelogs/v1.3.md](changelogs/v1.3.md)

### Highlight

- ✅ **Shadowsocks-rust** support (optional)
- ✅ **AEAD-2022 cipher** (`2022-blake3-aes-256-gcm`)
- ✅ **Port 8388** default

---

## v1.2 — Initial Release

**Tanggal**: 13 Oktober 2026  
**Detail**: [changelogs/v1.2.md](changelogs/v1.2.md)

### Highlight

- 🎉 **WireGuard VPN** (main engine)
- ✅ **SSH VPN** (Dropbear + Stunnel + WebSocket)
- ✅ **Xray-core** (VMess/VLESS/Trojan + REALITY)
- ✅ **OpenVPN** (optional alternative)
- ✅ **Multi-distro support** (Ubuntu/Debian/RHEL/CentOS/Rocky/Alma)

---

## 📋 Protocol Evolution

| Version | Total Protocols | New Additions |
|---------|----------------|---------------|
| v1.2 | 5 | WireGuard, SSH, VMess/VLESS/Trojan WS, VLESS REALITY |
| v1.3 | 6 | + Shadowsocks |
| v1.4 | 6 | (Trilingual support, no new protocols) |
| v2.0 | 6 | (Limits & quota, no new protocols) |
| v3.0 | 6 | (Web dashboard + Bot, no new protocols) |
| v3.1-3.3 | 6 | (Features enhancement) |
| v4.0 | 9 | + 4 gRPC (VMess/VLESS/Trojan/REALITY) |
| v4.1 | 9 | (Donation support, no new protocols) |
| v4.2 | 13 | + 4 XHTTP (VMess/VLESS/Trojan/REALITY) 🏆 |
| v4.3 | 13 | (Changelog organization, no new protocols) |
| v4.4 | 13 | (Enhanced OS detection: 20+ distros) 🔍 |
| v4.5 | 13 | (Environment checks + ARM64 support) ✅ |
| **v4.6** | **13** | **(Dynamic firewall handling)** 🔥 |

---

## 🎯 Rekomendasi Protocol (v4.2)

**Priority order untuk koneksi terbaik**:

1. 🥇 **VLESS + XHTTP + REALITY @ Port 443** — Ultimate stealth, paling mirip HTTP
2. 🥈 **VLESS + TCP + REALITY @ Port 443** — Most efficient, XTLS-Vision
3. 🥉 **VLESS + gRPC + REALITY** — Best for CDN & heavy censorship
4. **VLESS + XHTTP @ Port 80** — HTTP stealth tanpa TLS
5. **VLESS + XTLS @ Port 10004** — Plain performance

---

## 📦 Installation

```bash
git clone https://github.com/mobatmabet99/vpn.git
cd vpn
sudo ./install.sh
```

**Quick options**:
```bash
# Non-interactive, all defaults
sudo ./install.sh --yes

# Bahasa Indonesia
sudo ./install.sh --lang id --yes

# Menu interaktif
sudo ./menu.sh
```

---

## 🔗 Links

- **Repository**: https://github.com/mobatmabet99/vpn
- **Issues**: https://github.com/mobatmabet99/vpn/issues
- **Changelog Details**: [changelogs/](changelogs/)

---

**Dibuat oleh wrwb Store** — v4.6 (Dynamic Firewall + Environment Checks + ARM64 + 13 Protocols)
