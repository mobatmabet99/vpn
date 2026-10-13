#!/bin/bash
# ==============================================================================
#  status.sh — Cek Kesehatan dan Status Layanan VPN Lengkap
#  Penggunaan:
#    sudo ./status.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

need_root
detect_os

echo "================================================================================"
echo -e "${_C_BOLD}STATUS DAN DIAGNOSTIK SERVER VPN${_C_RESET}"
echo "================================================================================"
echo "Sistem Operasi : $OS_NAME"
echo "Kernel         : $(uname -r)"
echo "Waktu Server   : $(date)"
echo "IP Publik      : $(get_public_ip 2>/dev/null || echo 'Tidak terdeteksi')"
echo "Interface Utama: $(get_default_iface 2>/dev/null || echo 'eth0')"
echo "--------------------------------------------------------------------------------"

# 1. IP Forwarding Check
echo -n "IPv4 Forwarding       : "
ipv4_fwd="$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo 0)"
if [[ "$ipv4_fwd" == "1" ]]; then
  echo -e "${_C_GREEN}[AKTIF (1)]${_C_RESET}"
else
  echo -e "${_C_RED}[NONAKTIF (0)]${_C_RESET} -> Jalankan sysctl -w net.ipv4.ip_forward=1"
fi

echo -n "IPv6 Forwarding       : "
ipv6_fwd="$(cat /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null || echo 0)"
if [[ "$ipv6_fwd" == "1" ]]; then
  echo -e "${_C_GREEN}[AKTIF (1)]${_C_RESET}"
else
  echo -e "${_C_YELLOW}[NONAKTIF / DISABLED]${_C_RESET}"
fi

# 2. Perangkat TUN
echo -n "Perangkat TUN (/dev/net/tun): "
if [[ -c /dev/net/tun ]]; then
  echo -e "${_C_GREEN}[TERSEDIA]${_C_RESET}"
else
  echo -e "${_C_RED}[TIDAK TERSEDIA]${_C_RESET}"
fi

# 3. Status Layanan WireGuard
echo "--------------------------------------------------------------------------------"
echo -e "${_C_BOLD}LAYANAN WIREGUARD:${_C_RESET}"
if systemctl is-active --quiet wg-quick@wg0 2>/dev/null; then
  echo -e "Status Systemd        : ${_C_GREEN}[ACTIVE / RUNNING]${_C_RESET}"
  if command -v wg &>/dev/null; then
    echo "Detail Antarmuka (wg show wg0):"
    wg show wg0 2>/dev/null || true
  fi
else
  echo -e "Status Systemd        : ${_C_RED}[INACTIVE / STOPPED]${_C_RESET}"
fi

# 4. Status Layanan Opsional (OpenVPN & Shadowsocks)
if systemctl list-unit-files | grep -qE "openvpn-server@|openvpn@"; then
  echo "--------------------------------------------------------------------------------"
  echo -e "${_C_BOLD}LAYANAN OPENVPN:${_C_RESET}"
  if systemctl is-active --quiet openvpn-server@server 2>/dev/null || systemctl is-active --quiet openvpn@server 2>/dev/null; then
    echo -e "Status Systemd        : ${_C_GREEN}[ACTIVE / RUNNING]${_C_RESET}"
  else
    echo -e "Status Systemd        : ${_C_YELLOW}[INACTIVE]${_C_RESET}"
  fi
fi

if systemctl list-unit-files | grep -q "shadowsocks-rust"; then
  echo "--------------------------------------------------------------------------------"
  echo -e "${_C_BOLD}LAYANAN SHADOWSOCKS:${_C_RESET}"
  if systemctl is-active --quiet shadowsocks-rust 2>/dev/null; then
    echo -e "Status Systemd        : ${_C_GREEN}[ACTIVE / RUNNING]${_C_RESET}"
  else
    echo -e "Status Systemd        : ${_C_YELLOW}[INACTIVE]${_C_RESET}"
  fi
fi

# 5. Aturan Firewall & NAT
echo "--------------------------------------------------------------------------------"
echo -e "${_C_BOLD}FIREWALL & NAT (MASQUERADE):${_C_RESET}"
if command -v ufw &>/dev/null; then
  echo "UFW Status            : $(ufw status 2>/dev/null | grep -i "Status:" || echo "N/A")"
fi
if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
  echo "Firewalld Masquerade  : $(firewall-cmd --query-masquerade 2>/dev/null || echo 'no')"
fi

echo -n "iptables MASQUERADE   : "
if iptables -t nat -S 2>/dev/null | grep -q "MASQUERADE"; then
  echo -e "${_C_GREEN}[DITEMUKAN]${_C_RESET}"
else
  echo -e "${_C_YELLOW}[BELUM ADA ATAU MENUNGGU INTERFACE UP]${_C_RESET}"
fi

echo "================================================================================"
