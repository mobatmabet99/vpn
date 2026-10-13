#!/bin/bash
# ==============================================================================
#  install.sh — Skrip Otomatisasi Instalasi VPN WireGuard
#  Mendukung:
#    - Ubuntu 20.04 / 22.04 / 24.04 / 26.04 LTS (dan versi seterusnya)
#    - Debian 10 (Buster) / 11 (Bullseye) / 12 (Bookworm) / 13 (Trixie)
#    - CentOS / Rocky Linux / AlmaLinux 8 / 9
#    - RHEL 8 / 9 & Fedora
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Muat modul pendukung
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

# Default Konfigurasi
DEFAULT_PORT="51820"
DEFAULT_DNS="1.1.1.1, 1.0.0.1"
DEFAULT_CLIENT="client1"
DEFAULT_SUBNET="10.66.66.0/24"
DEFAULT_SERVER_IP="10.66.66.1"

# Banner
print_banner() {
  cat <<'EOF'
 ================================================================
    __     ______  _   _    ___           _        _ _           
    \ \   / /  _ \| \ | |  |_ _|_ __  ___| |_ __ _| | | ___ _ __ 
     \ \ / /| |_) |  \| |   | || '_ \/ __| __/ _` | | |/ _ \ '__|
      \ V / |  __/| |\  |   | || | | \__ \ || (_| | | |  __/ |   
       \_/  |_|   |_| \_|  |___|_| |_|___/\__\__,_|_|_|\___|_|   
                                                                 
    Otomatisasi Instalasi VPN Multi-Distro (WireGuard Engine)
 ================================================================
EOF
}

# Parsing Argumen Baris Perintah
CLI_PORT=""
CLI_CLIENT=""
CLI_DNS=""
CLI_YES=0
WITH_OPENVPN=0
WITH_SHADOWSOCKS=0
# SSH & Xray aktif default — bisa dimatikan eksplisit via --no-ssh / --no-xray
WITH_SSH=1
WITH_XRAY=1
# Engine tunnel: "xray" (default, XTLS+REALITY) atau "v2ray"
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
        echo "Penggunaan: sudo ./install.sh [opsi]"
        echo "Opsi:"
        echo "  -p, --port <port>          Port WireGuard (default: 51820)"
        echo "  -c, --client <nama>        Nama client pertama (default: client1)"
        echo "  -d, --dns <ip1,ip2>        DNS Server (default: 1.1.1.1, 1.0.0.1)"
        echo "  -y, --yes                  Mode non-interaktif (gunakan nilai default)"
        echo "      --with-ssh             Pasang SSH VPN (DEFAULT AKTIF)"
        echo "      --with-openvpn         Pasang OpenVPN (pengganti SSH, saling eksklusif)"
        echo "      --no-ssh               Jangan pasang SSH maupun OpenVPN"
        echo "      --with-xray            Pasang Xray-core (DEFAULT AKTIF)"
        echo "      --with-v2ray           Pasang v2ray-core (pengganti Xray)"
        echo "      --no-xray              Jangan pasang Xray/V2Ray"
        echo "      --with-shadowsocks     Sekaligus instal Shadowsocks"
        echo "  -h, --help                 Tampilkan bantuan ini"
        echo ""
        echo "Contoh:"
        echo "  sudo ./install.sh --yes                                   # default: WG + SSH + Xray"
        echo "  sudo ./install.sh --with-openvpn --with-v2ray --yes       # WG + OpenVPN + V2Ray"
        echo "  XRAY_ENGINE=v2ray sudo ./install.sh --yes                 # pilih engine via env"
        exit 0
        ;;
      *)
        die "Opsi tidak dikenal: $1. Gunakan --help untuk bantuan."
        ;;
    esac
  done
}

main() {
  print_banner
  parse_args "$@"

  # 1. Validasi Akses Root
  need_root

  # 2. Periksa Perangkat TUN
  check_tun
  check_virt

  # 3. Validasi & Deteksi OS
  check_os_supported

  # Cek apakah WireGuard sudah terpasang sebelumnya
  if [[ -f /etc/wireguard/params && -f /etc/wireguard/wg0.conf ]]; then
    log_warn "WireGuard sepertinya sudah terpasang di sistem ini."
    if [[ "$CLI_YES" -eq 0 ]]; then
      echo "Pilihan:"
      echo "  1) Tambah client baru (add-client.sh)"
      echo "  2) Instal ulang / Re-install bersih"
      echo "  3) Keluar"
      read -rp "Pilih [1-3] (default 1): " ex_choice
      ex_choice="${ex_choice:-1}"
      case "$ex_choice" in
        1) exec "$SCRIPT_DIR/add-client.sh" ;;
        2) log_warn "Melanjutkan instal ulang WireGuard..." ;;
        *) exit 0 ;;
      esac
    fi
  fi

  # 4. Deteksi Parameter Jaringan
  log_step "Mendeteksi antarmuka jaringan dan IP publik..."
  NET_IFACE="$(get_default_iface)"
  SERVER_PUB_IP="$(get_public_ip)"
  log_info "Antarmuka publik : $NET_IFACE"
  log_info "IP Publik server : $SERVER_PUB_IP"

  # 5. Tanya Parameter (atau gunakan CLI / default)
  if [[ "$CLI_YES" -eq 1 ]]; then
    SERVER_PORT="${CLI_PORT:-$DEFAULT_PORT}"
    SERVER_DNS="${CLI_DNS:-$DEFAULT_DNS}"
    FIRST_CLIENT="${CLI_CLIENT:-$DEFAULT_CLIENT}"
  else
    # Port
    echo ""
    read -rp "Port WireGuard [$DEFAULT_PORT]: " input_port
    SERVER_PORT="${input_port:-$DEFAULT_PORT}"
    [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] && [[ "$SERVER_PORT" -ge 1 && "$SERVER_PORT" -le 65535 ]] || die "Port harus berupa angka antara 1-65535."

    # DNS
    echo ""
    echo "Pilihan DNS Server:"
    echo "  1) Cloudflare (1.1.1.1, 1.0.0.1) - Cepat & Privasi (Rekomendasi)"
    echo "  2) Google (8.8.8.8, 8.8.4.4)"
    echo "  3) AdGuard DNS (94.140.14.14 - Blokir Iklan)"
    echo "  4) Kustom"
    read -rp "Pilih DNS [1-4] (default 1): " dns_choice
    case "${dns_choice:-1}" in
      1) SERVER_DNS="1.1.1.1, 1.0.0.1" ;;
      2) SERVER_DNS="8.8.8.8, 8.8.4.4" ;;
      3) SERVER_DNS="94.140.14.14, 94.140.15.15" ;;
      4)
        read -rp "Masukkan IP DNS (pisahkan koma): " custom_dns
        SERVER_DNS="${custom_dns:-1.1.1.1}"
        ;;
      *) SERVER_DNS="1.1.1.1, 1.0.0.1" ;;
    esac

    # Nama Client Pertama
    echo ""
    read -rp "Nama client pertama [$DEFAULT_CLIENT]: " input_client
    FIRST_CLIENT="${input_client:-$DEFAULT_CLIENT}"
    validate_client_name "$FIRST_CLIENT"

    # Opsi Protokol Tambahan — SSH default YA, OpenVPN sebagai alternatif
    echo ""
    echo "Pilih layanan login tunnel:"
    echo "  1) SSH VPN (Dropbear + Stunnel + WebSocket) — DEFAULT, ringan & universal"
    echo "  2) OpenVPN (port 1194/UDP + profil .ovpn)"
    echo "  3) Keduanya"
    echo "  4) Tidak pasang keduanya"
    read -rp "Pilih layanan login [1-4] (default 1): " login_choice
    case "${login_choice:-1}" in
      1) WITH_SSH=1; WITH_OPENVPN=0 ;;
      2) WITH_SSH=0; WITH_OPENVPN=1 ;;
      3) WITH_SSH=1; WITH_OPENVPN=1 ;;
      4) WITH_SSH=0; WITH_OPENVPN=0 ;;
      *) WITH_SSH=1; WITH_OPENVPN=0 ;;
    esac

    # Opsi Engine Tunnel — Xray default, V2Ray alternatif
    echo ""
    echo "Pilih engine tunnel (VMess/VLESS/Trojan + XTLS/REALITY):"
    echo "  1) Xray-core v26.3.27 — DEFAULT, XTLS-Vision + REALITY tercepat"
    echo "  2) v2ray-core v5.53.0 — alternatif stabil"
    echo "  3) Tidak pasang keduanya"
    read -rp "Pilih engine tunnel [1-3] (default 1): " engine_choice
    case "${engine_choice:-1}" in
      1) WITH_XRAY=1; XRAY_ENGINE="xray" ;;
      2) WITH_XRAY=1; XRAY_ENGINE="v2ray" ;;
      3) WITH_XRAY=0 ;;
      *) WITH_XRAY=1; XRAY_ENGINE="xray" ;;
    esac

    read -rp "Ingin sekalian memasang Shadowsocks? [y/N]: " ask_ss
    [[ "$ask_ss" =~ ^[Yy]$ ]] && WITH_SHADOWSOCKS=1 || true
  fi

  # Validasi global (berlaku untuk mode interaktif & non-interaktif)
  [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] && [[ "$SERVER_PORT" -ge 1 && "$SERVER_PORT" -le 65535 ]] || die "Port '$SERVER_PORT' tidak valid. Gunakan angka 1-65535."
  validate_client_name "$FIRST_CLIENT"
  if is_port_in_use "$SERVER_PORT" "udp"; then
    log_warn "Port UDP $SERVER_PORT sepertinya sudah dipakai oleh aplikasi lain."
    if [[ "$CLI_YES" -eq 0 ]]; then
      confirm "Tetap lanjutkan dengan port $SERVER_PORT? [y/N] " || die "Instalasi dibatalkan. Jalankan ulang dengan port lain (mis. --port 51821)."
    fi
  fi

  SERVER_SUBNET="$DEFAULT_SUBNET"
  SERVER_IP="$DEFAULT_SERVER_IP"
  WG_CONF="/etc/wireguard/wg0.conf"
  CLIENT_DIR="/etc/wireguard/clients"

  # 6. Pasang Paket Dependensi
  install_wireguard_packages

  # 7. Aktifkan IP Forwarding
  enable_ip_forwarding

  # 8. Buka Port Firewall
  open_firewall_port "$SERVER_PORT" "udp"

  # 9. Buat Kunci Server WireGuard
  wg_generate_server_keys

  # 10. Tulis Konfigurasi Server wg0.conf
  wg_write_server_conf "$SERVER_PORT" "$NET_IFACE" "10.66.66.1/24" "fd42:42:42::1/64"

  # 11. Simpan File Parameter Server (/etc/wireguard/params)
  save_params

  # 12. Buat Client Pertama
  log_step "Membuat profil untuk client '$FIRST_CLIENT'..."
  wg_create_client "$FIRST_CLIENT"

  # 13. Aktifkan dan Jalankan Layanan WireGuard
  wg_enable_and_start

  # 14. Pasang Protokol Tambahan sesuai pilihan (default: SSH + Xray)
  if [[ "$WITH_SSH" -eq 1 ]]; then
    log_step "Memasang SSH VPN Server (default)..."
    ssh_setup_server "$SERVER_PUB_IP" 22 143 444 80
  fi

  if [[ "$WITH_OPENVPN" -eq 1 ]]; then
    log_step "Memasang OpenVPN Server..."
    install_openvpn_packages
    ovpn_setup_server 1194 udp "$NET_IFACE" "$SERVER_PUB_IP"
    ovpn_create_client "${FIRST_CLIENT}-ovpn" || true
  fi

  if [[ "$WITH_XRAY" -eq 1 ]]; then
    log_step "Memasang ${XRAY_ENGINE} Server (VMess/VLESS/Trojan + XTLS/REALITY)..."
    xray_setup_server "$SERVER_PUB_IP"
  fi

  if [[ "$WITH_SHADOWSOCKS" -eq 1 ]]; then
    log_step "Memasang Shadowsocks Server..."
    ss_setup_server 8388 "$(gen_password 18)" "$SS_METHOD_DEFAULT" "$SERVER_PUB_IP"
  fi

  # 15. Tampilkan QR Code & Petunjuk Akhir
  echo ""
  log_success "Instalasi VPN WireGuard SELESAI!"
  echo ""
  echo "==================== INFORMASI INSTALASI ===================="
  echo " Server IP Publik : $SERVER_PUB_IP"
  echo " WireGuard Port   : $SERVER_PORT (UDP)"
  echo " Subnet VPN       : $SERVER_SUBNET"
  echo " DNS Server       : $SERVER_DNS"
  echo " Client Pertama   : $FIRST_CLIENT"
  echo " File Konfigurasi : $LAST_CLIENT_CONF"
  echo " Gambar QR Code   : $LAST_CLIENT_PNG"
  echo "============================================================="

  # Tampilkan QR Code ANSI
  wg_show_client_qr "$LAST_CLIENT_CONF"

  echo "Perintah Cepat:"
  echo "  - Tambah user baru : sudo ./add-client.sh <nama_client>"
  echo "  - Hapus user       : sudo ./remove-client.sh <nama_client>"
  echo "  - Daftar client    : sudo ./list-clients.sh"
  echo "  - Cek status       : sudo ./status.sh"
  echo "  - Menu interaktif  : sudo ./menu.sh"
  if [[ "$WITH_SSH" -eq 1 ]]; then
    echo "  - Akun SSH         : sudo ./add-ssh-user.sh <username> | sudo ./remove-ssh-user.sh <username>"
  fi
  if [[ "$WITH_XRAY" -eq 1 ]]; then
    echo "  - User Xray/V2Ray  : sudo ./add-xray-user.sh <nama> | sudo ./remove-xray-user.sh <nama>"
  fi
  echo ""
}

main "$@"
