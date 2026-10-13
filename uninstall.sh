#!/bin/bash
# ==============================================================================
#  uninstall.sh — Menghapus Instalasi VPN dan Membersihkan Konfigurasi
#  Penggunaan:
#    sudo ./uninstall.sh [--yes]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/system.sh
source "$SCRIPT_DIR/lib/system.sh"

need_root

echo "================================================================================"
echo -e "${_C_RED}${_C_BOLD}PERINGATAN PENGHAPUSAN VPN${_C_RESET}"
echo "================================================================================"
echo "Skrip ini akan:"
echo " 1. Menghentikan dan menonaktifkan service WireGuard (wg-quick@wg0)."
echo " 2. Menghapus konfigurasi server dan semua file client WireGuard."
echo " 3. Menghapus aturan firewall yang pernah dibuat oleh skrip ini."
echo " 4. Menghapus service tambahan (OpenVPN / Shadowsocks jika ada)."
echo "================================================================================"

if [[ "${1:-}" != "-y" && "${1:-}" != "--yes" ]]; then
  read -rp "Apakah Anda yakin ingin MENGHAPUS SELURUH VPN? [y/N]: " confirm_uninst
  [[ "$confirm_uninst" =~ ^[Yy]$ ]] || die "Penghapusan dibatalkan."
fi

# 1. Hentikan WireGuard
if systemctl is-active --quiet wg-quick@wg0 2>/dev/null; then
  log_step "Menghentikan layanan WireGuard..."
  systemctl stop wg-quick@wg0 2>/dev/null || true
fi
systemctl disable wg-quick@wg0 2>/dev/null || true

# 2. Hapus port firewall jika params ada
if [[ -f /etc/wireguard/params ]]; then
  # shellcheck disable=SC1091
  source /etc/wireguard/params
  if [[ -n "${SERVER_PORT:-}" ]]; then
    close_firewall_port "$SERVER_PORT" "udp"
  fi
fi

# 3. Bersihkan direktori WireGuard
if [[ -d /etc/wireguard ]]; then
  backup_dir="/root/wireguard_backup_$(date +%Y%m%d%H%M%S)"
  log_info "Membuat backup darurat konfigurasi ke $backup_dir..."
  cp -r /etc/wireguard "$backup_dir" || true
  rm -rf /etc/wireguard
  log_success "Direktori /etc/wireguard berhasil dibersihkan."
fi

# 4. Hentikan & bersihkan OpenVPN jika ada
if systemctl list-unit-files | grep -qE "openvpn-server@|openvpn@"; then
  log_step "Membersihkan OpenVPN..."
  systemctl stop openvpn-server@server 2>/dev/null || systemctl stop openvpn@server 2>/dev/null || true
  systemctl disable openvpn-server@server 2>/dev/null || systemctl disable openvpn@server 2>/dev/null || true
  if [[ -f /etc/openvpn/params ]]; then
    # shellcheck disable=SC1091
    source /etc/openvpn/params
    close_firewall_port "${OVPN_PORT:-1194}" "${OVPN_PROTO:-udp}"
  fi
  rm -rf /etc/openvpn
fi

# 5. Hentikan & bersihkan Shadowsocks jika ada
if systemctl list-unit-files | grep -q "shadowsocks-rust"; then
  log_step "Membersihkan Shadowsocks..."
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

# 6. Bersihkan file sysctl jika ada
if [[ -f /etc/sysctl.d/99-vpn-forward.conf ]]; then
  rm -f /etc/sysctl.d/99-vpn-forward.conf
fi

log_success "Uninstalasi VPN selesai. Sistem telah dikembalikan ke kondisi semula."
