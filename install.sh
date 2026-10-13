#!/bin/bash
# ==============================================================================
#  install.sh — Automated VPN installer (WireGuard engine, trilingual EN/ID/ZH)
#  Supports:
#    - Ubuntu 20.04 / 22.04 / 24.04 / 26.04 LTS (and later)
#    - Debian 10 (Buster) / 11 (Bullseye) / 12 (Bookworm) / 13 (Trixie)
#    - CentOS / Rocky Linux / AlmaLinux 8 / 9
#    - RHEL 8 / 9 & Fedora
#  Branding: wrwb Store
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pre-scan --lang <en|id|zh> so the language framework knows the choice
# before any module prints output (default: en).
_prev_arg=""
for _a in "$@"; do
  case "$_a" in
    --lang=*) VPN_LANG_CLI="${_a#--lang=}" ;;
    *) if [[ "$_prev_arg" == "--lang" ]]; then VPN_LANG_CLI="$_a"; fi ;;
  esac
  _prev_arg="$_a"
done
unset _a _prev_arg
export VPN_LANG_CLI="${VPN_LANG_CLI:-}"

# Load support modules
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/system.sh
source "$SCRIPT_DIR/lib/system.sh"
# shellcheck source=lib/wireguard.sh
source "$SCRIPT_DIR/lib/wireguard.sh"
# shellcheck source=lib/openvpn.sh
source "$SCRIPT_DIR/lib/openvpn.sh"
# shellcheck source=lib/shadowsocks.sh
source "$SCRIPT_DIR/lib/shadowsocks.sh"
# shellcheck source=lib/ssh.sh
source "$SCRIPT_DIR/lib/ssh.sh"
# shellcheck source=lib/xray.sh
source "$SCRIPT_DIR/lib/xray.sh"
# shellcheck source=lib/limits.sh
source "$SCRIPT_DIR/lib/limits.sh"

# Default configuration
DEFAULT_PORT="51820"
DEFAULT_DNS="1.1.1.1, 1.0.0.1"
DEFAULT_CLIENT="client1"
DEFAULT_SUBNET="10.66.66.0/24"
DEFAULT_SERVER_IP="10.66.66.1"

# Banner (trilingual, printed after language selection)
print_banner() {
  cat <<'EOF'
 ================================================================
    __     ______  _   _    ___           _        _ _
    \ \   / /  _ \| \ | |  |_ _|_ __  ___| |_ __ _| | | ___ _ __
     \ \ / /| |_) |  \| |   | || '_ \/ __| __/ _` | | |/ _ \ '__|
      \ V / |  __/| |\  |   | || | | \__ \ || (_| | | |  __/ |
       \_/  |_|   |_| \_|  |___|_| |_|___/\__\__,_|_|_|\___|_|

EOF
  echo "    $(T "Multi-Distro VPN Auto-Installer (WireGuard Engine)" "Otomatisasi Instalasi VPN Multi-Distro (WireGuard Engine)" "多发行版 VPN 自动安装程序 (WireGuard 引擎)")"
  echo "    $(T "by wrwb Store - Default limit 2 IPs & 100GB" "Dibuat oleh wrwb Store - Limit 2 IP & 100GB Default" "由 wrwb Store 打造 - 默认限制 2 IP 和 100GB")"
  echo "    $(lang_label)"
  echo " ================================================================"
}

# Command-line argument parsing
CLI_PORT=""
CLI_CLIENT=""
CLI_DNS=""
CLI_YES=0
WITH_OPENVPN=0
WITH_SHADOWSOCKS=0
# SSH & Xray enabled by default — can be disabled explicitly via --no-ssh / --no-xray
WITH_SSH=1
WITH_XRAY=1
# Tunnel engine: "xray" (default, XTLS+REALITY) or "v2ray"
XRAY_ENGINE="${XRAY_ENGINE:-xray}"

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--port)
        CLI_PORT="$2"; shift 2 ;;
      -c|--client)
        CLI_CLIENT="$2"; shift 2 ;;
      -d|--dns)
        CLI_DNS="$2"; shift 2 ;;
      -y|--yes)
        CLI_YES=1; AUTO_YES=1; shift ;;
      --lang)
        VPN_LANG_CLI="$2"; shift 2 ;;
      --lang=*)
        VPN_LANG_CLI="${1#--lang=}"; shift ;;
      --with-openvpn)
        WITH_OPENVPN=1; WITH_SSH=0; shift ;;
      --with-ssh)
        WITH_SSH=1; WITH_OPENVPN=0; shift ;;
      --no-ssh)
        WITH_SSH=0; shift ;;
      --with-shadowsocks)
        WITH_SHADOWSOCKS=1; shift ;;
      --with-xray)
        WITH_XRAY=1; XRAY_ENGINE="xray"; shift ;;
      --with-v2ray)
        WITH_XRAY=1; XRAY_ENGINE="v2ray"; shift ;;
      --no-xray)
        WITH_XRAY=0; shift ;;
      -h|--help)
        echo "$(T "Usage: sudo ./install.sh [options]" "Penggunaan: sudo ./install.sh [opsi]" "用法：sudo ./install.sh [选项]")"
        echo "$(T "Options:" "Opsi:" "选项：")"
        echo "  -p, --port <port>          $(T "WireGuard port (default: 51820)" "Port WireGuard (default: 51820)" "WireGuard 端口（默认：51820）")"
        echo "  -c, --client <name>        $(T "First client name (default: client1)" "Nama client pertama (default: client1)" "首个客户端名称（默认：client1）")"
        echo "  -d, --dns <ip1,ip2>        $(T "DNS servers (default: 1.1.1.1, 1.0.0.1)" "DNS Server (default: 1.1.1.1, 1.0.0.1)" "DNS 服务器（默认：1.1.1.1, 1.0.0.1）")"
        echo "  -y, --yes                  $(T "Non-interactive mode (use defaults)" "Mode non-interaktif (gunakan nilai default)" "非交互模式（使用默认值）")"
        echo "      --lang <en|id|zh>      $(T "Installer language (default: en)" "Bahasa instalasi (default: en)" "安装语言（默认：en）")"
        echo "      --with-ssh             $(T "Install SSH VPN (DEFAULT ON)" "Pasang SSH VPN (DEFAULT AKTIF)" "安装 SSH VPN（默认开启）")"
        echo "      --with-openvpn         $(T "Install OpenVPN (replaces SSH, mutually exclusive)" "Pasang OpenVPN (pengganti SSH, saling eksklusif)" "安装 OpenVPN（替代 SSH，二者互斥）")"
        echo "      --no-ssh               $(T "Install neither SSH nor OpenVPN" "Jangan pasang SSH maupun OpenVPN" "既不安装 SSH 也不安装 OpenVPN")"
        echo "      --with-xray            $(T "Install Xray-core (DEFAULT ON)" "Pasang Xray-core (DEFAULT AKTIF)" "安装 Xray-core（默认开启）")"
        echo "      --with-v2ray           $(T "Install v2ray-core (replaces Xray)" "Pasang v2ray-core (pengganti Xray)" "安装 v2ray-core（替代 Xray）")"
        echo "      --no-xray              $(T "Install neither Xray nor V2Ray" "Jangan pasang Xray/V2Ray" "既不安装 Xray 也不安装 V2Ray")"
        echo "      --with-shadowsocks     $(T "Also install Shadowsocks" "Sekaligus instal Shadowsocks" "同时安装 Shadowsocks")"
        echo "  -h, --help                 $(T "Show this help" "Tampilkan bantuan ini" "显示此帮助")"
        echo ""
        echo "$(T "Examples:" "Contoh:" "示例：")"
        echo "  sudo ./install.sh --yes                                   # default: WG + SSH + Xray"
        echo "  sudo ./install.sh --lang id --yes                         # installer in Indonesian"
        echo "  sudo ./install.sh --lang zh --yes                         # installer in Chinese (简体中文)"
        echo "  sudo ./install.sh --with-openvpn --with-v2ray --yes       # WG + OpenVPN + V2Ray"
        echo "  XRAY_ENGINE=v2ray sudo ./install.sh --yes                 # select engine via env"
        exit 0
        ;;
      *)
        die "$(T "Unknown option: $1. Use --help for help." "Opsi tidak dikenal: $1. Gunakan --help untuk bantuan." "未知选项: $1。使用 --help 查看帮助.")"
        ;;
    esac
  done
  # Refresh language now that CLI flags are known (--lang may appear anywhere)
  lang_load
}

main() {
  parse_args "$@"

  # 1. Root access validation
  need_root

  # 2. Language selection (interactive only; default English).
  #    --lang en|id|zh, VPN_LANG env, or saved /etc/vpn/lang wins silently.
  lang_ask
  lang_save

  print_banner

  # 3. TUN device check
  check_tun
  check_virt

  # 4. OS validation & detection
  check_os_supported

  # Check whether WireGuard was already installed
  if [[ -f /etc/wireguard/params && -f /etc/wireguard/wg0.conf ]]; then
    log_warn "$(T "WireGuard seems to be already installed on this system." "WireGuard sepertinya sudah terpasang di sistem ini." "WireGuard 似乎已安装在此系统上。")"
    if [[ "$CLI_YES" -eq 0 ]]; then
      echo "$(T "Options:" "Pilihan:" "选项：")"
      echo "  1) $(T "Add a new client (add-client.sh)" "Tambah client baru (add-client.sh)" "添加新客户端 (add-client.sh)")"
      echo "  2) $(T "Clean re-install" "Instal ulang / Re-install bersih" "干净重装")"
      echo "  3) $(T "Exit" "Keluar" "退出")"
      read -rp "$(T "Choose [1-3] (default 1): " "Pilih [1-3] (default 1): " "选择 [1-3]（默认 1）：")" ex_choice
      ex_choice="${ex_choice:-1}"
      case "$ex_choice" in
        1) exec "$SCRIPT_DIR/add-client.sh" ;;
        2) log_warn "$(T "Continuing with a clean WireGuard re-install..." "Melanjutkan instal ulang WireGuard..." "正在干净重装 WireGuard……")" ;;
        *) exit 0 ;;
      esac
    fi
  fi

  # 5. Network parameter detection
  log_step "$(T "Detecting network interface and public IP..." "Mendeteksi antarmuka jaringan dan IP publik..." "正在检测网络接口和公网 IP……")"
  NET_IFACE="$(get_default_iface)"
  SERVER_PUB_IP="$(get_public_ip)"
  log_info "$(T "Public interface : $NET_IFACE" "Antarmuka publik : $NET_IFACE" "公网接口：$NET_IFACE")"
  log_info "$(T "Server public IP : $SERVER_PUB_IP" "IP Publik server : $SERVER_PUB_IP" "服务器公网 IP：$SERVER_PUB_IP")"

  # 6. Ask parameters (or use CLI / defaults)
  if [[ "$CLI_YES" -eq 1 ]]; then
    SERVER_PORT="${CLI_PORT:-$DEFAULT_PORT}"
    SERVER_DNS="${CLI_DNS:-$DEFAULT_DNS}"
    FIRST_CLIENT="${CLI_CLIENT:-$DEFAULT_CLIENT}"
  else
    # Port
    echo ""
    read -rp "$(T "WireGuard port [$DEFAULT_PORT]: " "Port WireGuard [$DEFAULT_PORT]: " "WireGuard 端口 [$DEFAULT_PORT]：")" input_port
    SERVER_PORT="${input_port:-$DEFAULT_PORT}"
    [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] && [[ "$SERVER_PORT" -ge 1 && "$SERVER_PORT" -le 65535 ]] || die "$(T "Port must be a number between 1-65535." "Port harus berupa angka antara 1-65535." "端口必须是 1-65535 之间的数字。")"

    # DNS
    echo ""
    echo "$(T "DNS server choices:" "Pilihan DNS Server:" "DNS 服务器选项：")"
    echo "  1) Cloudflare (1.1.1.1, 1.0.0.1) - $(T "Fast & private (Recommended)" "Cepat & Privasi (Rekomendasi)" "快速且注重隐私（推荐）")"
    echo "  2) Google (8.8.8.8, 8.8.4.4)"
    echo "  3) AdGuard DNS (94.140.14.14 - $(T "Blocks ads" "Blokir Iklan" "拦截广告"))"
    echo "  4) $(T "Custom" "Kustom" "自定义")"
    read -rp "$(T "Choose DNS [1-4] (default 1): " "Pilih DNS [1-4] (default 1): " "选择 DNS [1-4]（默认 1）：")" dns_choice
    case "${dns_choice:-1}" in
      1) SERVER_DNS="1.1.1.1, 1.0.0.1" ;;
      2) SERVER_DNS="8.8.8.8, 8.8.4.4" ;;
      3) SERVER_DNS="94.140.14.14, 94.140.15.15" ;;
      4)
        read -rp "$(T "Enter DNS IPs (comma separated): " "Masukkan IP DNS (pisahkan koma): " "输入 DNS IP（以逗号分隔）：")" custom_dns
        SERVER_DNS="${custom_dns:-1.1.1.1}"
        ;;
      *) SERVER_DNS="1.1.1.1, 1.0.0.1" ;;
    esac

    # First client name
    echo ""
    read -rp "$(T "First client name [$DEFAULT_CLIENT]: " "Nama client pertama [$DEFAULT_CLIENT]: " "首个客户端名称 [$DEFAULT_CLIENT]：")" input_client
    FIRST_CLIENT="${input_client:-$DEFAULT_CLIENT}"
    validate_client_name "$FIRST_CLIENT"

    # Extra protocol options — SSH default YES, OpenVPN as alternative
    echo ""
    echo "$(T "Choose the login tunnel service:" "Pilih layanan login tunnel:" "选择登录隧道服务：")"
    echo "  1) SSH VPN (Dropbear + Stunnel + WebSocket) — $(T "DEFAULT, lightweight & universal" "DEFAULT, ringan & universal" "默认，轻量且通用")"
    echo "  2) OpenVPN ($(T "port" "port" "端口") 1194/UDP + .ovpn $(T "profile" "profil" "配置文件"))"
    echo "  3) $(T "Both" "Keduanya" "两者都安装")"
    echo "  4) $(T "Install neither" "Tidak pasang keduanya" "都不安装")"
    read -rp "$(T "Choose login service [1-4] (default 1): " "Pilih layanan login [1-4] (default 1): " "选择登录服务 [1-4]（默认 1）：")" login_choice
    case "${login_choice:-1}" in
      1) WITH_SSH=1; WITH_OPENVPN=0 ;;
      2) WITH_SSH=0; WITH_OPENVPN=1 ;;
      3) WITH_SSH=1; WITH_OPENVPN=1 ;;
      4) WITH_SSH=0; WITH_OPENVPN=0 ;;
      *) WITH_SSH=1; WITH_OPENVPN=0 ;;
    esac

    # Tunnel engine options — Xray default, V2Ray alternative
    echo ""
    echo "$(T "Choose the tunnel engine (VMess/VLESS/Trojan + XTLS/REALITY):" "Pilih engine tunnel (VMess/VLESS/Trojan + XTLS/REALITY):" "选择隧道引擎 (VMess/VLESS/Trojan + XTLS/REALITY)：")"
    echo "  1) Xray-core v26.3.27 — $(T "DEFAULT, fastest XTLS-Vision + REALITY" "DEFAULT, XTLS-Vision + REALITY tercepat" "默认，最快的 XTLS-Vision + REALITY")"
    echo "  2) v2ray-core v5.53.0 — $(T "stable alternative" "alternatif stabil" "稳定的替代方案")"
    echo "  3) $(T "Install neither" "Tidak pasang keduanya" "都不安装")"
    read -rp "$(T "Choose tunnel engine [1-3] (default 1): " "Pilih engine tunnel [1-3] (default 1): " "选择隧道引擎 [1-3]（默认 1）：")" engine_choice
    case "${engine_choice:-1}" in
      1) WITH_XRAY=1; XRAY_ENGINE="xray" ;;
      2) WITH_XRAY=1; XRAY_ENGINE="v2ray" ;;
      3) WITH_XRAY=0 ;;
      *) WITH_XRAY=1; XRAY_ENGINE="xray" ;;
    esac

    read -rp "$(T "Also install Shadowsocks? [y/N]: " "Ingin sekalian memasang Shadowsocks? [y/N]: " "同时安装 Shadowsocks 吗？[y/N]：")" ask_ss
    [[ "$ask_ss" =~ ^[Yy]$ ]] && WITH_SHADOWSOCKS=1 || true
  fi

  # Global validation (applies to interactive & non-interactive modes)
  [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] && [[ "$SERVER_PORT" -ge 1 && "$SERVER_PORT" -le 65535 ]] || die "$(T "Port '$SERVER_PORT' is invalid. Use a number 1-65535." "Port '$SERVER_PORT' tidak valid. Gunakan angka 1-65535." "端口 '$SERVER_PORT' 无效。请使用 1-65535 之间的数字。")"
  validate_client_name "$FIRST_CLIENT"
  if is_port_in_use "$SERVER_PORT" "udp"; then
    log_warn "$(T "UDP port $SERVER_PORT seems to be already used by another application." "Port UDP $SERVER_PORT sepertinya sudah dipakai oleh aplikasi lain." "UDP 端口 $SERVER_PORT 似乎已被其他应用占用。")"
    if [[ "$CLI_YES" -eq 0 ]]; then
      confirm "$(T "Continue with port $SERVER_PORT anyway? [y/N] " "Tetap lanjutkan dengan port $SERVER_PORT? [y/N] " "仍要继续使用端口 $SERVER_PORT 吗？[y/N] ")" || die "$(T "Installation cancelled. Re-run with another port (e.g. --port 51821)." "Instalasi dibatalkan. Jalankan ulang dengan port lain (mis. --port 51821)." "安装已取消。请使用其他端口重新运行（例如 --port 51821）。")"
    fi
  fi

  SERVER_SUBNET="$DEFAULT_SUBNET"
  SERVER_IP="$DEFAULT_SERVER_IP"
  WG_CONF="/etc/wireguard/wg0.conf"
  CLIENT_DIR="/etc/wireguard/clients"

  # 7. Install dependency packages
  install_wireguard_packages

  # 8. Enable IP forwarding
  enable_ip_forwarding

  # 9. Open firewall port
  open_firewall_port "$SERVER_PORT" "udp"

  # 10. Generate WireGuard server keys
  wg_generate_server_keys

  # 11. Write server wg0.conf
  wg_write_server_conf "$SERVER_PORT" "$NET_IFACE" "10.66.66.1/24" "fd42:42:42::1/64"

  # 12. Save server parameter file (/etc/wireguard/params)
  save_params

  # 13. Create first client
  log_step "$(T "Creating profile for client '$FIRST_CLIENT'..." "Membuat profil untuk client '$FIRST_CLIENT'..." "正在为客户端 '$FIRST_CLIENT' 创建配置文件……")"
  wg_create_client "$FIRST_CLIENT"

  # 14. Enable and start WireGuard service
  wg_enable_and_start

  # 15. Install extra protocols as chosen (default: SSH + Xray)
  if [[ "$WITH_SSH" -eq 1 ]]; then
    log_step "$(T "Installing SSH VPN server (default)..." "Memasang SSH VPN Server (default)..." "正在安装 SSH VPN 服务器（默认）……")"
    ssh_setup_server "$SERVER_PUB_IP" 22 143 444 80
  fi

  if [[ "$WITH_OPENVPN" -eq 1 ]]; then
    log_step "$(T "Installing OpenVPN server..." "Memasang OpenVPN Server..." "正在安装 OpenVPN 服务器……")"
    install_openvpn_packages
    ovpn_setup_server 1194 udp "$NET_IFACE" "$SERVER_PUB_IP"
    ovpn_create_client "${FIRST_CLIENT}-ovpn" || true
  fi

  if [[ "$WITH_XRAY" -eq 1 ]]; then
    log_step "$(T "Installing ${XRAY_ENGINE} server (VMess/VLESS/Trojan + XTLS/REALITY)..." "Memasang ${XRAY_ENGINE} Server (VMess/VLESS/Trojan + XTLS/REALITY)..." "正在安装 ${XRAY_ENGINE} 服务器 (VMess/VLESS/Trojan + XTLS/REALITY)……")"
    xray_setup_server "$SERVER_PUB_IP"
  fi

  if [[ "$WITH_SHADOWSOCKS" -eq 1 ]]; then
    log_step "$(T "Installing Shadowsocks server..." "Memasang Shadowsocks Server..." "正在安装 Shadowsocks 服务器……")"
    ss_setup_server 8388 "$(gen_password 18)" "$SS_METHOD_DEFAULT" "$SERVER_PUB_IP"
  fi

  # 15b. Register default limit for the first client + install monitor (wrwb Store)
  limits_set "$FIRST_CLIENT" "2" "100"
  log_info "$(T "Default limit for '$FIRST_CLIENT': 2 concurrent IPs, 100 GB/month." "Limit default '$FIRST_CLIENT': 2 IP concurrent, 100 GB/bulan." "'$FIRST_CLIENT' 的默认限制：2 个并发 IP，100 GB/月。")"
  limits_install_monitor_service

  # 16. Show QR code & final instructions
  echo ""
  log_success "$(T "WireGuard VPN installation COMPLETE!" "Instalasi VPN WireGuard SELESAI!" "WireGuard VPN 安装完成！")"
  echo ""
  echo "==================== $(T "INSTALLATION INFO" "INFORMASI INSTALASI" "安装信息") ===================="
  echo " $(T "Server public IP : $SERVER_PUB_IP" "Server IP Publik : $SERVER_PUB_IP" "服务器公网 IP：$SERVER_PUB_IP")"
  echo " $(T "WireGuard port   : $SERVER_PORT (UDP)" "WireGuard Port   : $SERVER_PORT (UDP)" "WireGuard 端口：$SERVER_PORT (UDP)")"
  echo " $(T "VPN subnet       : $SERVER_SUBNET" "Subnet VPN       : $SERVER_SUBNET" "VPN 子网：$SERVER_SUBNET")"
  echo " $(T "DNS servers      : $SERVER_DNS" "DNS Server       : $SERVER_DNS" "DNS 服务器：$SERVER_DNS")"
  echo " $(T "First client     : $FIRST_CLIENT" "Client Pertama   : $FIRST_CLIENT" "首个客户端：$FIRST_CLIENT")"
  echo " $(T "Config file      : $LAST_CLIENT_CONF" "File Konfigurasi : $LAST_CLIENT_CONF" "配置文件：$LAST_CLIENT_CONF")"
  echo " $(T "QR code image    : $LAST_CLIENT_PNG" "Gambar QR Code   : $LAST_CLIENT_PNG" "二维码图片：$LAST_CLIENT_PNG")"
  echo "============================================================="

  # Show ANSI QR code
  wg_show_client_qr "$LAST_CLIENT_CONF"

  echo "$(T "Quick commands:" "Perintah Cepat:" "常用命令：")"
  echo "  - $(T "Add new user    : sudo ./add-client.sh <client_name>" "Tambah user baru : sudo ./add-client.sh <nama_client>" "添加新用户：sudo ./add-client.sh <client_name>")"
  echo "  - $(T "Remove user     : sudo ./remove-client.sh <client_name>" "Hapus user       : sudo ./remove-client.sh <nama_client>" "删除用户：sudo ./remove-client.sh <client_name>")"
  echo "  - $(T "List clients    : sudo ./list-clients.sh" "Daftar client    : sudo ./list-clients.sh" "列出客户端：sudo ./list-clients.sh")"
  echo "  - $(T "Check status    : sudo ./status.sh" "Cek status       : sudo ./status.sh" "检查状态：sudo ./status.sh")"
  echo "  - $(T "Interactive menu: sudo ./menu.sh" "Menu interaktif  : sudo ./menu.sh" "交互式菜单：sudo ./menu.sh")"
  if [[ "$WITH_SSH" -eq 1 ]]; then
    echo "  - $(T "SSH accounts    : sudo ./add-ssh-user.sh <username> | sudo ./remove-ssh-user.sh <username>" "Akun SSH         : sudo ./add-ssh-user.sh <username> | sudo ./remove-ssh-user.sh <username>" "SSH 账号：sudo ./add-ssh-user.sh <username> | sudo ./remove-ssh-user.sh <username>")"
  fi
  if [[ "$WITH_XRAY" -eq 1 ]]; then
    echo "  - $(T "Xray/V2Ray users: sudo ./add-xray-user.sh <name> | sudo ./remove-xray-user.sh <name>" "User Xray/V2Ray  : sudo ./add-xray-user.sh <nama> | sudo ./remove-xray-user.sh <nama>" "Xray/V2Ray 用户：sudo ./add-xray-user.sh <name> | sudo ./remove-xray-user.sh <name>")"
  fi
  echo ""
}

main "$@"
