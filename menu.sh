#!/bin/bash
# ==============================================================================
#  menu.sh — Interactive VPN server management menu (bilingual EN/ID)
#  Usage:
#    sudo ./menu.sh [--lang en|id]
#  Branding: wrwb Store
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# CLI override: --lang en|id (optional; otherwise persisted /etc/vpn/lang)
for _ma in "$@"; do
  case "$_ma" in
    --lang=*) VPN_LANG_CLI="${_ma#--lang=}" ;;
    --lang) _menu_lang_next=1 ;;
    *) if [[ "${_menu_lang_next:-0}" == "1" ]]; then VPN_LANG_CLI="$_ma"; _menu_lang_next=0; fi ;;
  esac
done
unset _ma
export VPN_LANG_CLI="${VPN_LANG_CLI:-}"

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
      ____  ___  _   _ _____ _____ ____     __  __ _____ _   _ _
     |  _ \/ _ \| | | |_   _| ____|  _ \   |  \/  | ____| \ | | | | |
     | |_) | | | | | | | | | |  _| | |_) |  | |\/| |  _| |  \| | | | |
     |  _ <| |_| | |_| | | | | |___|  _ <   | |  | | |___| |\  | |_| |
     |_| \_\\___/ \___/  |_| |_____|_| \_\  |_|  |_|_____|_| \_|\___/

EOF
  echo "         $(T "VPN Control Panel & Multi-Protocol Linux Management" "Panel Kontrol & Manajemen VPN Multi-Protokol Linux")"
  echo "         $(T "by wrwb Store" "Dibuat oleh wrwb Store") | $(lang_label)"
  echo " ================================================================"
  local wg_state
  wg_state="$(systemctl is-active wg-quick@wg0 2>/dev/null || echo "$(T "Not active yet" "Belum aktif")")"
  echo " $(T "WireGuard status: $wg_state" "Status WireGuard: $wg_state")"
  echo "----------------------------------------------------------------"
  echo " [1]  $(T "Install / set up WireGuard VPN server" "Instal / Setup Server VPN WireGuard")"
  echo " [2]  $(T "Add new client (WireGuard)" "Tambah Client Baru (WireGuard)")"
  echo " [3]  $(T "Remove client (WireGuard)" "Hapus Client (WireGuard)")"
  echo " [4]  $(T "Show client QR code & config" "Tampilkan QR Code & Konfigurasi Client")"
  echo " [5]  $(T "List clients & traffic stats" "Lihat Daftar Client & Statistik Trafik")"
  echo " [6]  $(T "Check server status & diagnostics (firewall/NAT/services)" "Cek Status Server & Diagnostik (Firewall/NAT/Service)")"
  echo "----------------------------------------------------------------"
  echo " [7]  $(T "Install / configure SSH VPN — Dropbear+Stunnel+WS (DEFAULT)" "Instal / Konfigurasi SSH VPN — Dropbear+Stunnel+WS (DEFAULT)")"
  echo " [8]  $(T "Install / configure OpenVPN (SSH alternative)" "Instal / Konfigurasi OpenVPN (alternatif SSH)")"
  echo " [9]  $(T "Install / configure Xray-core — VMess/VLESS/Trojan+REALITY (DEFAULT)" "Instal / Konfigurasi Xray-core — VMess/VLESS/Trojan+REALITY (DEFAULT)")"
  echo " [10] $(T "Install / configure v2ray-core (Xray alternative)" "Instal / Konfigurasi v2ray-core (alternatif Xray)")"
  echo " [11] $(T "Install / configure Shadowsocks (optional)" "Instal / Konfigurasi Shadowsocks (Opsional)")"
  echo " [12] $(T "Manage SSH accounts (add/remove/list)" "Kelola Akun SSH (tambah/hapus/daftar)")"
  echo " [13] $(T "Manage Xray/V2Ray users (add/remove/list)" "Kelola User Xray/V2Ray (tambah/hapus/daftar)")"
  echo " [14] $(T "Restart all VPN services" "Mulai Ulang Semua Layanan VPN")"
  echo " [15] $(T "Uninstall / cleanly remove VPN from server" "Uninstall / Hapus Bersih VPN dari Server")"
  echo " [16] $(T "Check IP & bandwidth limits (wrwb Store)" "Cek Limit IP & Bandwidth (wrwb Store)")"
  echo " [17] $(T "Switch language (English/Indonesia)" "Ganti bahasa (English/Indonesia)")"
  echo " [0]  $(T "Exit" "Keluar")"
  echo "================================================================"
  echo " $(T "by wrwb Store" "Dibuat oleh wrwb Store")"
}

pause() {
  echo ""
  read -rp "$(T "Press [Enter] to return to the menu..." "Tekan [Enter] untuk kembali ke menu...")" _
}

menu_switch_language() {
  echo ""
  echo "$(T "Current: " "Saat ini: ")$(lang_label)"
  echo "  1) English"
  echo "  2) Indonesia"
  local c=""
  read -rp "$(T "Choose language [1-2] (default 1): " "Pilih bahasa [1-2] (default 1): ")" c || true
  case "${c:-1}" in
    2) VPN_LANG="id" ;;
    *) VPN_LANG="en" ;;
  esac
  export VPN_LANG
  lang_save
  log_success "$(T "Language set to English." "Bahasa diatur ke Indonesia.")"
}

main_loop() {
  while true; do
    show_menu
    read -rp "$(T "Choose menu [0-17]: " "Pilih menu [0-17]: ")" choice
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
        read -rp "$(T "Create the first SSH account now? [Y/n]: " "Buat akun SSH pertama sekarang? [Y/n]: ")" make_ssh_u
        if [[ ! "${make_ssh_u:-Y}" =~ ^[Nn]$ ]]; then
          read -rp "$(T "Username: " "Username: ")" ssh_uname
          ssh_uname="${ssh_uname:-user1}"
          ssh_create_user "$ssh_uname" "" 30
          echo "$(T "Username: $SSH_LAST_USER | Password: $SSH_LAST_PASS | Valid until: $SSH_LAST_EXPIRE" "Username: $SSH_LAST_USER | Password: $SSH_LAST_PASS | Berlaku s/d: $SSH_LAST_EXPIRE")"
        fi
        pause
        ;;
      8)
        install_openvpn_packages
        ovpn_setup_server 1194 udp "$(get_default_iface)" "$(get_public_ip)"
        read -rp "$(T "Create the first OpenVPN client now? [y/N]: " "Buat client OpenVPN pertama sekarang? [y/N]: ")" make_ovpn_c
        if [[ "$make_ovpn_c" =~ ^[Yy]$ ]]; then
          read -rp "$(T "Client name: " "Nama client: ")" ovpn_name
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
        read -rp "$(T "Shadowsocks port [8388]: " "Port Shadowsocks [8388]: ")" ss_p
        ss_p="${ss_p:-8388}"
        ss_setup_server "$ss_p" "$(gen_password 18)" "$SS_METHOD_DEFAULT" "$(get_public_ip)"
        pause
        ;;
      12)
        echo "$(T "Manage SSH accounts:" "Kelola Akun SSH:")"
        echo "  1) $(T "Add account" "Tambah akun")"
        echo "  2) $(T "Remove account" "Hapus akun")"
        echo "  3) $(T "List accounts" "Daftar akun")"
        read -rp "$(T "Choose [1-3]: " "Pilih [1-3]: ")" ssh_m
        case "$ssh_m" in
          1) "$SCRIPT_DIR/add-ssh-user.sh" ;;
          2) "$SCRIPT_DIR/remove-ssh-user.sh" ;;
          3) ssh_list_users ;;
          *) log_warn "$(T "Invalid choice." "Pilihan tidak valid.")" ;;
        esac
        pause
        ;;
      13)
        echo "$(T "Manage Xray/V2Ray users:" "Kelola User Xray/V2Ray:")"
        echo "  1) $(T "Add user" "Tambah user")"
        echo "  2) $(T "Remove user" "Hapus user")"
        echo "  3) $(T "List users" "Daftar user")"
        read -rp "$(T "Choose [1-3]: " "Pilih [1-3]: ")" xr_m
        case "$xr_m" in
          1) "$SCRIPT_DIR/add-xray-user.sh" ;;
          2) "$SCRIPT_DIR/remove-xray-user.sh" ;;
          3) xray_list_users ;;
          *) log_warn "$(T "Invalid choice." "Pilihan tidak valid.")" ;;
        esac
        pause
        ;;
      14)
        log_step "$(T "Restarting WireGuard service..." "Memulai ulang layanan WireGuard...")"
        systemctl restart wg-quick@wg0 2>/dev/null && log_success "$(T "WireGuard restarted." "WireGuard dimulai ulang.")" || log_warn "$(T "WireGuard is not active." "WireGuard tidak aktif.")"
        if systemctl list-unit-files | grep -qE "openvpn-server@|openvpn@"; then
          systemctl restart openvpn-server@server 2>/dev/null || systemctl restart openvpn@server 2>/dev/null || true
          log_success "$(T "OpenVPN restarted." "OpenVPN dimulai ulang.")"
        fi
        if systemctl list-unit-files 2>/dev/null | grep -q "shadowsocks-rust"; then
          systemctl restart shadowsocks-rust 2>/dev/null || true
          log_success "$(T "Shadowsocks restarted." "Shadowsocks dimulai ulang.")"
        fi
        for svc in ssh dropbear ssh-ws xray; do
          if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\\.service"; then
            systemctl restart "$svc" 2>/dev/null || true
            log_success "$(T "$svc restarted." "$svc dimulai ulang.")"
          fi
        done
        if systemctl list-unit-files 2>/dev/null | grep -q "^stunnel4\\.service"; then
          systemctl restart stunnel4 2>/dev/null || true
          log_success "$(T "stunnel4 restarted." "stunnel4 dimulai ulang.")"
        fi
        pause
        ;;
      15)
        "$SCRIPT_DIR/uninstall.sh"
        pause
        ;;
      16)
        "$SCRIPT_DIR/check-limits.sh"
        pause
        ;;
      17)
        menu_switch_language
        pause
        ;;
      0)
        echo "$(T "Goodbye!" "Sampai jumpa!")"
        exit 0
        ;;
      *)
        log_warn "$(T "Invalid choice." "Pilihan tidak valid.")"
        sleep 1
        ;;
    esac
  done
}

main_loop
