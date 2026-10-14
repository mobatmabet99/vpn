#!/bin/bash
# ==============================================================================
#  uninstall.sh — Remove the VPN installation and clean up configs (EN/ID/ZH)
#  Usage:
#    sudo ./uninstall.sh [--yes]
#  Branding: wrwb Store
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/system.sh
source "$SCRIPT_DIR/lib/system.sh"
# shellcheck source=lib/ssl.sh
source "$SCRIPT_DIR/lib/ssl.sh"

install_cleanup_trap
need_root

echo "================================================================================"
echo -e "${_C_RED}${_C_BOLD}$(T "VPN REMOVAL WARNING" "PERINGATAN PENGHAPUSAN VPN" "VPN 卸载警告")${_C_RESET}"
echo "================================================================================"
echo "$(T "This script will:" "Skrip ini akan:" "此脚本将执行：")"
echo " 1. $(T "Stop and disable the WireGuard service (wg-quick@wg0)." "Menghentikan dan menonaktifkan service WireGuard (wg-quick@wg0)." "停止并禁用 WireGuard 服务 (wg-quick@wg0)。")"
echo " 2. $(T "Delete the server config and all WireGuard client files." "Menghapus konfigurasi server dan semua file client WireGuard." "删除服务器配置及所有 WireGuard 客户端文件。")"
echo " 3. $(T "Remove firewall rules created by these scripts." "Menghapus aturan firewall yang pernah dibuat oleh skrip ini." "删除这些脚本创建的防火墙规则。")"
echo " 4. $(T "Remove extra services (SSH / OpenVPN / Xray / Shadowsocks if present)." "Menghapus service tambahan (SSH / OpenVPN / Xray / Shadowsocks jika ada)." "删除附加服务（SSH / OpenVPN / Xray / Shadowsocks，如有）。")"
echo "================================================================================"

if [[ "${1:-}" != "-y" && "${1:-}" != "--yes" ]]; then
  read -rp "$(T "Are you sure you want to REMOVE THE ENTIRE VPN? [y/N]: " "Apakah Anda yakin ingin MENGHAPUS SELURUH VPN? [y/N]: " "确定要删除整个 VPN 吗？[y/N]：")" confirm_uninst
  [[ "$confirm_uninst" =~ ^[Yy]$ ]] || die "$(T "Removal cancelled." "Penghapusan dibatalkan." "删除已取消。")"
fi

# 1. Stop WireGuard
if systemctl is-active --quiet wg-quick@wg0 2>/dev/null; then
  log_step "$(T "Stopping the WireGuard service..." "Menghentikan layanan WireGuard..." "正在停止 WireGuard 服务……")"
  systemctl stop wg-quick@wg0 2>/dev/null || true
fi
systemctl disable wg-quick@wg0 2>/dev/null || true

# 2. Remove firewall port when params exist
if [[ -f /etc/wireguard/params ]]; then
  # shellcheck disable=SC1091
  source /etc/wireguard/params
  if [[ -n "${SERVER_PORT:-}" ]]; then
    close_firewall_port "$SERVER_PORT" "udp"
  fi
fi

# 3. Clean up the WireGuard directory
if [[ -d /etc/wireguard ]]; then
  backup_dir="/root/wireguard_backup_$(date +%Y%m%d%H%M%S)"
  log_info "$(T "Creating an emergency config backup at $backup_dir..." "Membuat backup darurat konfigurasi ke $backup_dir..." "正在将应急配置备份到 $backup_dir……")"
  cp -r /etc/wireguard "$backup_dir" || true
  rm -rf /etc/wireguard
  log_success "$(T "The /etc/wireguard directory was cleaned up." "Direktori /etc/wireguard berhasil dibersihkan." "/etc/wireguard 目录已清理。")"
fi

# 4. Stop & clean OpenVPN when present
if systemctl list-unit-files | grep -qE "openvpn-server@|openvpn@"; then
  log_step "$(T "Cleaning up OpenVPN..." "Membersihkan OpenVPN..." "正在清理 OpenVPN……")"
  systemctl stop openvpn-server@server 2>/dev/null || systemctl stop openvpn@server 2>/dev/null || true
  systemctl disable openvpn-server@server 2>/dev/null || systemctl disable openvpn@server 2>/dev/null || true
  if [[ -f /etc/openvpn/params ]]; then
    # shellcheck disable=SC1091
    source /etc/openvpn/params
    close_firewall_port "${OVPN_PORT:-1194}" "${OVPN_PROTO:-udp}"
  fi
  rm -rf /etc/openvpn
fi

# 5. Stop & clean Shadowsocks when present
if systemctl list-unit-files 2>/dev/null | grep -q "shadowsocks-rust"; then
  log_step "$(T "Cleaning up Shadowsocks..." "Membersihkan Shadowsocks..." "正在清理 Shadowsocks……")"
  systemctl stop shadowsocks-rust 2>/dev/null || true
  systemctl disable shadowsocks-rust 2>/dev/null || true
  rm -f /etc/systemd/system/shadowsocks-rust.service
  systemctl daemon-reload
  if [[ -f /etc/shadowsocks/params ]]; then
    # shellcheck disable=SC1091
    source /etc/shadowsocks/params
    close_firewall_port "${SS_PORT:-8388}" "tcp"
    close_firewall_port "${SS_PORT:-8388}" "udp"
  fi
  rm -rf /etc/shadowsocks /usr/local/bin/ssserver
fi

# 6. Stop & clean SSH VPN when present
if [[ -d /etc/ssh-vpn ]] || systemctl list-unit-files 2>/dev/null | grep -qE "^(dropbear|stunnel4|ssh-ws)\\.service"; then
  log_step "$(T "Cleaning up SSH VPN..." "Membersihkan SSH VPN..." "正在清理 SSH VPN……")"
  if [[ -f /etc/ssh-vpn/params ]]; then
    # shellcheck disable=SC1091
    source /etc/ssh-vpn/params
    close_firewall_ports "tcp" "${DROPBEAR_PORT:-143}" "${SSL_PORT:-444}" "${SSH_PORT:-22}" "${WS_PORT:-8080}"
  fi
  for svc in dropbear stunnel4 ssh-ws; do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
  done
  rm -f /etc/systemd/system/stunnel4.service /etc/systemd/system/ssh-ws.service
  rm -f /etc/systemd/system/dropbear.service.d/override.conf
  systemctl daemon-reload
  rm -rf /etc/ssh-vpn /etc/stunnel /usr/local/bin/ssh-ws.py
  log_success "$(T "SSH VPN cleaned up (restore sshd config manually when needed)." "SSH VPN dibersihkan (konfigurasi sshd dikembalikan manual bila perlu)." "SSH VPN 已清理（需要时请手动恢复 sshd 配置）。")"
fi

# 7. Stop & clean Xray / V2Ray when present
if [[ -d /etc/xray ]] || systemctl list-unit-files 2>/dev/null | grep -q "^xray\\.service"; then
  log_step "$(T "Cleaning up Xray/V2Ray..." "Membersihkan Xray/V2Ray..." "正在清理 Xray/V2Ray……")"
  systemctl stop xray 2>/dev/null || true
  systemctl disable xray 2>/dev/null || true
  rm -f /etc/systemd/system/xray.service
  systemctl daemon-reload
  if [[ -f /etc/xray/params ]]; then
    # shellcheck disable=SC1091
    source /etc/xray/params
    close_firewall_ports "tcp" "${XPORT_VMESS_WS:-10001}" "${XPORT_VLESS_WS:-10002}" "${XPORT_TROJAN_WS:-10003}" "${XPORT_VLESS_XTLS:-10004}" "${XPORT_VLESS_REALITY:-443}" "${XPORT_VMESS_GRPC:-10005}" "${XPORT_VLESS_GRPC:-10006}" "${XPORT_TROJAN_GRPC:-10007}" "${XPORT_VLESS_REALITY_GRPC:-10008}" "${XPORT_XHTTP_SHARED:-80}"
  fi
  rm -rf /etc/xray /usr/local/bin/xray /usr/local/share/xray
  log_success "$(T "Xray/V2Ray cleaned up." "Xray/V2Ray dibersihkan." "Xray/V2Ray 已清理。")"
fi

# 8. Clean sysctl file when present
if [[ -f /etc/sysctl.d/99-vpn-forward.conf ]]; then
  rm -f /etc/sysctl.d/99-vpn-forward.conf
fi

# 8b. Remove the saved language preference
rm -f /etc/vpn/lang 2>/dev/null || true
rmdir /etc/vpn 2>/dev/null || true

# 8c. Remove the saved account summary (v4.9, contains secrets)
if [[ -f /etc/vpn-script/client-config.txt || -d /etc/vpn-script ]]; then
  log_step "$(T "Cleaning up the saved account summary..." "Membersihkan ringkasan akun tersimpan..." "正在清理已保存账户摘要...")"
  rm -rf /etc/vpn-script
  log_success "$(T "Saved account summary removed." "Ringkasan akun tersimpan dihapus." "已保存账户摘要已删除。")"
fi

# 9. Stop & clean the limit monitor (wrwb Store)
if systemctl list-unit-files 2>/dev/null | grep -q "^vpn-limits\\.service"; then
  log_step "$(T "Cleaning up the IP & bandwidth limit monitor..." "Membersihkan monitor limit IP & bandwidth..." "正在清理 IP 与带宽限制监控……")"
  systemctl stop vpn-limits 2>/dev/null || true
  systemctl disable vpn-limits 2>/dev/null || true
  rm -f /etc/systemd/system/vpn-limits.service /usr/local/bin/vpn-limits-monitor.sh
  rm -rf /usr/local/share/vpn-libs /var/lib/vpn-limits
  systemctl daemon-reload 2>/dev/null || true
  log_success "$(T "Limit monitor cleaned up." "Monitor limit dibersihkan." "限制监控已清理。")"
fi

# 8c. Clean SSL certificates (acme.sh, v4.7)
if [[ -d /etc/vpn-ssl || -x /root/.acme.sh/acme.sh ]]; then
  log_step "$(T "Cleaning up SSL certificates..." "Membersihkan sertifikat SSL..." "正在清理 SSL 证书...")"
  ssl_remove || true
  log_success "$(T "SSL cleaned up." "SSL dibersihkan." "SSL 已清理。")"
fi
log_success "$(T "VPN uninstallation complete. The system was restored to its original state." "Uninstalasi VPN selesai. Sistem telah dikembalikan ke kondisi semula." "VPN 卸载完成，系统已恢复到初始状态。")"
echo "$(T "By wrwb Store" "Dibuat oleh wrwb Store" "由 wrwb Store 打造")"
