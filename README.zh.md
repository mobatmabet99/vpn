# VPN 自动安装程序 — Linux 多协议 (WireGuard + SSH + Xray + OpenVPN + Shadowsocks)

> 由 **wrwb Store** 打造 — 默认限制 2 IP & 100 GB，多登录自动暂停 5 分钟。

基于 **WireGuard** 为主引擎、默认安装 **SSH VPN** 与 **Xray-core**、可选 **OpenVPN**、**v2ray-core**、**Shadowsocks** 的**开箱即用 VPN 自动化安装脚本**。模块化、安全、兼容众多 Linux 发行版 — 从旧版本到最新版本。

> 适用于 Linux 服务器 (VPS / 物理机)。请勿在 Windows 上运行 — 请将本仓库克隆到您的 Linux 服务器。
>
> 📖 English version (default): [README.en.md](README.en.md)
> 📖 Versi Indonesia: [README.md](README.md)
>
> **v1.4 新特性：** 三语安装程序 **English (默认) / Indonesia / 中文**。安装时会询问语言 — 直接按回车即为英文。详情：[CHANGELOG-v1.4.md](CHANGELOG-v1.4.md)。
>
> **v1.3 特性：** 双语安装程序 **English (默认) / Indonesia**。详情：[CHANGELOG-v1.3.md](CHANGELOG-v1.3.md)。
>
> **v1.2 特性：** 每个新账号都会询问 **IP 限制** 与 **带宽限制**
> （跳过即默认 **2 IP** & **100 GB/月**）。多登录超限 =
> **自动暂停 5 分钟 + 自动清理会话**。详情：[CHANGELOG-v1.2.md](CHANGELOG-v1.2.md)。

---

## 🌐 语言 / Language / Bahasa

- 默认语言：**English**。在语言提示处直接按 **回车** 即可。
- 选择 **2) Indonesia** 为印尼语安装程序。
- 选择 **3) 中文** 为简体中文安装程序。
- 非交互 / 自动化：
  ```bash
  sudo ./install.sh --yes                 # 英文 (默认)
  sudo ./install.sh --lang id --yes       # 印尼语
  sudo ./install.sh --lang zh --yes       # 简体中文
  VPN_LANG=zh sudo ./install.sh --yes     # 通过环境变量
  ```
- 选择保存在 `/etc/vpn/lang` (`en` / `id` / `zh`)，供所有脚本使用 (`add-client.sh`、`menu.sh`、`status.sh` 等)。
- 随时切换：`sudo ./menu.sh` → 菜单 **17) 切换语言**，或 `sudo ./menu.sh --lang en|id|zh`。

---

## ✨ 主要功能

| 功能 | 说明 |
|---|---|
| 🔌 **主协议** | WireGuard (ChaCha20-Poly1305, MTU 1420)，自动生成服务端 + 客户端密钥对、预共享密钥 (PSK)、客户端 `.conf` 文件与二维码 (PNG + 终端 ANSI) |
| 🔑 **SSH VPN (默认开启)** | OpenSSH 加固 + Dropbear (端口 143) + SSH over TLS/Stunnel (端口 444) + SSH over WebSocket (端口 80)。账号管理：`add-ssh-user.sh` / `remove-ssh-user.sh` (带有效期) |
| ⚡ **Xray-core (默认开启)** | v26.3.27 稳定版 — 5 个入站同时运行：VMess WS (10001)、VLESS WS (10002)、Trojan WS (10003)、VLESS TCP XTLS-Vision (10004)、**VLESS TCP XTLS-Vision + REALITY (443)**。1 个 UUID 通用于所有协议 + 自动生成链接与二维码 |
| 🔄 **备用引擎** | v2ray-core v5.53.0 (通过 `--with-v2ray` 或 `XRAY_ENGINE=v2ray` 切换)；OpenVPN 2.7/2.6 (加密 `AES-256-GCM` + `CHACHA20-POLY1305`，认证 `SHA512`，TLS 最低 1.3，`.ovpn` 配置) 可替代 SSH |
| 👻 **Shadowsocks (可选)** | shadowsocks-rust v1.25.0，AEAD-2022 加密 `2022-blake3-aes-256-gcm` + `ss://` URI + 二维码 |
| 🖥️ **系统支持** | Ubuntu 20.04 / 22.04 / 24.04 / 26.04 LTS，Debian 10 / 11 / 12 / 13，CentOS / Rocky / AlmaLinux 8 / 9，RHEL 8/9，Fedora |
| 🛡️ **自动防火墙** | 在 **UFW** (Debian/Ubuntu) 或 **firewalld** (RHEL/Rocky) 中开放所有 VPN 端口 (UDP + TCP) |
| 🌐 **IP 转发** | 持久化启用 `net.ipv4.ip_forward=1` + IPv6 转发 (`/etc/sysctl.d/99-vpn-forward.conf`) |
| 🚀 **吞吐优化** | 服务端与客户端 `MTU = 1420`，TCP BBR + 25 MB 缓冲区 sysctl 优化 |
| 🔀 **NAT / 伪装** | 通过 WireGuard `PostUp`/`PostDown` 自动添加 `iptables ... -j MASQUERADE`，保证客户端正常上网 |
| 📦 **模块化** | `install.sh`、`add-client.sh`、`remove-client.sh`、`list-clients.sh`、`show-qr.sh`、`add-ssh-user.sh`、`remove-ssh-user.sh`、`add-xray-user.sh`、`remove-xray-user.sh`、`check-limits.sh`、`status.sh`、`menu.sh` (0-17)、`uninstall.sh`，以及 `lib/` 下的库 (含 `lib/lang.sh`、`lib/limits.sh`) |
| 🌐 **三语 (v1.4)** | 默认英文，另有印尼语、中文可选。单代码库通过 `lib/lang.sh` 的 `T "English" "Indonesia" "中文"` 实现，选择保存在 `/etc/vpn/lang` |
| ⚠️ **错误处理** | 必须 root/sudo，检查 `/dev/net/tun`，系统检测 + 未测试发行版警告，端口与依赖检查，客户端/用户名校验，旧配置备份 |
| ⏱️ **限制与暂停 (v1.2)** | 每个账号并发 IP + 每月带宽 GB 限制 (默认 2 IP & 100 GB)。多登录超限 = 自动暂停 5 分钟 + 自动清理会话。`vpn-limits` systemd 监控每 60 秒检查一次 |

---

## 📁 仓库结构

```
vpn/
├── install.sh              # 安装：WireGuard + SSH + Xray (默认开启)，会询问语言
├── add-client.sh           # 添加 WireGuard 新客户端 (询问 IP 与带宽限制)
├── remove-client.sh        # 删除 WireGuard 客户端 (+ 清理限制数据)
├── list-clients.sh         # 列出 WG 客户端 + 流量统计与握手状态
├── show-qr.sh              # 重新显示客户端 WG 二维码 / .conf
├── add-ssh-user.sh         # 创建 SSH VPN 账号 (有效期 + IP 与带宽限制)
├── remove-ssh-user.sh      # 删除 SSH VPN 账号 (+ 清理限制数据)
├── add-xray-user.sh        # 创建 Xray/V2Ray 用户 + IP 与带宽限制
├── remove-xray-user.sh     # 删除 Xray/V2Ray 用户 (+ 清理限制数据)
├── check-limits.sh         # 查看 IP 限制、配额、在线 IP 与暂停状态
├── status.sh               # 诊断：服务、转发、TUN、NAT、防火墙、限制、语言
├── menu.sh                 # 交互菜单 0-17 (wrwb Store 控制面板，含语言切换)
├── uninstall.sh            # 彻底卸载 VPN (+ 限制监控 + /etc/vpn/lang)
├── README.md               # 印尼语文档
├── README.en.md            # 英语文档 (默认)
├── README.zh.md            # 中文文档 (本文件)
├── CHANGELOG-v1.2.md       # v1.2 更新日志 (IP 与带宽限制)
├── CHANGELOG-v1.3.md       # v1.3 更新日志 (英/印尼双语)
├── CHANGELOG-v1.4.md       # v1.4 更新日志 (英/印尼/中文三语)
├── lib/
│   ├── lang.sh             # v1.4 三语核心：T "EN" "ID" "ZH"，/etc/vpn/lang
│   ├── common.sh           # 日志、系统检测、校验、网络工具、参数
│   ├── system.sh           # 软件包安装、IP 转发、防火墙 (UFW/firewalld)
│   ├── wireguard.sh        # WireGuard 核心：服务端配置、IP 分配、客户端增删
│   ├── ssh.sh              # SSH 模块：OpenSSH+Dropbear+Stunnel+WebSocket，账号增删
│   ├── xray.sh             # Xray/V2Ray 模块：VMess/VLESS/Trojan+XTLS/REALITY
│   ├── limits.sh           # v1.2 模块：IP 与带宽限制 + 5 分钟自动暂停
│   ├── openvpn.sh          # 备用 OpenVPN + Easy-RSA 模块
│   └── shadowsocks.sh      # 可选 Shadowsocks-rust 模块
├── .gitattributes          # 强制 LF 换行，保证脚本在 Linux 上安全
```

服务器上生成的配置文件：

```
/etc/wireguard/wg0.conf            # WireGuard 服务端配置
/etc/wireguard/params              # 服务端参数 (供其他 WG 脚本读取)
/etc/wireguard/clients/<name>/
    ├── <name>.conf                # 客户端配置 (导入 WireGuard App)
    ├── <name>.png                 # 二维码 (手机/平板扫码)
    └── private.key / public.key / preshared.key
/etc/vpn/lang                      # v1.4 语言选择 ("en" / "id" / "zh")
/etc/ssh-vpn/params                # SSH/Dropbear/TLS/WS 端口 + 公网 IP
/etc/ssh-vpn/accounts.db           # SSH 账号数据库 (user:created:expiry)
/etc/xray/config.json              # Xray/V2Ray 配置 (5 个入站)
```

```
/etc/xray/params                   # 服务端 UUID、REALITY 密钥、入站端口
/etc/xray/accounts.db              # Xray 用户数据库 (name:uuid:created)
```

---

## ⚙️ 前提条件

1. **Linux 服务器** (推荐 VPS)，系统在支持列表中。
2. **Root 权限** — 所有脚本必须以 root / `sudo` 运行。
3. **TUN 设备** 可用 (`/dev/net/tun`)。绝大多数 KVM VPS 已启用。OpenVZ/LXC 请先在服务商面板启用 TUN。
4. 服务器需**联网**以下载软件包 (apt/dnf) 与 GitHub 二进制 (Xray/Shadowsocks)。
5. 云防火墙放行空闲端口：UDP 51820 (WireGuard)，TCP 22/80/143/444 (SSH)，TCP 443/10001-10004 (Xray)。
6. 服务器需 **Python 3** (一般预装；Xray 模块用于安全编辑 JSON)。

---

## 🚀 安装步骤

### 1. 克隆仓库到 Linux 服务器

```bash
git clone https://github.com/mobatmabet99/vpn.git
cd vpn
chmod +x *.sh
```

### 2. 以 root 运行安装程序

交互模式 — 选择安装语言 (默认英文)、登录服务 (SSH/OpenVPN，**默认 SSH**)、隧道引擎 (Xray/V2Ray，**默认 Xray**)：

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

非交互模式 — 全默认 (**WireGuard + SSH + Xray**，英文，适合自动化)：

```bash
sudo ./install.sh --yes
```

其他非交互示例：

```bash
# WireGuard + OpenVPN + V2Ray (不装 SSH 与 Xray)
sudo ./install.sh --with-openvpn --with-v2ray --yes

# 默认 + Shadowsocks
sudo ./install.sh --with-shadowsocks --yes

# 最简：仅 WireGuard
sudo ./install.sh --no-ssh --no-xray --yes

# 中文安装，非交互
sudo ./install.sh --lang zh --yes

# 通过环境变量选择引擎
XRAY_ENGINE=v2ray sudo ./install.sh --yes
```

查看全部选项：

```bash
./install.sh --help
```

| 参数 | 作用 |
|---|---|
| `--with-ssh` / `--no-ssh` | 安装 / 跳过 SSH VPN (默认：安装) |
| `--with-openvpn` | 安装 OpenVPN **替代** SSH (互斥，可手动组合) |
| `--with-xray` / `--with-v2ray` / `--no-xray` | 选择隧道引擎 (默认 Xray)。`--with-v2ray` = v2ray-core 引擎 |
| `--with-shadowsocks` | 同时安装 Shadowsocks (默认：不装) |
| `--lang en\|id\|zh` | 安装语言 (默认 en)。也可用 `VPN_LANG=en\|id\|zh` 环境变量 |
| `-p/-c/-d/-y` | WG 端口、首个客户端名、DNS、非交互模式 |

### 3. `install.sh` 执行顺序

1. 校验 root 与 `/dev/net/tun`。
2. 询问安装语言 (默认英文)，保存到 `/etc/vpn/lang`。
3. 检测系统 (Ubuntu/Debian/RHEL/...) — 未测试发行版会警告 + 确认，除非强制。
4. 检测主网卡与服务器公网 IP。
5. 询问/使用参数 (端口、DNS、客户端名、SSH-vs-OpenVPN、Xray-vs-V2Ray)。
6. 校验端口与客户端名，检查 UDP 端口是否被占用。
7. 安装 WireGuard 软件包 + 启用 IP 转发与吞吐优化 (BBR、TCP 缓冲)。
8. 在 UFW / firewalld 开放 WireGuard UDP 端口。
9. 生成服务端密钥对，写入 `wg0.conf` (MTU 1420 + NAT `PostUp`/`PostDown`)，保存 `params`。
10. 创建首个 WireGuard 客户端 + `.conf` + 二维码，然后启用并启动 `wg-quick@wg0`。
11. **安装 SSH VPN** (默认)：OpenSSH 加固 + Dropbear:143 + Stunnel:444 + WebSocket:80。
12. **安装 Xray-core** (默认)：5 个入站 VMess/VLESS/Trojan + XTLS-Vision + REALITY:443 + 连接链接与二维码。
13. (可选) 按需安装 OpenVPN / Shadowsocks。
14. 显示总结 + 快捷命令。

### 4. 备选：交互菜单

```bash
sudo ./menu.sh
sudo ./menu.sh --lang zh   # 本次强制中文
```

菜单 0–17：安装 WG、添加/删除 WG 客户端、显示二维码、列出客户端、检查状态、安装 SSH / OpenVPN / Xray / V2Ray / Shadowsocks、管理 SSH 账号、管理 Xray 用户、重启服务、检查限制、切换语言 (17)、卸载。

---

## 👤 WireGuard — 添加 / 删除客户端

```bash
sudo ./add-client.sh                 # 交互 (询问 IP 与带宽限制)
sudo ./add-client.sh phone-andi      # 直接 (默认 2 IP / 100 GB)
sudo ./add-client.sh phone-andi 3 200 # 直接 (限制 3 IP / 200 GB)
sudo ./remove-client.sh phone-andi   # 删除 (实时删除 peer + IP 复用)
sudo ./list-clients.sh               # 列表 + 最近握手 + 上/下行流量
sudo ./show-qr.sh phone-andi         # 重新显示二维码 + .conf
```

命名规则：仅字母、数字、`-`、`_`，最长 32 字符。

- **Android / iOS：** *WireGuard* App → 添加隧道 → *从二维码扫描*。
- **Windows / macOS / Linux 桌面：** *WireGuard* App → *从文件导入隧道* → 选择 `.conf` → *激活*。

---

## 🔑 SSH VPN — 账号管理

WireGuard 之后的默认第二服务。端口：OpenSSH **22**、Dropbear **143**、SSH-over-TLS **444**、SSH-over-WS **80**。

```bash
sudo ./add-ssh-user.sh                    # 交互 (询问 IP 与带宽限制)
sudo ./add-ssh-user.sh andi               # 随机密码，30 天 (默认限制)
sudo ./add-ssh-user.sh andi 'R4h4s1a!' 90 # 自定义密码，90 天
sudo ./add-ssh-user.sh andi '' 30 3 200   # 限制 3 IP / 200 GB
sudo ./remove-ssh-user.sh andi            # 删除 (同时踢掉在线会话)
```

电脑/手机连接示例：

```bash
ssh -p 22 andi@SERVER-IP
```

隧道 App (HTTP Custom 等)：主机填 `SERVER-IP`，WS 端口 `80` 使用标准 WebSocket 负载，或 TLS 端口 `444` 走 SSH over TLS。

---

## ⚡ Xray / V2Ray — 用户管理 (VMess / VLESS / Trojan + XTLS / REALITY)

一个用户 = 1 个 UUID，在**全部 5 个入站**生效：

| # | 协议 | 端口 | 适用场景 |
|---|---|---|---|
| 1 | **VLESS + TCP + XTLS-Vision + REALITY** | 443 | **首选** — 最高效、防封锁，无需自备域名/TLS (SNI `www.microsoft.com`) |
| 2 | VLESS + TCP + XTLS-Vision | 10004 | 干净网络最快 / 自备 TLS 前置时 |
| 3 | VMess + WebSocket (`/vmess`) | 10001 | 老客户端兼容 |
| 4 | VLESS + WebSocket (`/vless`) | 10002 | CDN/反代之后 (Cloudflare 等) |
| 5 | Trojan + WebSocket (`/trojan`) | 10003 | 伪装 HTTPS 流量 |

```bash
sudo ./add-xray-user.sh phone-andi       # 创建用户 + 打印 5 条链接 + REALITY 二维码 (默认限制)
sudo ./add-xray-user.sh phone-andi 3 200 # 创建用户，限制 3 IP / 200 GB
sudo ./remove-xray-user.sh phone-andi    # 从所有入站删除
```

推荐客户端：安卓 **v2rayNG / NekoBox**，iOS **Streisand / FoXray / Shadowrocket**，桌面 **Nekoray / Hiddify**。优先级：**VLESS REALITY > VLESS XTLS > VMess/VLESS/Trojan WS**。复制以 `vless://...security=reality...` 开头的链接效果最好。

安装时切换默认引擎 (`xray` → `v2ray`)：`sudo ./install.sh --with-v2ray --yes` 或 `XRAY_ENGINE=v2ray sudo ./install.sh --yes`。

---

## ⏱️ IP 与带宽限制 — 5 分钟自动暂停 (v1.2, wrwb Store)

每个新账号都会询问**并发 IP 限制**与**带宽限制 (GB/月)**。留空 = 默认 **2 IP** & **100 GB**。

```bash
sudo ./check-limits.sh          # 所有用户表格：限制、已用配额、在线 IP、状态
sudo ./check-limits.sh phone-andi  # 只查一个用户
```

规则：

- `vpn-limits` systemd 监控每 **60 秒**运行一次，统计每用户**在线唯一 IP**
  (SSH 经 `who`/`ss`，WireGuard 经在线 endpoint，Xray 经 access log)，窗口 10 分钟。
- 在线 IP **超限** → 用户**暂停 5 分钟** (300 秒)，
  数据库中所有会话**被清理**，用户 SSH 进程被杀掉。
- 5 分钟后暂停**自动到期** + 再次清理会话，
  下次登录从零计数 (准确)。
- WireGuard 带宽用量从 `wg show` 自动采集，
  每月初重置。`check-limits.sh` 显示 `OVER-QUOTA` 状态。
- 删除账号 (`remove-*.sh`) 自动删除其限制数据。

---

## 📋 其他运维命令

```bash
# 服务器诊断 (服务、转发、TUN、NAT、防火墙、语言、限制)
sudo ./status.sh

# 手动重启 WireGuard
sudo systemctl restart wg-quick@wg0
sudo wg show   # 每 peer 握手与传输

# 切换语言
sudo ./menu.sh   # → 17) 切换语言

# 从服务器彻底删除 VPN (在 /root/ 留应急备份)
sudo ./uninstall.sh
```

---

## 🛡️ 安全与网络细节

- **WireGuard：** 每客户端唯一 Curve25519 密钥对 + PSK (抗量子)，敏感文件 `600`/目录 `700`，`SaveConfig = false`，`MTU = 1420`，`PersistentKeepalive = 25`。
- **SSH：** `PermitRootLogin no`，`MaxAuthTries 3`，`PasswordAuthentication yes` (供 VPN 账号)，`nologin` 用户 + 到期日，删除账号时踢掉会话。
- **Xray/REALITY：** 每服务器 x25519 密钥 + 随机 shortId，`dest`/`SNI` 大厂 TLSv1.3+H2 域名，`chrome` 指纹，`xtls-rprx-vision` 流 (避免 TLS-in-TLS)。
- **OpenVPN：** `data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305`，`auth SHA512`，`tls-version-min 1.3`，`tls-crypt`，Easy-RSA 3 PKI + CRL 吊销。
- `wg0` 启动时 `PostUp` 自动添加 **NAT/伪装**：
  ```bash
  iptables -I FORWARD -i %i -j ACCEPT
  iptables -I FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  iptables -t nat -I POSTROUTING -o <主网卡> -j MASQUERADE
  ```
  (另有 `ip6tables` 对应规则)，`PostDown` 自动清理。
- **UFW：** 启用时开放所有端口 + `DEFAULT_FORWARD_POLICY` 改为 `ACCEPT`。
- **firewalld：** 启用时开放所有端口 + 永久 `masquerade`。

---

## ❓ 故障排查 (FAQ)

| 现象 | 常见原因与解决 |
|---|---|
| `must be run as root` | 用 `sudo` 运行，如 `sudo ./install.sh`。 |
| `/dev/net/tun not available` | OpenVZ/LXC VPS 无 TUN。请在服务商面板启用 TUN，或换 KVM VPS。 |
| `wg-quick@wg0 failed to start` | 看日志：`journalctl -u wg-quick@wg0 -n 50 --no-pager`。多为端口冲突 — 安装时换端口。 |
| 客户端能连但上不了网 | 确认转发已开 (`cat /proc/sys/net/ipv4/ip_forward` 应为 `1`)，检查 NAT (`iptables -t nat -L -n`)，云防火墙放行 UDP 端口。 |
| `Port already in use` | 安装程序会自动警告 — 用 `ss -lnup \| grep 51820` 检查，通过 `./install.sh --port 51821` 换端口。 |
| `xray` 服务启动失败 | 校验配置：`/usr/local/bin/xray run -test -config /etc/xray/config.json`；看日志 `journalctl -u xray -n 50 --no-pager` (多为 443 被 Web 服务占用)。 |
| REALITY 连不上 | 确认服务器时间准确 (NTP)，`serverNames` SNI 与客户端 `serverName` 一致，`pbk`/`sid` 从服务端链接完整复制。 |
| 终端不显示二维码 | 终端不支持 ANSI-UTF8 — 用 `/etc/wireguard/clients/<name>/` 下 PNG 文件，或手动复制 Xray 链接。 |
| 新系统 (如 Ubuntu 26 / Debian 13) 提示 "untested" | 输入 `y` 继续，或设置 `FORCE_OS=1`。欢迎通过 Issues 反馈，便于更新官方支持列表。 |
| 语言不对 | 重新 `sudo ./menu.sh` → 17，或 `VPN_LANG=zh sudo ./status.sh`，或 `echo zh \| sudo tee /etc/vpn/lang`。 |

---

## 🔧 快捷自定义

- **改默认端口：** 改 `install.sh` 的 `DEFAULT_PORT`，或安装时 `--port <数字>`。
- **改 VPN 子网：** 改 `install.sh` 的 `DEFAULT_SUBNET`/`DEFAULT_SERVER_IP` 与 `lib/wireguard.sh` 的 `base_v4`/`base_v6` (`wg_write_server_conf` 与 `wg_get_next_ip` 保持一致)。
- **改默认 DNS：** 改 `install.sh` 的 `DEFAULT_DNS`。
- **改默认语言：** 无需改代码 — 用 `--lang en|id|zh`、`VPN_LANG=zh` 或菜单 17。文件：`/etc/vpn/lang`。
- **改 Xray/V2Ray 版本：** 改 `lib/xray.sh` 的 `XRAY_VERSION_DEFAULT` (`v26.3.27`) / `V2RAY_VERSION_DEFAULT` (`v5.53.0`) — 最新版见 [Xray-core releases](https://github.com/XTLS/Xray-core/releases) 与 [v2ray-core releases](https://github.com/v2fly/v2ray-core/releases)。
- **改 Xray 入站端口：** 安装前改 `lib/xray.sh` 的 `XPORT_VMESS_WS` / `XPORT_VLESS_WS` / `XPORT_TROJAN_WS` / `XPORT_VLESS_XTLS` / `XPORT_VLESS_REALITY`。
- **改 REALITY SNI：** 改 `lib/xray.sh` 的 `XREALITY_SNI_DEFAULT` / `XREALITY_DEST_DEFAULT` (要求：国外大域名、TLSv1.3 + H2、无跳转)。
- **改 Shadowsocks 版本：** 改 `lib/shadowsocks.sh` 的 `SS_VERSION_DEFAULT` (默认 `v1.25.0`，见 [shadowsocks-rust releases](https://github.com/shadowsocks/shadowsocks-rust/releases))。
- **改 Shadowsocks 加密：** 改 `lib/shadowsocks.sh` 的 `SS_METHOD_DEFAULT` (默认 AEAD-2022 `2022-blake3-aes-256-gcm`；省 CPU：`2022-blake3-aes-128-gcm`)。
- **客户端禁用 IPv6：** 生成配置时从 `AllowedIPs` 删除 `, ::/0` (或手动改客户端 `.conf`)。
- **改默认限制：** 改 `lib/limits.sh` 的 `DEFAULT_MAX_IP` (2) / `DEFAULT_MAX_GB` (100)；暂停时长 `SUSPEND_SECONDS_DEFAULT` (300 = 5 分钟)。

---

## 🤝 贡献

欢迎 Pull Request 与 Issues — 尤其新发行版兼容报告 (Ubuntu 26、Debian 13) 与防火墙/NAT 规则修复。有 `bash` 时提交前请先做语法检查：

```bash
for f in *.sh lib/*.sh; do bash -n "$f" && echo "OK: $f"; done
```

---

## 📄 许可

个人与商业用途均免费。按“现状”提供，不含保证。运行 VPN 服务时请遵守网络服务商法律/ToS。

---
由 **wrwb Store** 打造 — v1.4 (英/印尼/中文三语，默认英文 + 2-IP & 100-GB 限制，5 分钟自动暂停)。
