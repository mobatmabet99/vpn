#!/bin/bash
# ==============================================================================
#  status.sh — Full VPN health check and service status (bilingual EN/ID)
#  Usage:
#    sudo ./status.sh
#  Branding: wrwb Store
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

need_root
detect_os

echo "================================================================================"
echo -e "${_C_BOLD}$(T "VPN SERVER STATUS & DIAGNOSTICS" "STATUS DAN DIAGNOSTIK SERVER VPN")${_C_RESET} ($(lang_label))"
echo "================================================================================"
echo "$(T "Operating system : $OS_NAME" "Sistem Operasi : $OS_NAME")"
echo "$(T "Kernel           : $(uname -r)" "Kernel         : $(uname -r)")"
echo "$(T "Server time      : $(date)" "Waktu Server   : $(date)")"
echo "$(T "Public IP        : $(get_public_ip 2>/dev/null || echo 'Undetected')" "IP Publik      : $(get_public_ip 2>/dev/null || echo 'Tidak terdeteksi')")"
echo "$(T "Primary iface    : $(get_default_iface 2>/dev/null || echo 'eth0')" "Interface Utama: $(get_default_iface 2>/dev/null || echo 'eth0')")"
echo "--------------------------------------------------------------------------------"

# 1. IP forwarding check
echo -n "$(T "IPv4 forwarding       : " "IPv4 Forwarding       : ")"
ipv4_fwd="$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo 0)"
if [[ "$ipv4_fwd" == "1" ]]; then
  echo -e "${_C_GREEN}[$(T "ACTIVE (1)" "AKTIF (1)")]${_C_RESET}"
else
  echo -e "${_C_RED}[$(T "INACTIVE (0)" "NONAKTIF (0)")]${_C_RESET} -> $(T "Run: sysctl -w net.ipv4.ip_forward=1" "Jalankan sysctl -w net.ipv4.ip_forward=1")"
fi

echo -n "$(T "IPv6 forwarding       : " "IPv6 Forwarding       : ")"
ipv6_fwd="$(cat /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null || echo 0)"
if [[ "$ipv6_fwd" == "1" ]]; then
  echo -e "${_C_GREEN}[$(T "ACTIVE (1)" "AKTIF (1)")]${_C_RESET}"
else
  echo -e "${_C_YELLOW}[$(T "INACTIVE / DISABLED" "NONAKTIF / DISABLED")]${_C_RESET}"
fi

# 2. TUN device
echo -n "$(T "TUN device (/dev/net/tun): " "Perangkat TUN (/dev/net/tun): ")"
if [[ -c /dev/net/tun ]]; then
  echo -e "${_C_GREEN}[$(T "AVAILABLE" "TERSEDIA")]${_C_RESET}"
else
  echo -e "${_C_RED}[$(T "NOT AVAILABLE" "TIDAK TERSEDIA")]${_C_RESET}"
fi

# 3. WireGuard service status
echo "--------------------------------------------------------------------------------"
echo -e "${_C_BOLD}$(T "WIREGUARD SERVICE:" "LAYANAN WIREGUARD:")${_C_RESET}"
if systemctl is-active --quiet wg-quick@wg0 2>/dev/null; then
  echo -e "$(T "Systemd status        : " "Status Systemd        : ")${_C_GREEN}[ACTIVE / RUNNING]${_C_RESET}"
  if command -v wg &>/dev/null; then
    echo "$(T "Interface details (wg show wg0):" "Detail Antarmuka (wg show wg0):")"
    wg show wg0 2>/dev/null || true
  fi
else
  echo -e "$(T "Systemd status        : " "Status Systemd        : ")${_C_RED}[INACTIVE / STOPPED]${_C_RESET}"
fi

# 4. Optional services (OpenVPN & Shadowsocks)
if systemctl list-unit-files | grep -qE "openvpn-server@|openvpn@"; then
  echo "--------------------------------------------------------------------------------"
  echo -e "${_C_BOLD}$(T "OPENVPN SERVICE:" "LAYANAN OPENVPN:")${_C_RESET}"
  if systemctl is-active --quiet openvpn-server@server 2>/dev/null || systemctl is-active --quiet openvpn@server 2>/dev/null; then
    echo -e "$(T "Systemd status        : " "Status Systemd        : ")${_C_GREEN}[ACTIVE / RUNNING]${_C_RESET}"
  else
    echo -e "$(T "Systemd status        : " "Status Systemd        : ")${_C_YELLOW}[INACTIVE]${_C_RESET}"
  fi
fi

if systemctl list-unit-files 2>/dev/null | grep -q "shadowsocks-rust"; then
  echo "--------------------------------------------------------------------------------"
  echo -e "${_C_BOLD}$(T "SHADOWSOCKS SERVICE:" "LAYANAN SHADOWSOCKS:")${_C_RESET}"
  if systemctl is-active --quiet shadowsocks-rust 2>/dev/null; then
    echo -e "$(T "Systemd status        : " "Status Systemd        : ")${_C_GREEN}[ACTIVE / RUNNING]${_C_RESET}"
  else
    echo -e "$(T "Systemd status        : " "Status Systemd        : ")${_C_YELLOW}[INACTIVE]${_C_RESET}"
  fi
fi

# 4b. SSH VPN service status (OpenSSH / Dropbear / Stunnel / WebSocket)
if [[ -f /etc/ssh-vpn/params ]] || systemctl list-unit-files 2>/dev/null | grep -qE "^(ssh|sshd|dropbear|stunnel4|ssh-ws)\\.service"; then
  echo "--------------------------------------------------------------------------------"
  echo -e "${_C_BOLD}$(T "SSH VPN SERVICE:" "LAYANAN SSH VPN:")${_C_RESET}"
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

# 4c. Xray / V2Ray service status (VMess/VLESS/Trojan + XTLS/REALITY)
if [[ -f /etc/xray/params ]] || systemctl list-unit-files 2>/dev/null | grep -q "^xray\\.service"; then
  echo "--------------------------------------------------------------------------------"
  echo -e "${_C_BOLD}$(T "XRAY/V2RAY SERVICE:" "LAYANAN XRAY/V2RAY:")${_C_RESET}"
  if systemctl is-active --quiet xray 2>/dev/null; then
    echo -e "$(T "Systemd status        : " "Status Systemd        : ")${_C_GREEN}[ACTIVE / RUNNING]${_C_RESET}"
    if [[ -x /usr/local/bin/xray ]]; then
      echo -e "$(T "Binary version        : $(/usr/local/bin/xray version 2>/dev/null | head -n1)" "Versi Binary          : $(/usr/local/bin/xray version 2>/dev/null | head -n1)")"
    fi
    if [[ -f /etc/xray/params ]]; then
      # shellcheck disable=SC1091
      source /etc/xray/params
      echo -e "Engine                : ${XRAY_ENGINE:-xray}"
      echo -e "$(T "VMess WS port         : ${XPORT_VMESS_WS:-10001}/tcp" "Port VMess WS         : ${XPORT_VMESS_WS:-10001}/tcp")"
      echo -e "$(T "VLESS WS port         : ${XPORT_VLESS_WS:-10002}/tcp" "Port VLESS WS         : ${XPORT_VLESS_WS:-10002}/tcp")"
      echo -e "$(T "Trojan WS port        : ${XPORT_TROJAN_WS:-10003}/tcp" "Port Trojan WS        : ${XPORT_TROJAN_WS:-10003}/tcp")"
      echo -e "$(T "VLESS XTLS port       : ${XPORT_VLESS_XTLS:-10004}/tcp" "Port VLESS XTLS       : ${XPORT_VLESS_XTLS:-10004}/tcp")"
      echo -e "$(T "VLESS REALITY port    : ${XPORT_VLESS_REALITY:-443}/tcp" "Port VLESS REALITY    : ${XPORT_VLESS_REALITY:-443}/tcp")"
    fi
  else
    echo -e "$(T "Systemd status        : " "Status Systemd        : ")${_C_YELLOW}[INACTIVE]${_C_RESET}"
  fi
fi

# 5. Firewall & NAT rules
echo "--------------------------------------------------------------------------------"
echo -e "${_C_BOLD}$(T "FIREWALL & NAT (MASQUERADE):" "FIREWALL & NAT (MASQUERADE):")${_C_RESET}"
if command -v ufw &>/dev/null; then
  echo "$(T "UFW status            : $(ufw status 2>/dev/null | grep -i "Status:" || echo "N/A")" "UFW Status            : $(ufw status 2>/dev/null | grep -i "Status:" || echo "N/A")")"
fi
if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
  echo "$(T "Firewalld masquerade  : $(firewall-cmd --query-masquerade 2>/dev/null || echo 'no')" "Firewalld Masquerade  : $(firewall-cmd --query-masquerade 2>/dev/null || echo 'no')")"
fi

echo -n "$(T "iptables MASQUERADE   : " "iptables MASQUERADE   : ")"
if iptables -t nat -S 2>/dev/null | grep -q "MASQUERADE"; then
  echo -e "${_C_GREEN}[$(T "FOUND" "DITEMUKAN")]${_C_RESET}"
else
  echo -e "${_C_YELLOW}[$(T "MISSING OR WAITING FOR INTERFACE UP" "BELUM ADA ATAU MENUNGGU INTERFACE UP")]${_C_RESET}"
fi

# 6. IP & bandwidth limits (wrwb Store)
echo "--------------------------------------------------------------------------------"
echo -e "${_C_BOLD}$(T "IP & BANDWIDTH LIMITS (wrwb Store):" "LIMIT IP & BANDWIDTH (wrwb Store):")${_C_RESET}"
if systemctl list-unit-files 2>/dev/null | grep -q "^vpn-limits\\.service"; then
  if systemctl is-active --quiet vpn-limits 2>/dev/null; then
    echo -e "$(T "Monitor service       : " "Monitor Service       : ")${_C_GREEN}[ACTIVE]${_C_RESET} ($(T "checks every 60 seconds" "cek tiap 60 detik"))"
  else
    echo -e "$(T "Monitor service       : " "Monitor Service       : ")${_C_YELLOW}[INACTIVE]${_C_RESET}"
  fi
else
  echo -e "$(T "Monitor service       : " "Monitor Service       : ")${_C_YELLOW}[$(T "NOT INSTALLED" "BELUM TERPASANG")]${_C_RESET}"
fi
if [[ -f /var/lib/vpn-limits/limits.db ]]; then
  echo "$(T "Users with limits     : $(grep -c . /var/lib/vpn-limits/limits.db 2>/dev/null || true)" "User terdaftar limit  : $(grep -c . /var/lib/vpn-limits/limits.db 2>/dev/null || true)")"
fi
if [[ -f /var/lib/vpn-limits/suspended.db && -s /var/lib/vpn-limits/suspended.db ]]; then
  echo -e "$(T "Suspended users       : " "User di-suspend       : ")${_C_RED}$(cut -d: -f1 /var/lib/vpn-limits/suspended.db | tr '\n' ' ')${_C_RESET}"
fi

echo "================================================================================"
echo " $(T "By wrwb Store" "Dibuat oleh wrwb Store")"
