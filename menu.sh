#!/bin/bash
# ==============================================================================
#  menu.sh — Interactive VPN server management menu (trilingual EN/ID/ZH)
#  Usage:
#    sudo ./menu.sh [--lang en|id|zh]
#  Branding: wrwb Store
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# CLI override: --lang en|id|zh (optional; otherwise persisted /etc/vpn/lang)
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
  echo "         $(T "VPN Control Panel & Multi-Protocol Linux Management" "Panel Kontrol & Manajemen VPN Multi-Protokol Linux" "VPN 控制面板与多协议 Linux 管理")"
  echo "         $(T "by wrwb Store" "Dibuat oleh wrwb Store" "由 wrwb Store 打造") | $(lang_label)"
  echo " ================================================================"
  local wg_state
  wg_state="$(systemctl is-active wg-quick@wg0 2>/dev/null || echo "$(T "Not active yet" "Belum aktif" "尚未激活")")"
  echo " $(T "WireGuard status: $wg_state" "Status WireGuard: $wg_state" "WireGuard 状态：$wg_state")"
  echo "----------------------------------------------------------------"
  echo " [1]  $(T "Install / set up WireGuard VPN server" "Instal / Setup Server VPN WireGuard" "安装 / 配置 WireGuard VPN 服务器")"
  echo " [2]  $(T "Add new client (WireGuard)" "Tambah Client Baru (WireGuard)" "添加新客户端 (WireGuard)")"
  echo " [3]  $(T "Remove client (WireGuard)" "Hapus Client (WireGuard)" "删除客户端 (WireGuard)")"
  echo " [4]  $(T "Show client QR code & config" "Tampilkan QR Code & Konfigurasi Client" "显示客户端二维码与配置")"
  echo " [5]  $(T "List clients & traffic stats" "Lihat Daftar Client & Statistik Trafik" "查看客户端列表与流量统计")"
  echo " [6]  $(T "Check server status & diagnostics (firewall/NAT/services)" "Cek Status Server & Diagnostik (Firewall/NAT/Service)" "检查服务器状态与诊断（防火墙/NAT/服务）")"
  echo "----------------------------------------------------------------"
  echo " [7]  $(T "Install / configure SSH VPN — Dropbear+Stunnel+WS (DEFAULT)" "Instal / Konfigurasi SSH VPN — Dropbear+Stunnel+WS (DEFAULT)" "安装 / 配置 SSH VPN — Dropbear+Stunnel+WS（默认）")"
  echo " [8]  $(T "Install / configure OpenVPN (SSH alternative)" "Instal / Konfigurasi OpenVPN (alternatif SSH)" "安装 / 配置 OpenVPN（SSH 的替代方案）")"
  echo " [9]  $(T "Install / configure Xray-core — VMess/VLESS/Trojan+REALITY (DEFAULT)" "Instal / Konfigurasi Xray-core — VMess/VLESS/Trojan+REALITY (DEFAULT)" "安装 / 配置 Xray-core — VMess/VLESS/Trojan+REALITY（默认）")"
  echo " [10] $(T "Install / configure v2ray-core (Xray alternative)" "Instal / Konfigurasi v2ray-core (alternatif Xray)" "安装 / 配置 v2ray-core（Xray 的替代方案）")"
  echo " [11] $(T "Install / configure Shadowsocks (optional)" "Instal / Konfigurasi Shadowsocks (Opsional)" "安装 / 配置 Shadowsocks（可选）")"
  echo " [12] $(T "Manage SSH accounts (add/remove/list)" "Kelola Akun SSH (tambah/hapus/daftar)" "管理 SSH 账号（添加/删除/列出）")"
  echo " [13] $(T "Manage Xray/V2Ray users (add/remove/list)" "Kelola User Xray/V2Ray (tambah/hapus/daftar)" "管理 Xray/V2Ray 用户（添加/删除/列出）")"
  echo " [14] $(T "Restart all VPN services" "Mulai Ulang Semua Layanan VPN" "重启所有 VPN 服务")"
  echo " [15] $(T "Uninstall / cleanly remove VPN from server" "Uninstall / Hapus Bersih VPN dari Server" "卸载 / 从服务器彻底删除 VPN")"
  echo " [16] $(T "Check IP & bandwidth limits (wrwb Store)" "Cek Limit IP & Bandwidth (wrwb Store)" "检查 IP 与带宽限制 (wrwb Store)")"
  echo " [17] $(T "Switch language (English/Indonesia/中文）" "Ganti bahasa (English/Indonesia/中文）" "切换语言 (英语/印尼语/中文）")"
  echo "----------------------------------------------------------------"
  echo " $(T "🆕 v3 Features:" "🆕 Fitur v3:" "🆕 v3 功能：")"
  echo " [18] $(T "Setup Telegram Bot (remote management)" "Setup Bot Telegram (manajemen remote)" "配置 Telegram Bot（远程管理）")"
  echo " [19] $(T "Setup Web Dashboard (browser control)" "Setup Web Dashboard (kontrol browser)" "配置 Web 控制面板（浏览器）")"
  echo " [20] $(T "Setup Auto Backup (daily backups)" "Setup Auto Backup (backup harian)" "配置自动备份（每日备份）")"
  echo " [21] $(T "Manual Backup Now" "Backup Manual Sekarang" "立即手动备份")"
  echo " [22] $(T "Install ALL v3 Features" "Instal SEMUA Fitur v3" "安装所有 v3 功能")"
  echo " [0]  $(T "Exit" "Keluar" "退出")"
  echo "================================================================"
  echo " $(T "by wrwb Store v3" "Dibuat oleh wrwb Store v3" "由 wrwb Store 打造 v3")"
}

pause() {
  echo ""
  read -rp "$(T "Press [Enter] to return to the menu..." "Tekan [Enter] untuk kembali ke menu..." "按 [Enter] 返回菜单……")" _
}

menu_switch_language() {
  echo ""
  echo "$(T "Current: " "Saat ini: " "当前：")$(lang_label)"
  echo "  1) English"
  echo "  2) Indonesia"
  echo "  3) 中文"
  local c=""
  read -rp "$(T "Choose language [1-3] (default 1): " "Pilih bahasa [1-3] (default 1): " "选择语言 [1-3]（默认 1）：")" c || true
  case "${c:-1}" in
    2) VPN_LANG="id" ;;
    3) VPN_LANG="zh" ;;
    *) VPN_LANG="en" ;;
  esac
  export VPN_LANG
  lang_save
  log_success "$(T "Language set to English." "Bahasa diatur ke Indonesia." "语言已设置为简体中文。")"
}

main_loop() {
  while true; do
    show_menu
    read -rp "$(T "Choose menu [0-22]: " "Pilih menu [0-22]: " "选择菜单 [0-22]：")" choice
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
        read -rp "$(T "Create the first SSH account now? [Y/n]: " "Buat akun SSH pertama sekarang? [Y/n]: " "现在创建首个 SSH 账号吗？[Y/n]：")" make_ssh_u
        if [[ ! "${make_ssh_u:-Y}" =~ ^[Nn]$ ]]; then
          read -rp "$(T "Username: " "Username: " "用户名：")" ssh_uname
          ssh_uname="${ssh_uname:-user1}"
          ssh_create_user "$ssh_uname" "" 30
          echo "$(T "Username: $SSH_LAST_USER | Password: $SSH_LAST_PASS | Valid until: $SSH_LAST_EXPIRE" "Username: $SSH_LAST_USER | Password: $SSH_LAST_PASS | Berlaku s/d: $SSH_LAST_EXPIRE" "用户名：$SSH_LAST_USER | 密码：$SSH_LAST_PASS | 有效期至：$SSH_LAST_EXPIRE")"
        fi
        pause
        ;;
      8)
        install_openvpn_packages
        ovpn_setup_server 1194 udp "$(get_default_iface)" "$(get_public_ip)"
        read -rp "$(T "Create the first OpenVPN client now? [y/N]: " "Buat client OpenVPN pertama sekarang? [y/N]: " "现在创建首个 OpenVPN 客户端吗？[y/N]：")" make_ovpn_c
        if [[ "$make_ovpn_c" =~ ^[Yy]$ ]]; then
          read -rp "$(T "Client name: " "Nama client: " "客户端名称：")" ovpn_name
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
        read -rp "$(T "Shadowsocks port [8388]: " "Port Shadowsocks [8388]: " "Shadowsocks 端口 [8388]：")" ss_p
        ss_p="${ss_p:-8388}"
        ss_setup_server "$ss_p" "$(gen_password 18)" "$SS_METHOD_DEFAULT" "$(get_public_ip)"
        pause
        ;;
      12)
        echo "$(T "Manage SSH accounts:" "Kelola Akun SSH:" "管理 SSH 账号：")"
        echo "  1) $(T "Add account" "Tambah akun" "添加账号")"
        echo "  2) $(T "Remove account" "Hapus akun" "删除账号")"
        echo "  3) $(T "List accounts" "Daftar akun" "列出账号")"
        read -rp "$(T "Choose [1-3]: " "Pilih [1-3]: " "选择 [1-3]：")" ssh_m
        case "$ssh_m" in
          1) "$SCRIPT_DIR/add-ssh-user.sh" ;;
          2) "$SCRIPT_DIR/remove-ssh-user.sh" ;;
          3) ssh_list_users ;;
          *) log_warn "$(T "Invalid choice." "Pilihan tidak valid." "选择无效。")" ;;
        esac
        pause
        ;;
      13)
        echo "$(T "Manage Xray/V2Ray users:" "Kelola User Xray/V2Ray:" "管理 Xray/V2Ray 用户：")"
        echo "  1) $(T "Add user" "Tambah user" "添加用户")"
        echo "  2) $(T "Remove user" "Hapus user" "删除用户")"
        echo "  3) $(T "List users" "Daftar user" "列出用户")"
        read -rp "$(T "Choose [1-3]: " "Pilih [1-3]: " "选择 [1-3]：")" xr_m
        case "$xr_m" in
          1) "$SCRIPT_DIR/add-xray-user.sh" ;;
          2) "$SCRIPT_DIR/remove-xray-user.sh" ;;
          3) xray_list_users ;;
          *) log_warn "$(T "Invalid choice." "Pilihan tidak valid." "选择无效。")" ;;
        esac
        pause
        ;;
      14)
        log_step "$(T "Restarting WireGuard service..." "Memulai ulang layanan WireGuard..." "正在重启 WireGuard 服务……")"
        systemctl restart wg-quick@wg0 2>/dev/null && log_success "$(T "WireGuard restarted." "WireGuard dimulai ulang." "WireGuard 已重启。")" || log_warn "$(T "WireGuard is not active." "WireGuard tidak aktif." "WireGuard 未激活。")"
        if systemctl list-unit-files | grep -qE "openvpn-server@|openvpn@"; then
          systemctl restart openvpn-server@server 2>/dev/null || systemctl restart openvpn@server 2>/dev/null || true
          log_success "$(T "OpenVPN restarted." "OpenVPN dimulai ulang." "OpenVPN 已重启。")"
        fi
        if systemctl list-unit-files 2>/dev/null | grep -q "shadowsocks-rust"; then
          systemctl restart shadowsocks-rust 2>/dev/null || true
          log_success "$(T "Shadowsocks restarted." "Shadowsocks dimulai ulang." "Shadowsocks 已重启。")"
        fi
        for svc in ssh dropbear ssh-ws xray; do
          if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\\.service"; then
            systemctl restart "$svc" 2>/dev/null || true
            log_success "$(T "$svc restarted." "$svc dimulai ulang." "$svc 已重启。")"
          fi
        done
        if systemctl list-unit-files 2>/dev/null | grep -q "^stunnel4\\.service"; then
          systemctl restart stunnel4 2>/dev/null || true
          log_success "$(T "stunnel4 restarted." "stunnel4 dimulai ulang." "stunnel4 已重启。")"
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
      18)
        "$SCRIPT_DIR/setup-telegram-bot.sh"
        pause
        ;;
      19)
        "$SCRIPT_DIR/setup-web-dashboard.sh"
        pause
        ;;
      20)
        "$SCRIPT_DIR/setup-auto-backup.sh"
        pause
        ;;
      21)
        "$SCRIPT_DIR/backup.sh" manual
        pause
        ;;
      22)
        "$SCRIPT_DIR/setup-all-v3.sh"
        pause
        ;;
      0)
        echo "$(T "Goodbye!" "Sampai jumpa!" "再见！")"
        exit 0
        ;;
      *)
        log_warn "$(T "Invalid choice." "Pilihan tidak valid." "选择无效。")"
        sleep 1
        ;;
    esac
  done
}

main_loop
