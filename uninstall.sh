#!/bin/bash
# ==============================================================================
#  uninstall.sh — Remove the VPN installation and clean up configs (EN/ID)
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

need_root

echo "================================================================================"
echo -e "${_C_RED}${_C_BOLD}$(T "VPN REMOVAL WARNING" "PERINGATAN PENGHAPUSAN VPN")${_C_RESET}"
echo "================================================================================"
echo "$(T "This script will:" "Skrip ini akan:")"
echo " 1. $(T "Stop and disable the WireGuard service (wg-quick@wg0)." "Menghentikan dan menonaktifkan service WireGuard (wg-quick@wg0).")"
echo " 2. $(T "Delete the server config and all WireGuard client files." "Menghapus konfigurasi server dan semua file client WireGuard.")"
echo " 3. $(T "Remove firewall rules created by these scripts." "Menghapus aturan firewall yang pernah dibuat oleh skrip ini.")"
echo " 4. $(T "Remove extra services (SSH / OpenVPN / Xray / Shadowsocks if present)." "Menghapus service tambahan (SSH / OpenVPN / Xray / Shadowsocks jika ada).")"
echo "================================================================================"

if [[ "${1:-}" != "-y" && "${1:-}" != "--yes" ]]; then
  read -rp "$(T "Are you sure you want to REMOVE THE ENTIRE VPN? [y/N]: " "Apakah Anda yakin ingin MENGHAPUS SELURUH VPN? [y/N]: ")" confirm_uninst
  [[ "$confirm_uninst" =~ ^[Yy]$ ]] || die "$(T "Removal cancelled." "Penghapusan dibatalkan.")"
fi

# 1. Stop WireGuard
if systemctl is-active --quiet wg-quick@wg0 2>/dev/null; then
  log_step "$(T "Stopping the WireGuard service..." "Menghentikan layanan WireGuard...")"
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
  log_info "$(T "Creating an emergency config backup at $backup_dir..." "Membuat backup darurat konfigurasi ke $backup_dir...")"
  cp -r /etc/wireguard "$backup_dir" || true
  rm -rf /etc/wireguard
  log_success "$(T "The /etc/wireguard directory was cleaned up." "Direktori /etc/wireguard berhasil dibersihkan.")"
fi

# 4. Stop & clean OpenVPN when present
if systemctl list-unit-files | grep -qE "openvpn-server@|openvpn@"; then
  log_step "$(T "Cleaning up OpenVPN..." "Membersihkan OpenVPN...")"
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
  log_step "$(T "Cleaning up Shadowsocks..." "Membersihkan Shadowsocks...")"
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
  log_step "$(T "Cleaning up SSH VPN..." "Membersihkan SSH VPN...")"
  if [[ -f /etc/ssh-vpn/params ]]; then
    # shellcheck disable=SC1091
    source /etc/ssh-vpn/params
    close_firewall_port "${DROPBEAR_PORT:-143}" "tcp"
    close_firewall_port "${SSL_PORT:-444}" "tcp"
    close_firewall_port "${WS_PORT:-80}" "tcp"
  fi
  for svc in dropbear stunnel4 ssh-ws; do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
  done
  rm -f /etc/systemd/system/stunnel4.service /etc/systemd/system/ssh-ws.service
  rm -f /etc/systemd/system/dropbear.service.d/override.conf
  systemctl daemon-reload
  rm -rf /etc/ssh-vpn /etc/stunnel /usr/local/bin/ssh-ws.py
  log_success "$(T "SSH VPN cleaned up (restore sshd config manually when needed)." "SSH VPN dibersihkan (konfigurasi sshd dikembalikan manual bila perlu).")"
fi

# 7. Stop & clean Xray / V2Ray when present
if [[ -d /etc/xray ]] || systemctl list-unit-files 2>/dev/null | grep -q "^xray\\.service"; then
  log_step "$(T "Cleaning up Xray/V2Ray..." "Membersihkan Xray/V2Ray...")"
  systemctl stop xray 2>/dev/null || true
  systemctl disable xray 2>/dev/null || true
  rm -f /etc/systemd/system/xray.service
  systemctl daemon-reload
  if [[ -f /etc/xray/params ]]; then
    # shellcheck disable=SC1091
    source /etc/xray/params
    for p in "${XPORT_VMESS_WS:-10001}" "${XPORT_VLESS_WS:-10002}" "${XPORT_TROJAN_WS:-10003}" "${XPORT_VLESS_XTLS:-10004}" "${XPORT_VLESS_REALITY:-443}"; do
      close_firewall_port "$p" "tcp"
    done
  fi
  rm -rf /etc/xray /usr/local/bin/xray /usr/local/share/xray
  log_success "$(T "Xray/V2Ray cleaned up." "Xray/V2Ray dibersihkan.")"
fi

# 8. Clean sysctl file when present
if [[ -f /etc/sysctl.d/99-vpn-forward.conf ]]; then
  rm -f /etc/sysctl.d/99-vpn-forward.conf
fi

# 8b. Remove the saved language preference
rm -f /etc/vpn/lang 2>/dev/null || true
rmdir /etc/vpn 2>/dev/null || true

# 9. Stop & clean the limit monitor (wrwb Store)
if systemctl list-unit-files 2>/dev/null | grep -q "^vpn-limits\\.service"; then
  log_step "$(T "Cleaning up the IP & bandwidth limit monitor..." "Membersihkan monitor limit IP & bandwidth...")"
  systemctl stop vpn-limits 2>/dev/null || true
  systemctl disable vpn-limits 2>/dev/null || true
  rm -f /etc/systemd/system/vpn-limits.service /usr/local/bin/vpn-limits-monitor.sh
  rm -rf /usr/local/share/vpn-libs /var/lib/vpn-limits
  systemctl daemon-reload 2>/dev/null || true
  log_success "$(T "Limit monitor cleaned up." "Monitor limit dibersihkan.")"
fi

log_success "$(T "VPN uninstallation complete. The system was restored to its original state." "Uninstalasi VPN selesai. Sistem telah dikembalikan ke kondisi semula.")"
echo "$(T "By wrwb Store" "Dibuat oleh wrwb Store")"
