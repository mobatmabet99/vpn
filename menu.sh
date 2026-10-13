#!/bin/bash
# ==============================================================================
#  menu.sh — Menu Interaktif Manajemen VPN Server
#  Penggunaan:
#    sudo ./menu.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

need_root

show_menu() {
  clear 2>/dev/null || true
  cat <<'EOF'
 ================================================================
       ____  ___  _   _ _____ _____ ____     __  __ _____ _   _ _   _ 
      |  _ \/ _ \| | | |_   _| ____|  _ \   |  \/  | ____| \ | | | | |
      | |_) | | | | | | | | | |  _| | |_) |  | |\/| |  _| |  \| | | | |
      |  _ <| |_| | |_| | | | | |___|  _ <   | |  | | |___| |\  | |_| |
      |_| \_\\___/ \___/  |_| |_____|_| \_\  |_|  |_|_____|_| \_|\___/ 
                                                                       
        Panel Kontrol & Manajemen VPN Multi-Protokol Linux
 ================================================================
EOF
  echo " Status WireGuard: $(systemctl is-active wg-quick@wg0 2>/dev/null || echo 'Belum aktif')"
  echo "----------------------------------------------------------------"
  echo " [1]  Instal / Setup Server VPN WireGuard"
  echo " [2]  Tambah Client Baru (WireGuard)"
  echo " [3]  Hapus Client (WireGuard)"
  echo " [4]  Tampilkan QR Code & Konfigurasi Client"
  echo " [5]  Lihat Daftar Client & Statistik Trafik"
  echo " [6]  Cek Status Server & Diagnostik (Firewall/NAT/Service)"
  echo "----------------------------------------------------------------"
  echo " [7]  Instal / Konfigurasi OpenVPN (Opsional)"
  echo " [8]  Instal / Konfigurasi Shadowsocks (Opsional)"
  echo " [9]  Restart Semua Layanan VPN"
  echo " [10] Uninstall / Hapus Bersih VPN dari Server"
  echo " [0]  Keluar"
  echo "================================================================"
}

pause() {
  echo ""
  read -rp "Tekan [Enter] untuk kembali ke menu..." _
}

main_loop() {
  while true; do
    show_menu
    read -rp "Pilih menu [0-10]: " choice
    case "$choice" in
      1)
        "$SCRIPT_DIR/install.sh"
        pause
        ;;
      2)
        "$SCRIPT_DIR/add-client.sh"
        pause
        ;;
      3)
        "$SCRIPT_DIR/remove-client.sh"
        pause
        ;;
      4)
        "$SCRIPT_DIR/show-qr.sh"
        pause
        ;;
      5)
        "$SCRIPT_DIR/list-clients.sh"
        pause
        ;;
      6)
        "$SCRIPT_DIR/status.sh"
        pause
        ;;
      7)
        install_openvpn_packages
        ovpn_setup_server 1194 udp "$(get_default_iface)" "$(get_public_ip)"
        read -rp "Buat client OpenVPN pertama sekarang? [y/N]: " make_ovpn_c
        if [[ "$make_ovpn_c" =~ ^[Yy]$ ]]; then
          read -rp "Nama client: " ovpn_name
          ovpn_create_client "${ovpn_name:-client1}"
        fi
        pause
        ;;
      8)
        read -rp "Port Shadowsocks [8388]: " ss_p
        ss_p="${ss_p:-8388}"
        ss_setup_server "$ss_p" "$(gen_password 18)" "aes-256-gcm" "$(get_public_ip)"
        pause
        ;;
      9)
        log_step "Me-restart layanan WireGuard..."
        systemctl restart wg-quick@wg0 2>/dev/null && log_success "WireGuard di-restart." || log_warn "WireGuard tidak aktif."
        if systemctl list-unit-files | grep -qE "openvpn-server@|openvpn@"; then
          systemctl restart openvpn-server@server 2>/dev/null || systemctl restart openvpn@server 2>/dev/null || true
          log_success "OpenVPN di-restart."
        fi
        if systemctl list-unit-files | grep -q "shadowsocks-rust"; then
          systemctl restart shadowsocks-rust 2>/dev/null || true
          log_success "Shadowsocks di-restart."
        fi
        pause
        ;;
      10)
        "$SCRIPT_DIR/uninstall.sh"
        pause
        ;;
      0)
        echo "Sampai jumpa!"
        exit 0
        ;;
      *)
        log_warn "Pilihan tidak valid."
        sleep 1
        ;;
    esac
  done
}

main_loop
