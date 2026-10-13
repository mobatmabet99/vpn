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

if systemctl list-unit-files 2>/dev/null | grep -q "shadowsocks-rust"; then
  echo "--------------------------------------------------------------------------------"
  echo -e "${_C_BOLD}LAYANAN SHADOWSOCKS:${_C_RESET}"
  if systemctl is-active --quiet shadowsocks-rust 2>/dev/null; then
    echo -e "Status Systemd        : ${_C_GREEN}[ACTIVE / RUNNING]${_C_RESET}"
  else
    echo -e "Status Systemd        : ${_C_YELLOW}[INACTIVE]${_C_RESET}"
  fi
fi

# 4b. Status Layanan SSH VPN (OpenSSH / Dropbear / Stunnel / WebSocket)
if [[ -f /etc/ssh-vpn/params ]] || systemctl list-unit-files 2>/dev/null | grep -qE "^(ssh|sshd|dropbear|stunnel4|ssh-ws)\\.service"; then
  echo "--------------------------------------------------------------------------------"
  echo -e "${_C_BOLD}LAYANAN SSH VPN:${_C_RESET}"
  for svc in ssh sshd dropbear stunnel4 ssh-ws; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\\.service"; then
      if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "  ${svc} : ${_C_GREEN}[ACTIVE]${_C_RESET}"
      else
        echo -e "  ${svc} : ${_C_YELLOW}[INACTIVE]${_C_RESET}"
      fi
    fi
  done
fi

# 4c. Status Layanan Xray / V2Ray (VMess/VLESS/Trojan + XTLS/REALITY)
if [[ -f /etc/xray/params ]] || systemctl list-unit-files 2>/dev/null | grep -q "^xray\\.service"; then
  echo "--------------------------------------------------------------------------------"
  echo -e "${_C_BOLD}LAYANAN XRAY/V2RAY:${_C_RESET}"
  if systemctl is-active --quiet xray 2>/dev/null; then
    echo -e "Status Systemd        : ${_C_GREEN}[ACTIVE / RUNNING]${_C_RESET}"
    if [[ -x /usr/local/bin/xray ]]; then
      echo -e "Versi Binary          : $(/usr/local/bin/xray version 2>/dev/null | head -n1)"
    fi
    if [[ -f /etc/xray/params ]]; then
      # shellcheck disable=SC1091
      source /etc/xray/params
      echo -e "Engine                : ${XRAY_ENGINE:-xray}"
      echo -e "Port VMess WS         : ${XPORT_VMESS_WS:-10001}/tcp"
      echo -e "Port VLESS WS         : ${XPORT_VLESS_WS:-10002}/tcp"
      echo -e "Port Trojan WS        : ${XPORT_TROJAN_WS:-10003}/tcp"
      echo -e "Port VLESS XTLS       : ${XPORT_VLESS_XTLS:-10004}/tcp"
      echo -e "Port VLESS REALITY    : ${XPORT_VLESS_REALITY:-443}/tcp"
    fi
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

# 6. Limit IP & Bandwidth (wrwb Store)
echo "--------------------------------------------------------------------------------"
echo -e "${_C_BOLD}LIMIT IP & BANDWIDTH (wrwb Store):${_C_RESET}"
if systemctl list-unit-files 2>/dev/null | grep -q "^vpn-limits\\.service"; then
  if systemctl is-active --quiet vpn-limits 2>/dev/null; then
    echo -e "Monitor Service       : ${_C_GREEN}[ACTIVE]${_C_RESET} (cek tiap 60 detik)"
  else
    echo -e "Monitor Service       : ${_C_YELLOW}[INACTIVE]${_C_RESET}"
  fi
else
  echo -e "Monitor Service       : ${_C_YELLOW}[BELUM TERPASANG]${_C_RESET}"
fi
if [[ -f /var/lib/vpn-limits/limits.db ]]; then
  echo "User terdaftar limit  : $(grep -c . /var/lib/vpn-limits/limits.db 2>/dev/null || echo 0)"
fi
if [[ -f /var/lib/vpn-limits/suspended.db && -s /var/lib/vpn-limits/suspended.db ]]; then
  echo -e "User di-suspend       : ${_C_RED}$(cut -d: -f1 /var/lib/vpn-limits/suspended.db | tr '\n' ' ')${_C_RESET}"
fi

echo "================================================================================"
echo " Dibuat oleh wrwb Store"
