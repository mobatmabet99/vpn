# VPN Auto-Installer — Multi-Protocol Linux (WireGuard + SSH + Xray + OpenVPN + Shadowsocks)

> Made by **wrwb Store** — Default limit 2 IPs & 100 GB, auto-suspend 5 minutes on multi-login.

**Ready-to-use automated VPN installer** based on **WireGuard** as the main engine, with **SSH VPN** and **Xray-core** installed **by default**, plus optional **OpenVPN**, **v2ray-core**, and **Shadowsocks**. Modular, secure, and compatible with many Linux distros — old to latest.

> Made for Linux Servers (VPS / Bare Metal). Not for running on Windows — clone this repo to your Linux server.
>
> 📖 Versi Indonesia: [README.md](README.md) (Bahasa Indonesia)
> 📖 中文版: [README.zh.md](README.zh.md) (简体中文)
>
> **New in v1.4:** trilingual installer **English (default) / Indonesia / 中文**. You are asked for language at install time — just press Enter for English. Details: [CHANGELOG-v1.4.md](CHANGELOG-v1.4.md).
>
> **New in v1.3:** bilingual installer **English (default) / Indonesia**. Details: [CHANGELOG-v1.3.md](CHANGELOG-v1.3.md).
>
> **New in v1.2:** every new account asks for **IP Limit** and **Bandwidth Limit**
> (default **2 IPs** & **100 GB/month** when skipped). Multi-login over limit =
> **auto-suspend 5 minutes + auto-clear sessions**. Details: [CHANGELOG-v1.2.md](CHANGELOG-v1.2.md).

---

## 🌐 Language / Bahasa / 语言

- Default language: **English**. Just press **Enter** at the language prompt.
- Select **2) Indonesia** for the Indonesian installer.
- 选择 **3) 中文** 为简体中文安装程序。
- Non-interactive / automation:
  ```bash
  sudo ./install.sh --yes                 # English (default)
  sudo ./install.sh --lang id --yes       # Indonesian
  sudo ./install.sh --lang zh --yes       # 中文
  VPN_LANG=zh sudo ./install.sh --yes     # via env var
  ```
- Choice is saved in `/etc/vpn/lang` (`en` / `id` / `zh`) and used by all scripts (`add-client.sh`, `menu.sh`, `status.sh`, ...).
- Switch anytime: `sudo ./menu.sh` → menu **17) Switch language**, or `sudo ./menu.sh --lang en|id|zh`.

---

## ✨ Main Features

| Feature | Detail |
|---|---|
| 🔌 **Main protocol** | WireGuard (ChaCha20-Poly1305, MTU 1420) with auto server + client keypair, Pre-Shared Key (PSK), client `.conf` files & QR Code (PNG + ANSI terminal) |
| 🔑 **SSH VPN (default ON)** | OpenSSH hardening + Dropbear (port 143) + SSH over TLS/Stunnel (port 444) + SSH over WebSocket (port 80). Account management: `add-ssh-user.sh` / `remove-ssh-user.sh` (with expiry) |
| ⚡ **Xray-core (default ON)** | v26.3.27 stable — 5 inbounds at once: VMess WS (10001), VLESS WS (10002), Trojan WS (10003), VLESS TCP XTLS-Vision (10004), **VLESS TCP XTLS-Vision + REALITY (443)**. 1 UUID works for all protocols + auto links & QR |
| 🔄 **Alternative engine** | v2ray-core v5.53.0 (switch via `--with-v2ray` or `XRAY_ENGINE=v2ray`); OpenVPN 2.7/2.6 (cipher `AES-256-GCM` + `CHACHA20-POLY1305`, auth `SHA512`, TLS min 1.3, `.ovpn` profile) as SSH replacement |
| 👻 **Shadowsocks (optional)** | shadowsocks-rust v1.25.0, AEAD-2022 cipher `2022-blake3-aes-256-gcm` + `ss://` URI + QR |
| 🖥️ **OS Support** | Ubuntu 20.04 / 22.04 / 24.04 / 26.04 LTS, Debian 10 / 11 / 12 / 13, CentOS / Rocky / AlmaLinux 8 / 9, RHEL 8/9, Fedora |
| 🛡️ **Auto firewall** | Opens all VPN ports (UDP + TCP) in **UFW** (Debian/Ubuntu) or **firewalld** (RHEL/Rocky) |
| 🌐 **IP Forwarding** | Enables `net.ipv4.ip_forward=1` + IPv6 forwarding persistently (`/etc/sysctl.d/99-vpn-forward.conf`) |
| 🚀 **Throughput tuning** | `MTU = 1420` on server & client, TCP BBR + 25 MB buffers via sysctl |
| 🔀 **NAT / Masquerade** | Automatic `iptables ... -j MASQUERADE` via WireGuard `PostUp`/`PostDown` so client internet works |
| 📦 **Modular** | `install.sh`, `add-client.sh`, `remove-client.sh`, `list-clients.sh`, `show-qr.sh`, `add-ssh-user.sh`, `remove-ssh-user.sh`, `add-xray-user.sh`, `remove-xray-user.sh`, `check-limits.sh`, `status.sh`, `menu.sh` (0-17), `uninstall.sh`, plus libraries in `lib/` (including `lib/lang.sh`, `lib/limits.sh`) |
| 🌐 **Trilingual (v1.4)** | English default, Indonesian + Chinese optional. Single codebase via `T "English" "Indonesia" "中文"` in `lib/lang.sh`, saved in `/etc/vpn/lang` |
| ⚠️ **Error handling** | Requires root/sudo, checks `/dev/net/tun`, OS detection + untested-distro warning, port & dependency checks, client/user name validation, old-config backup |
| ⏱️ **Limits & suspend (v1.2)** | Concurrent IP + monthly bandwidth GB limit per account (default 2 IPs & 100 GB). Multi-login over limit = 5-minute auto-suspend + auto-clear sessions. `vpn-limits` systemd monitor every 60 seconds |

---

## 📁 Repository Structure

```
vpn/
├── install.sh              # Install: WireGuard + SSH + Xray (default ON), asks language
├── add-client.sh           # Add new WireGuard client (asks IP & bandwidth limit)
├── remove-client.sh        # Remove WireGuard client (+ cleans limit data)
├── list-clients.sh         # List WG clients + traffic stats & handshake
├── show-qr.sh              # Re-show client WG QR Code / .conf
├── add-ssh-user.sh         # Create SSH VPN account (expiry + IP & bandwidth limit)
├── remove-ssh-user.sh      # Remove SSH VPN account (+ cleans limit data)
├── add-xray-user.sh        # Create Xray/V2Ray user + IP & bandwidth limit
├── remove-xray-user.sh     # Remove Xray/V2Ray user (+ cleans limit data)
├── check-limits.sh         # Show IP limits, quota, active IPs & suspend status
├── status.sh               # Diagnostics: services, forwarding, TUN, NAT, firewall, limits
├── menu.sh                 # Interactive menu 0-17 (wrwb Store control panel)
├── uninstall.sh            # Fully remove VPN install (+ limit monitor, + /etc/vpn/lang)
├── README.md               # Indonesian docs
├── README.en.md            # English docs (default, this file)
├── README.zh.md            # Chinese docs (简体中文)
├── CHANGELOG-v1.2.md       # v1.2 release notes (IP & bandwidth limits)
├── CHANGELOG-v1.3.md       # v1.3 release notes (bilingual EN/ID)
├── CHANGELOG-v1.4.md       # v1.4 release notes (trilingual EN/ID/ZH)
├── lib/
│   ├── lang.sh             # v1.4 trilingual core: T "EN" "ID" "ZH", /etc/vpn/lang
│   ├── common.sh           # Logging, OS detect, validation, network helpers, params
│   ├── system.sh           # Package install, IP forwarding, firewall (UFW/firewalld)
│   ├── wireguard.sh        # WireGuard core: server conf, IP alloc, client CRUD
│   ├── ssh.sh              # SSH module: OpenSSH+Dropbear+Stunnel+WebSocket, account CRUD
│   ├── xray.sh             # Xray/V2Ray module: VMess/VLESS/Trojan+XTLS/REALITY
│   ├── limits.sh           # v1.2 module: IP & bandwidth limits + 5-min auto-suspend
│   ├── openvpn.sh          # Alternative OpenVPN + Easy-RSA module
│   └── shadowsocks.sh      # Optional Shadowsocks-rust module
├── .gitattributes          # Forces LF endings so scripts stay safe on Linux
```

Generated config files on the server:

```
/etc/wireguard/wg0.conf            # WireGuard server config
/etc/wireguard/params              # Server params (sourced by other WG scripts)
/etc/wireguard/clients/<name>/
    ├── <name>.conf                # Client profile (import into WireGuard app)
    ├── <name>.png                 # QR code (for phones/tablets)
    └── private.key / public.key / preshared.key
/etc/vpn/lang                      # v1.4 language choice ("en" / "id" / "zh")
/etc/ssh-vpn/params                # SSH/Dropbear/TLS/WS ports + public IP
/etc/ssh-vpn/accounts.db           # SSH account DB (user:created:expiry)
/etc/xray/config.json              # Xray/V2Ray config (5 inbounds)
```

```
/etc/xray/params                   # Server UUID, REALITY keys, inbound ports
/etc/xray/accounts.db              # Xray user DB (name:uuid:created)
```

---

## ⚙️ Prerequisites

1. **Linux server** (VPS recommended) with a supported OS.
2. **Root access** — all scripts must run as root / via `sudo`.
3. **TUN device** available (`/dev/net/tun`). Almost all KVM VPS have it. For OpenVZ/LXC, enable TUN in the provider panel first.
4. **Internet** on the server for package downloads (apt/dnf) and GitHub binaries (Xray/Shadowsocks).
5. **Free & open ports** in the cloud firewall: UDP 51820 (WireGuard), TCP 22/80/143/444 (SSH), TCP 443/10001-10004 (Xray).
6. **Python 3** on the server (usually pre-installed; used by Xray module for safe JSON edits).

---

## 🚀 Installation

### 1. Clone the repo to your Linux server

```bash
git clone https://github.com/mobatmabet99/vpn.git
cd vpn
chmod +x *.sh
```

### 2. Run the installer as root

Interactive — you pick login service (SSH/OpenVPN, **default: SSH**) and tunnel engine (Xray/V2Ray, **default: Xray**), plus install language (default English):

```bash
sudo ./install.sh
```

```
Choose installation language / Pilih bahasa instalasi / 选择安装语言：
  1) English (default)
  2) Indonesia
  3) 中文 (简体)
Select [1-3] / Pilih [1-3] / 选择 [1-3] (default 1 - English):
```

Non-interactive — full defaults (**WireGuard + SSH + Xray**, good for automation, English):

```bash
sudo ./install.sh --yes
```

Other non-interactive variants:

```bash
# WireGuard + OpenVPN + V2Ray (no SSH & Xray)
sudo ./install.sh --with-openvpn --with-v2ray --yes

# Defaults + Shadowsocks
sudo ./install.sh --with-shadowsocks --yes

# Minimal: WireGuard only
sudo ./install.sh --no-ssh --no-xray --yes

# Indonesian installer, non-interactive
sudo ./install.sh --lang id --yes

# Chinese installer, non-interactive
sudo ./install.sh --lang zh --yes

# Pick engine via env var
XRAY_ENGINE=v2ray sudo ./install.sh --yes
```

See all options:

```bash
./install.sh --help
```

| Flag | Effect |
|---|---|
| `--with-ssh` / `--no-ssh` | Install / skip SSH VPN (default: install) |
| `--with-openvpn` | Install OpenVPN **instead of** SSH (mutually exclusive, can combine manually) |
| `--with-xray` / `--with-v2ray` / `--no-xray` | Pick tunnel engine (default: Xray). `--with-v2ray` = v2ray-core engine |
| `--with-shadowsocks` | Also add Shadowsocks (default: no) |
| `--lang en\|id\|zh` | Installer language (default: en). Also `VPN_LANG=en\|id\|zh` env |
| `-p/-c/-d/-y` | WG port, first client name, DNS, non-interactive mode |

### 3. What `install.sh` does in order

1. Validates root & `/dev/net/tun`.
2. Asks install language (default English), saves to `/etc/vpn/lang`.
3. Detects OS (Ubuntu/Debian/RHEL/...) — foreign distros get a warning + confirm, unless forced.
4. Detects main network interface & server public IP.
5. Asks/uses params (port, DNS, client name, SSH-vs-OpenVPN, Xray-vs-V2Ray).
6. Validates port & client name, checks if UDP port is used by another app.
7. Installs WireGuard packages + enables IP forwarding & throughput tuning (BBR, TCP buffers).
8. Opens WireGuard UDP port in UFW / firewalld.
9. Generates server keypair, writes `wg0.conf` (MTU 1420 + NAT `PostUp`/`PostDown`), saves `params`.
10. Creates first WireGuard client + `.conf` + QR Code, then enables & starts `wg-quick@wg0`.
11. **Installs SSH VPN** (default): OpenSSH hardening + Dropbear:143 + Stunnel:444 + WebSocket:80.
12. **Installs Xray-core** (default): 5 inbounds VMess/VLESS/Trojan + XTLS-Vision + REALITY:443 + connection links & QR.
13. (Optional) OpenVPN / Shadowsocks when requested.
14. Shows summary + quick commands.

### 4. Alternative: interactive menu

```bash
sudo ./menu.sh
sudo ./menu.sh --lang zh   # force Chinese for this run
```

Menu 0–17: install WG, add/remove WG client, show QR, list clients, check status, install SSH / OpenVPN / Xray / V2Ray / Shadowsocks, manage SSH accounts, manage Xray users, restart services, check limits, switch language (17), uninstall.

---

## 👤 WireGuard — Add / Remove Clients

```bash
sudo ./add-client.sh                 # interactive (asks IP & bandwidth limit)
sudo ./add-client.sh phone-andi      # direct (default limit 2 IPs / 100 GB)
sudo ./add-client.sh phone-andi 3 200 # direct (limit 3 IPs / 200 GB)
sudo ./remove-client.sh phone-andi   # remove (live peer delete + IP reuse)
sudo ./list-clients.sh               # list + last handshake + up/down traffic
sudo ./show-qr.sh phone-andi         # re-show QR + .conf
```

Name rule: letters, numbers, `-`, `_` only, max 32 chars.

- **Android / iOS:** *WireGuard* app → add tunnel → *Scan from QR code*.
- **Windows / macOS / Linux Desktop:** *WireGuard* app → *Import tunnel(s) from file* → pick `.conf` → *Activate*.

---

## 🔑 SSH VPN — Manage Accounts

Default second service after WireGuard. Ports: OpenSSH **22**, Dropbear **143**, SSH-over-TLS **444**, SSH-over-WS **80**.

```bash
sudo ./add-ssh-user.sh                    # interactive (asks IP & bandwidth limit)
sudo ./add-ssh-user.sh andi               # random password, 30 days (default limit)
sudo ./add-ssh-user.sh andi 'R4h4s1a!' 90 # own password, 90 days
sudo ./add-ssh-user.sh andi '' 30 3 200   # limit 3 IPs / 200 GB
sudo ./remove-ssh-user.sh andi            # remove (active sessions killed too)
```

Connect from laptop/phone:

```bash
ssh -p 22 andi@SERVER-IP
```

For tunneling apps (HTTP Custom, etc.): use host `SERVER-IP`, WS port `80` with standard WebSocket payload, or TLS port `444` for SSH over TLS.

---

## ⚡ Xray / V2Ray — Manage Users (VMess / VLESS / Trojan + XTLS / REALITY)

One user = 1 UUID active on **all 5 inbounds**:

| # | Protocol | Port | Best for |
|---|---|---|---|
| 1 | **VLESS + TCP + XTLS-Vision + REALITY** | 443 | **Primary** — most efficient & anti-blocking, no own domain/TLS needed (SNI `www.microsoft.com`) |
| 2 | VLESS + TCP + XTLS-Vision | 10004 | Fast on clean networks / behind own TLS terminator |
| 3 | VMess + WebSocket (`/vmess`) | 10001 | Old-client compatibility |
| 4 | VLESS + WebSocket (`/vless`) | 10002 | Behind CDN/reverse-proxy (Cloudflare etc.) |
| 5 | Trojan + WebSocket (`/trojan`) | 10003 | HTTPS-traffic disguise |

```bash
sudo ./add-xray-user.sh phone-andi       # create user + print 5 links + REALITY QR (default limit)
sudo ./add-xray-user.sh phone-andi 3 200 # create user with 3 IPs / 200 GB limit
sudo ./remove-xray-user.sh phone-andi    # remove from all inbounds
```

Recommended client apps: Android **v2rayNG / NekoBox**, iOS **Streisand / FoXray / Shadowrocket**, Desktop **Nekoray / Hiddify**. Priority: **VLESS REALITY > VLESS XTLS > VMess/VLESS/Trojan WS**. Copy the link starting `vless://...security=reality...` for best results.

Switch default engine (`xray` → `v2ray`) at install: `sudo ./install.sh --with-v2ray --yes` or `XRAY_ENGINE=v2ray sudo ./install.sh --yes`.

---

## ⏱️ IP & Bandwidth Limits — 5-Min Auto-Suspend (v1.2, wrwb Store)

Every new account asks for **Concurrent IP Limit** and **Bandwidth Limit
(GB/month)**. Empty answer = default **2 IPs** & **100 GB**.

```bash
sudo ./check-limits.sh          # table of all users: limits, used quota, active IPs, status
sudo ./check-limits.sh phone-andi  # check one user only
```

Rules:

- `vpn-limits` systemd monitor runs every **60 seconds**, counting **active unique
  IPs** per user (SSH via `who`/`ss`, WireGuard via active endpoints, Xray via
  access log) in a 10-minute window.
- If active IPs **exceed limit** → user is **suspended 5 minutes** (300 seconds),
  all sessions in the DB are **cleared**, and user SSH processes are killed.
- After 5 minutes, suspension expires **automatically** + sessions are cleared again,
  so the next login counts from zero (correct).
- WireGuard bandwidth usage is auto-collected from `wg show` and
  reset each month start. `OVER-QUOTA` status shows in `check-limits.sh`.
- Removing an account (`remove-*.sh`) auto-removes its limit data.

---

## 📋 Other Operational Commands

```bash
# Server diagnostics (services, forwarding, TUN, NAT, firewall, language, limits)
sudo ./status.sh

# Restart WireGuard manually
sudo systemctl restart wg-quick@wg0
sudo wg show   # handshake & transfer per peer

# Switch language
sudo ./menu.sh   # → 17) Switch language

# Fully remove VPN from server (with emergency backup in /root/)
sudo ./uninstall.sh
```

---

## 🛡️ Security & Network Details

- **WireGuard:** unique Curve25519 keypair per client + PSK (quantum-resistance), sensitive files `600`/dirs `700`, `SaveConfig = false`, `MTU = 1420`, `PersistentKeepalive = 25`.
- **SSH:** `PermitRootLogin no`, `MaxAuthTries 3`, `PasswordAuthentication yes` (for VPN accounts), `nologin` user + expiry date, user sessions killed on account delete.
- **Xray/REALITY:** x25519 keys + random shortId per server, `dest`/`SNI` big TLSv1.3+H2 domain, `chrome` fingerprint, `xtls-rprx-vision` flow (avoids TLS-in-TLS).
- **OpenVPN:** `data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305`, `auth SHA512`, `tls-version-min 1.3`, `tls-crypt`, Easy-RSA 3 PKI + CRL revocation.
- **NAT/Masquerade** on `PostUp` when `wg0` comes up:
  ```bash
  iptables -I FORWARD -i %i -j ACCEPT
  iptables -I FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  iptables -t nat -I POSTROUTING -o <main-iface> -j MASQUERADE
  ```
  (plus `ip6tables` equivalents), auto-cleaned on `PostDown`.
- **UFW:** when active, all ports opened + `DEFAULT_FORWARD_POLICY` changed to `ACCEPT`.
- **firewalld:** when active, all ports opened + permanent `masquerade`.

---

## ❓ Troubleshooting (FAQ)

| Symptom | Common Cause & Fix |
|---|---|
| `must be run as root` | Run with `sudo`, e.g. `sudo ./install.sh`. |
| `/dev/net/tun not available` | OpenVZ/LXC VPS without TUN. Enable TUN in provider panel, or move to KVM VPS. |
| `wg-quick@wg0 failed to start` | See log: `journalctl -u wg-quick@wg0 -n 50 --no-pager`. Usually port conflict — change port at install. |
| Client connects but no internet | Ensure forwarding is on (`cat /proc/sys/net/ipv4/ip_forward` must be `1`), check NAT (`iptables -t nat -L -n`), and open UDP port in cloud firewall. |
| `Port already in use` | Installer warns automatically — check with `ss -lnup \| grep 51820`, pick another port via `./install.sh --port 51821`. |
| `xray` service fails to start | Validate config: `/usr/local/bin/xray run -test -config /etc/xray/config.json`; see log `journalctl -u xray -n 50 --no-pager` (usually port 443 taken by a web server). |
| REALITY won't connect | Ensure server clock is accurate (NTP), `serverNames` SNI matches client `serverName`, and `pbk`/`sid` copied exactly from server link. |
| QR missing in terminal | Terminal lacks ANSI-UTF8 — use PNG file in `/etc/wireguard/clients/<name>/` or copy Xray link manually. |
| New OS (e.g. Ubuntu 26 / Debian 13) warns "untested" | Continue with `y`, or set `FORCE_OS=1`. Report results via Issues so the official list can be updated. |
| Wrong language | Re-run `sudo ./menu.sh` → 17, or `VPN_LANG=zh sudo ./status.sh`, or `echo zh \| sudo tee /etc/vpn/lang`. |

---

## 🔧 Quick Customization

- **Change default port:** edit `DEFAULT_PORT` in `install.sh`, or install with `--port <number>`.
- **Change VPN subnet:** edit `DEFAULT_SUBNET`/`DEFAULT_SERVER_IP` in `install.sh` and `base_v4`/`base_v6` in `lib/wireguard.sh` (keep consistent in `wg_write_server_conf` and `wg_get_next_ip`).
- **Change default DNS:** edit `DEFAULT_DNS` in `install.sh`.
- **Change default language:** no code edit needed — use `--lang en|id|zh`, `VPN_LANG=zh`, or menu 17. File: `/etc/vpn/lang`.
- **Change Xray/V2Ray version:** edit `XRAY_VERSION_DEFAULT` (`v26.3.27`) / `V2RAY_VERSION_DEFAULT` (`v5.53.0`) in `lib/xray.sh` — check latest at [Xray-core releases](https://github.com/XTLS/Xray-core/releases) and [v2ray-core releases](https://github.com/v2fly/v2ray-core/releases).
- **Change Xray inbound ports:** edit `XPORT_VMESS_WS` / `XPORT_VLESS_WS` / `XPORT_TROJAN_WS` / `XPORT_VLESS_XTLS` / `XPORT_VLESS_REALITY` in `lib/xray.sh` before install.
- **Change REALITY SNI:** edit `XREALITY_SNI_DEFAULT` / `XREALITY_DEST_DEFAULT` in `lib/xray.sh` (needs: foreign domain, TLSv1.3 + H2, no redirect).
- **Change Shadowsocks version:** edit `SS_VERSION_DEFAULT` in `lib/shadowsocks.sh` (default: `v1.25.0`, see [shadowsocks-rust releases](https://github.com/shadowsocks/shadowsocks-rust/releases)).
- **Change Shadowsocks cipher:** edit `SS_METHOD_DEFAULT` in `lib/shadowsocks.sh` (default AEAD-2022 `2022-blake3-aes-256-gcm`; low CPU: `2022-blake3-aes-128-gcm`).
- **Disable IPv6 for clients:** remove `, ::/0` from `AllowedIPs` when generating profiles (or edit client `.conf` manually).
- **Change default limits:** edit `DEFAULT_MAX_IP` (2) / `DEFAULT_MAX_GB` (100) in `lib/limits.sh`; suspend duration via `SUSPEND_SECONDS_DEFAULT` (300 = 5 minutes).

---

## 🤝 Contributing

Pull requests & Issues are welcome — especially compatibility reports for new distros (Ubuntu 26, Debian 13) and firewall/NAT rule fixes. Run a syntax check before commit when `bash` is available:

```bash
for f in *.sh lib/*.sh; do bash -n "$f" && echo "OK: $f"; done
```

---

## 📄 License

Free for personal and commercial use. Provided "as is" without warranty. Ensure compliance with your network provider's laws/ToS when running a VPN service.

---
Made by **wrwb Store** — v1.4 (Trilingual EN/ID/ZH, default English + 2-IP & 100-GB limits, 5-min auto-suspend).
