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
# shellcheck source=lib/ssh.sh
source "$SCRIPT_DIR/lib/ssh.sh"
# shellcheck source=lib/xray.sh
source "$SCRIPT_DIR/lib/xray.sh"

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
  echo " [7]  Instal / Konfigurasi SSH VPN — Dropbear+Stunnel+WS (DEFAULT)"
  echo " [8]  Instal / Konfigurasi OpenVPN (alternatif SSH)"
  echo " [9]  Instal / Konfigurasi Xray-core — VMess/VLESS/Trojan+REALITY (DEFAULT)"
  echo " [10] Instal / Konfigurasi v2ray-core (alternatif Xray)"
  echo " [11] Instal / Konfigurasi Shadowsocks (Opsional)"
  echo " [12] Kelola Akun SSH (tambah/hapus/daftar)"
  echo " [13] Kelola User Xray/V2Ray (tambah/hapus/daftar)"
  echo " [14] Mulai Ulang Semua Layanan VPN"
  echo " [15] Uninstall / Hapus Bersih VPN dari Server"
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
    read -rp "Pilih menu [0-15]: " choice
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
        ssh_setup_server "$(get_public_ip)" 22 143 444 80
        read -rp "Buat akun SSH pertama sekarang? [Y/n]: " make_ssh_u
        if [[ ! "${make_ssh_u:-Y}" =~ ^[Nn]$ ]]; then
          read -rp "Username: " ssh_uname
          ssh_uname="${ssh_uname:-user1}"
          ssh_create_user "$ssh_uname" "" 30
          echo "Username: $SSH_LAST_USER | Password: $SSH_LAST_PASS | Berlaku s/d: $SSH_LAST_EXPIRE"
        fi
        pause
        ;;
      8)
        install_openvpn_packages
        ovpn_setup_server 1194 udp "$(get_default_iface)" "$(get_public_ip)"
        read -rp "Buat client OpenVPN pertama sekarang? [y/N]: " make_ovpn_c
        if [[ "$make_ovpn_c" =~ ^[Yy]$ ]]; then
          read -rp "Nama client: " ovpn_name
          ovpn_create_client "${ovpn_name:-client1}"
        fi
        pause
        ;;
      9)
        XRAY_ENGINE="xray"
        xray_setup_server "$(get_public_ip)"
        pause
        ;;
      10)
        XRAY_ENGINE="v2ray"
        xray_setup_server "$(get_public_ip)"
        pause
        ;;
      11)
        read -rp "Port Shadowsocks [8388]: " ss_p
        ss_p="${ss_p:-8388}"
        ss_setup_server "$ss_p" "$(gen_password 18)" "$SS_METHOD_DEFAULT" "$(get_public_ip)"
        pause
        ;;
      12)
        echo "Kelola Akun SSH:"
        echo "  1) Tambah akun"
        echo "  2) Hapus akun"
        echo "  3) Daftar akun"
        read -rp "Pilih [1-3]: " ssh_m
        case "$ssh_m" in
          1) "$SCRIPT_DIR/add-ssh-user.sh" ;;
          2) "$SCRIPT_DIR/remove-ssh-user.sh" ;;
          3) ssh_list_users ;;
          *) log_warn "Pilihan tidak valid." ;;
        esac
        pause
        ;;
      13)
        echo "Kelola User Xray/V2Ray:"
        echo "  1) Tambah user"
        echo "  2) Hapus user"
        echo "  3) Daftar user"
        read -rp "Pilih [1-3]: " xr_m
        case "$xr_m" in
          1) "$SCRIPT_DIR/add-xray-user.sh" ;;
          2) "$SCRIPT_DIR/remove-xray-user.sh" ;;
          3) xray_list_users ;;
          *) log_warn "Pilihan tidak valid." ;;
        esac
        pause
        ;;
      14)
        log_step "Memulai ulang layanan WireGuard..."
        systemctl restart wg-quick@wg0 2>/dev/null && log_success "WireGuard dimulai ulang." || log_warn "WireGuard tidak aktif."
        if systemctl list-unit-files | grep -qE "openvpn-server@|openvpn@"; then
          systemctl restart openvpn-server@server 2>/dev/null || systemctl restart openvpn@server 2>/dev/null || true
          log_success "OpenVPN dimulai ulang."
        fi
        if systemctl list-unit-files | grep -q "shadowsocks-rust"; then
          systemctl restart shadowsocks-rust 2>/dev/null || true
          log_success "Shadowsocks dimulai ulang."
        fi
        for svc in ssh dropbear ssh-ws xray; do
          if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\\.service"; then
            systemctl restart "$svc" 2>/dev/null || true
            log_success "$svc dimulai ulang."
          fi
        done
        if systemctl list-unit-files 2>/dev/null | grep -q "^stunnel4\\.service"; then
          systemctl restart stunnel4 2>/dev/null || true
          log_success "stunnel4 dimulai ulang."
        fi
        pause
        ;;
      15)
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
