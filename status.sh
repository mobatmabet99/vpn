#!/bin/bash
# ==============================================================================
#  status.sh — Full VPN health check and service status (trilingual EN/ID/ZH)
#  Usage:
#    sudo ./status.sh
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

need_root
detect_os

echo "================================================================================"
echo -e "${_C_BOLD}$(T "VPN SERVER STATUS & DIAGNOSTICS" "STATUS DAN DIAGNOSTIK SERVER VPN" "VPN 服务器状态与诊断")${_C_RESET} ($(lang_label))"
echo "================================================================================"
echo "$(T "Operating system : $OS_NAME" "Sistem Operasi : $OS_NAME" "操作系统     : $OS_NAME")"
echo "$(T "Kernel           : $(uname -r)" "Kernel         : $(uname -r)" "内核           : $(uname -r)")"
echo "$(T "Server time      : $(date)" "Waktu Server   : $(date)" "服务器时间     : $(date)")"
echo "$(T "Public IP        : $(get_public_ip 2>/dev/null || echo 'Undetected')" "IP Publik      : $(get_public_ip 2>/dev/null || echo 'Tidak terdeteksi')" "公网 IP        : $(get_public_ip 2>/dev/null || echo '未检测到')")"
echo "$(T "Primary iface    : $(get_default_iface 2>/dev/null || echo 'eth0')" "Interface Utama: $(get_default_iface 2>/dev/null || echo 'eth0')" "主网卡         : $(get_default_iface 2>/dev/null || echo 'eth0')")"
echo "--------------------------------------------------------------------------------"

# 1. IP forwarding check
echo -n "$(T "IPv4 forwarding       : " "IPv4 Forwarding       : " "IPv4 转发             : ")"
ipv4_fwd="$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo 0)"
if [[ "$ipv4_fwd" == "1" ]]; then
  echo -e "${_C_GREEN}[$(T "ACTIVE (1)" "AKTIF (1)" "运行中 (1)")]${_C_RESET}"
else
  echo -e "${_C_RED}[$(T "INACTIVE (0)" "NONAKTIF (0)" "未运行 (0)")]${_C_RESET} -> $(T "Run: sysctl -w net.ipv4.ip_forward=1" "Jalankan sysctl -w net.ipv4.ip_forward=1" "运行：sysctl -w net.ipv4.ip_forward=1")"
fi

echo -n "$(T "IPv6 forwarding       : " "IPv6 Forwarding       : " "IPv6 转发             : ")"
ipv6_fwd="$(cat /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null || echo 0)"
if [[ "$ipv6_fwd" == "1" ]]; then
  echo -e "${_C_GREEN}[$(T "ACTIVE (1)" "AKTIF (1)" "运行中 (1)")]${_C_RESET}"
else
  echo -e "${_C_YELLOW}[$(T "INACTIVE / DISABLED" "NONAKTIF / DISABLED" "未运行 / 已禁用")]${_C_RESET}"
fi

# 2. TUN device
echo -n "$(T "TUN device (/dev/net/tun): " "Perangkat TUN (/dev/net/tun): " "TUN 设备 (/dev/net/tun)：")"
if [[ -c /dev/net/tun ]]; then
  echo -e "${_C_GREEN}[$(T "AVAILABLE" "TERSEDIA" "可用")]${_C_RESET}"
else
  echo -e "${_C_RED}[$(T "NOT AVAILABLE" "TIDAK TERSEDIA" "不可用")]${_C_RESET}"
fi

# 3. WireGuard service status
echo "--------------------------------------------------------------------------------"
echo -e "${_C_BOLD}$(T "WIREGUARD SERVICE:" "LAYANAN WIREGUARD:" "WIREGUARD 服务：")${_C_RESET}"
if systemctl is-active --quiet wg-quick@wg0 2>/dev/null; then
  echo -e "$(T "Systemd status        : " "Status Systemd        : " "Systemd 状态          : ")${_C_GREEN}[ACTIVE / RUNNING]${_C_RESET} ($(T "enabled: $(systemctl is-enabled wg-quick@wg0 2>/dev/null || echo '?') — auto-start on boot" "enabled: $(systemctl is-enabled wg-quick@wg0 2>/dev/null || echo '?') — auto-start saat boot" "enabled：$(systemctl is-enabled wg-quick@wg0 2>/dev/null || echo '?') — 开机自启"))"
  if command -v wg &>/dev/null; then
    echo "$(T "Interface details (wg show wg0):" "Detail Antarmuka (wg show wg0):" "接口详情 (wg show wg0)：")"
    wg show wg0 2>/dev/null || true
  fi
else
  echo -e "$(T "Systemd status        : " "Status Systemd        : " "Systemd 状态          : ")${_C_RED}[INACTIVE / STOPPED]${_C_RESET} ($(T "enabled: $(systemctl is-enabled wg-quick@wg0 2>/dev/null || echo '?')" "enabled: $(systemctl is-enabled wg-quick@wg0 2>/dev/null || echo '?')" "enabled：$(systemctl is-enabled wg-quick@wg0 2>/dev/null || echo '?')"))"
fi

# 4. Optional services (OpenVPN & Shadowsocks)
if systemctl list-unit-files | grep -qE "openvpn-server@|openvpn@"; then
  echo "--------------------------------------------------------------------------------"
  echo -e "${_C_BOLD}$(T "OPENVPN SERVICE:" "LAYANAN OPENVPN:" "OPENVPN 服务：")${_C_RESET}"
  if systemctl is-active --quiet openvpn-server@server 2>/dev/null || systemctl is-active --quiet openvpn@server 2>/dev/null; then
    echo -e "$(T "Systemd status        : " "Status Systemd        : " "Systemd 状态          : ")${_C_GREEN}[ACTIVE / RUNNING]${_C_RESET}"
  else
    echo -e "$(T "Systemd status        : " "Status Systemd        : " "Systemd 状态          : ")${_C_YELLOW}[INACTIVE]${_C_RESET}"
  fi
  if systemctl is-enabled --quiet openvpn-server@server 2>/dev/null || systemctl is-enabled --quiet openvpn@server 2>/dev/null; then
    echo -e "$(T "Auto-start on boot    : " "Auto-start saat boot  : " "开机自启              : ")${_C_GREEN}[ENABLED]${_C_RESET}"
  else
    echo -e "$(T "Auto-start on boot    : " "Auto-start saat boot  : " "开机自启              : ")${_C_YELLOW}[DISABLED]${_C_RESET}"
  fi
fi

if systemctl list-unit-files 2>/dev/null | grep -q "shadowsocks-rust"; then
  echo "--------------------------------------------------------------------------------"
  echo -e "${_C_BOLD}$(T "SHADOWSOCKS SERVICE:" "LAYANAN SHADOWSOCKS:" "SHADOWSOCKS 服务：")${_C_RESET}"
  if systemctl is-active --quiet shadowsocks-rust 2>/dev/null; then
    echo -e "$(T "Systemd status        : " "Status Systemd        : " "Systemd 状态          : ")${_C_GREEN}[ACTIVE / RUNNING]${_C_RESET}"
  else
    echo -e "$(T "Systemd status        : " "Status Systemd        : " "Systemd 状态          : ")${_C_YELLOW}[INACTIVE]${_C_RESET}"
  fi
  if systemctl is-enabled --quiet shadowsocks-rust 2>/dev/null; then
    echo -e "$(T "Auto-start on boot    : " "Auto-start saat boot  : " "开机自启              : ")${_C_GREEN}[ENABLED]${_C_RESET}"
  else
    echo -e "$(T "Auto-start on boot    : " "Auto-start saat boot  : " "开机自启              : ")${_C_YELLOW}[DISABLED]${_C_RESET}"
  fi
fi

# 4b. SSH VPN service status (OpenSSH / Dropbear / Stunnel / WebSocket)
if [[ -f /etc/ssh-vpn/params ]] || systemctl list-unit-files 2>/dev/null | grep -qE "^(ssh|sshd|dropbear|stunnel4|ssh-ws)\\.service"; then
  echo "--------------------------------------------------------------------------------"
  echo -e "${_C_BOLD}$(T "SSH VPN SERVICE:" "LAYANAN SSH VPN:" "SSH VPN 服务：")${_C_RESET}"
  for svc in ssh sshd dropbear stunnel4 ssh-ws; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\\.service"; then
      _en="$(systemctl is-enabled "$svc" 2>/dev/null || echo '?')"
      if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "  ${svc} : ${_C_GREEN}[ACTIVE]${_C_RESET} (enabled: $_en)"
      else
        echo -e "  ${svc} : ${_C_YELLOW}[INACTIVE]${_C_RESET} (enabled: $_en)"
      fi
    fi
  done
fi

# 4c. Xray / V2Ray service status (VMess/VLESS/Trojan + XTLS/REALITY)
# v5: engine-aware config test (xray `run -test`, v2ray `test -c`).
if [[ -f /etc/xray/params ]] || systemctl list-unit-files 2>/dev/null | grep -q "^xray\\.service"; then
  echo "--------------------------------------------------------------------------------"
  echo -e "${_C_BOLD}$(T "XRAY/V2RAY SERVICE:" "LAYANAN XRAY/V2RAY:" "XRAY/V2RAY 服务：")${_C_RESET}"
  if systemctl is-active --quiet xray 2>/dev/null; then
    echo -e "$(T "Systemd status        : " "Status Systemd        : " "Systemd 状态          : ")${_C_GREEN}[ACTIVE / RUNNING]${_C_RESET} ($(T "enabled: $(systemctl is-enabled xray 2>/dev/null || echo '?') — auto-start on boot" "enabled: $(systemctl is-enabled xray 2>/dev/null || echo '?') — auto-start saat boot" "enabled：$(systemctl is-enabled xray 2>/dev/null || echo '?') — 开机自启"))"
    if [[ -x /usr/local/bin/xray ]]; then
      _xray_eng="xray"
      [[ -f /etc/xray/params ]] && { # shellcheck disable=SC1091
        source /etc/xray/params 2>/dev/null || true; _xray_eng="${XRAY_ENGINE:-xray}"; }
      if [[ "$_xray_eng" == "v2ray" ]]; then
        echo -e "$(T "Config test           : $(/usr/local/bin/xray test -c /etc/xray/config.json >/dev/null 2>&1 && echo 'OK' || echo 'FAIL')" "Tes konfigurasi       : $(/usr/local/bin/xray test -c /etc/xray/config.json >/dev/null 2>&1 && echo 'OK' || echo 'GAGAL')" "配置测试              : $(/usr/local/bin/xray test -c /etc/xray/config.json >/dev/null 2>&1 && echo 'OK' || echo '失败')")"
      else
        echo -e "$(T "Config test           : $(/usr/local/bin/xray run -test -config /etc/xray/config.json >/dev/null 2>&1 && echo 'OK' || echo 'FAIL')" "Tes konfigurasi       : $(/usr/local/bin/xray run -test -config /etc/xray/config.json >/dev/null 2>&1 && echo 'OK' || echo 'GAGAL')" "配置测试              : $(/usr/local/bin/xray run -test -config /etc/xray/config.json >/dev/null 2>&1 && echo 'OK' || echo '失败')")"
      fi
      echo -e "$(T "Binary version        : $(/usr/local/bin/xray version 2>/dev/null | head -n1)" "Versi Binary          : $(/usr/local/bin/xray version 2>/dev/null | head -n1)" "程序版本              : $(/usr/local/bin/xray version 2>/dev/null | head -n1)")"
    fi
    if [[ -f /etc/xray/params ]]; then
      # shellcheck disable=SC1091
      source /etc/xray/params
      echo -e "Engine                : ${XRAY_ENGINE:-xray}"
      echo -e "$(T "VMess WS port         : ${XPORT_VMESS_WS:-10001}/tcp" "Port VMess WS         : ${XPORT_VMESS_WS:-10001}/tcp" "VMess WS 端口         : ${XPORT_VMESS_WS:-10001}/tcp")"
      echo -e "$(T "VLESS WS port         : ${XPORT_VLESS_WS:-10002}/tcp" "Port VLESS WS         : ${XPORT_VLESS_WS:-10002}/tcp" "VLESS WS 端口         : ${XPORT_VLESS_WS:-10002}/tcp")"
      echo -e "$(T "Trojan WS port        : ${XPORT_TROJAN_WS:-10003}/tcp" "Port Trojan WS        : ${XPORT_TROJAN_WS:-10003}/tcp" "Trojan WS 端口        : ${XPORT_TROJAN_WS:-10003}/tcp")"
      if [[ "${XRAY_ENGINE:-xray}" == "v2ray" ]]; then
        echo -e "$(T "VLESS TCP port        : ${XPORT_VLESS_XTLS:-10004}/tcp (plain, no XTLS-Vision)" "Port VLESS TCP        : ${XPORT_VLESS_XTLS:-10004}/tcp (plain, tanpa XTLS-Vision)" "VLESS TCP 端口        : ${XPORT_VLESS_XTLS:-10004}/tcp（明文，无 XTLS-Vision）")"
        echo -e "$(T "Inbounds              : 7 (WS + gRPC + TCP, no REALITY/XHTTP)" "Inbound               : 7 (WS + gRPC + TCP, tanpa REALITY/XHTTP)" "入站                  : 7（WS + gRPC + TCP，无 REALITY/XHTTP）")"
      else
        echo -e "$(T "VLESS XTLS port       : ${XPORT_VLESS_XTLS:-10004}/tcp" "Port VLESS XTLS       : ${XPORT_VLESS_XTLS:-10004}/tcp" "VLESS XTLS 端口       : ${XPORT_VLESS_XTLS:-10004}/tcp")"
        echo -e "$(T "VLESS REALITY port    : ${XPORT_VLESS_REALITY:-443}/tcp" "Port VLESS REALITY    : ${XPORT_VLESS_REALITY:-443}/tcp" "VLESS REALITY 端口    : ${XPORT_VLESS_REALITY:-443}/tcp")"
      fi
    fi
  else
    echo -e "$(T "Systemd status        : " "Status Systemd        : " "Systemd 状态          : ")${_C_YELLOW}[INACTIVE]${_C_RESET}"
  fi
fi

# 4d. v5 edge: Nginx WS gateway + wstunnel + AmneziaWG health
if [[ -f /etc/vpn-script/edge-params || -f /etc/nginx/conf.d/vpn-ws-gateway.conf || -f /etc/nginx/http.d/vpn-ws-gateway.conf ]] || systemctl list-unit-files 2>/dev/null | grep -qE "^(nginx|wstunnel)\\.service"; then
  echo "--------------------------------------------------------------------------------"
  echo -e "${_C_BOLD}$(T "WS GATEWAY v5 (Nginx edge + tunnels):" "GATEWAY WS v5 (Nginx edge + tunnel):" "v5 WS 网关 (Nginx 边缘 + 隧道)：")${_C_RESET}"
  for svc in nginx wstunnel; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\\.service"; then
      _en="$(systemctl is-enabled "$svc" 2>/dev/null || echo '?')"
      if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "  ${svc} : ${_C_GREEN}[ACTIVE]${_C_RESET} (enabled: $_en)"
      else
        echo -e "  ${svc} : ${_C_YELLOW}[INACTIVE]${_C_RESET} (enabled: $_en)"
      fi
    fi
  done
  if command -v nginx &>/dev/null; then
    echo -e "$(T "Nginx config test      : $(nginx -t >/dev/null 2>&1 && echo 'OK' || echo 'FAIL')" "Tes konfigurasi Nginx   : $(nginx -t >/dev/null 2>&1 && echo 'OK' || echo 'GAGAL')" "Nginx 配置测试        : $(nginx -t >/dev/null 2>&1 && echo 'OK' || echo '失败')")"
  fi
  if [[ -f /etc/vpn-script/edge-params ]]; then
    # shellcheck disable=SC1091
    source /etc/vpn-script/edge-params
    echo -e "$(T "Gateway plain ports   : ${EDGE_PORT_PLAIN:-80}/tcp + ${EDGE_PORT_ALT:-8080}/tcp" "Port plain gateway    : ${EDGE_PORT_PLAIN:-80}/tcp + ${EDGE_PORT_ALT:-8080}/tcp" "网关明文端口         : ${EDGE_PORT_PLAIN:-80}/tcp + ${EDGE_PORT_ALT:-8080}/tcp")"
    echo -e "$(T "Gateway TLS port      : ${EDGE_PORT_TLS:-8443}/tcp (+ 443 via REALITY fallback)" "Port TLS gateway      : ${EDGE_PORT_TLS:-8443}/tcp (+ 443 via fallback REALITY)" "网关 TLS 端口         : ${EDGE_PORT_TLS:-8443}/tcp（+ 经 REALITY 回退的 443）")"
  fi
  for svc in "awg-quick@awg0" "awg0"; do
    # FIXED-PATTERN grep (-F): '@'/'$svc' contains chars ('@' is literal, but
    # the param expansion already doubles '\' oddly). -F avoids regex vs shell
    # escaping mismatches (status.sh used a different mangled pattern than
    # menu.sh — both now use one identical -F string).
    if systemctl cat "$svc" &>/dev/null || systemctl list-unit-files 2>/dev/null | grep -qF "${svc}.service"; then
      _en="$(systemctl is-enabled "$svc" 2>/dev/null || echo '?')"
      if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "  ${svc} : ${_C_GREEN}[ACTIVE]${_C_RESET} (enabled: $_en)"
      else
        echo -e "  ${svc} : ${_C_YELLOW}[INACTIVE]${_C_RESET} (enabled: $_en)"
      fi
    fi
  done
  if [[ -f /etc/amneziawg/params ]]; then
    # shellcheck disable=SC1091
    source /etc/amneziawg/params 2>/dev/null || true
    echo -e "$(T "AmneziaWG endpoint    : ${AWG_PUB_IP:-?}:${AWG_PORT:-51821}/udp (awg0)" "Endpoint AmneziaWG    : ${AWG_PUB_IP:-?}:${AWG_PORT:-51821}/udp (awg0)" "AmneziaWG 端点        : ${AWG_PUB_IP:-?}:${AWG_PORT:-51821}/udp (awg0)")"
  fi
fi

# 5. Firewall & NAT rules (dynamic backend, v4.6)
echo "--------------------------------------------------------------------------------"
echo -e "${_C_BOLD}$(T "FIREWALL & NAT (MASQUERADE):" "FIREWALL & NAT (MASQUERADE):" "防火墙与 NAT (MASQUERADE)：")${_C_RESET}"
fw_status_summary
if command -v ufw &>/dev/null; then
  echo "$(T "UFW status            : $(ufw status 2>/dev/null | grep -i "Status:" || echo "N/A")" "UFW Status            : $(ufw status 2>/dev/null | grep -i "Status:" || echo "N/A")" "UFW 状态              : $(ufw status 2>/dev/null | grep -i "Status:" || echo "N/A")")"
fi
if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
  echo "$(T "Firewalld masquerade  : $(firewall-cmd --query-masquerade 2>/dev/null || echo 'no')" "Firewalld Masquerade  : $(firewall-cmd --query-masquerade 2>/dev/null || echo 'no')" "Firewalld 伪装       : $(firewall-cmd --query-masquerade 2>/dev/null || echo 'no')")"
fi

echo -n "$(T "iptables MASQUERADE   : " "iptables MASQUERADE   : " "iptables 伪装         : ")"
if iptables -t nat -S 2>/dev/null | grep -q "MASQUERADE"; then
  echo -e "${_C_GREEN}[$(T "FOUND" "DITEMUKAN" "已找到")]${_C_RESET}"
else
  echo -e "${_C_YELLOW}[$(T "MISSING OR WAITING FOR INTERFACE UP" "BELUM ADA ATAU MENUNGGU INTERFACE UP" "缺失或等待网卡启动")]${_C_RESET}"
fi

# 6. IP & bandwidth limits (wrwb Store)
echo "--------------------------------------------------------------------------------"
echo -e "${_C_BOLD}$(T "IP & BANDWIDTH LIMITS (wrwb Store):" "LIMIT IP & BANDWIDTH (wrwb Store):" "IP 与带宽限制 (wrwb Store)：")${_C_RESET}"
if systemctl list-unit-files 2>/dev/null | grep -q "^vpn-limits\\.service"; then
  if systemctl is-active --quiet vpn-limits 2>/dev/null; then
    echo -e "$(T "Monitor service       : " "Monitor Service       : " "监控服务              : ")${_C_GREEN}[ACTIVE]${_C_RESET} ($(T "checks every 60 seconds" "cek tiap 60 detik" "每 60 秒检查一次"))"
  else
    echo -e "$(T "Monitor service       : " "Monitor Service       : " "监控服务              : ")${_C_YELLOW}[INACTIVE]${_C_RESET}"
  fi
else
  echo -e "$(T "Monitor service       : " "Monitor Service       : " "监控服务              : ")${_C_YELLOW}[$(T "NOT INSTALLED" "BELUM TERPASANG" "尚未安装")]${_C_RESET}"
fi
if [[ -f /var/lib/vpn-limits/limits.db ]]; then
  echo "$(T "Users with limits     : $(grep -c . /var/lib/vpn-limits/limits.db 2>/dev/null || true)" "User terdaftar limit  : $(grep -c . /var/lib/vpn-limits/limits.db 2>/dev/null || true)" "受限用户数           : $(grep -c . /var/lib/vpn-limits/limits.db 2>/dev/null || true)")"
fi
if [[ -f /var/lib/vpn-limits/suspended.db && -s /var/lib/vpn-limits/suspended.db ]]; then
  echo -e "$(T "Suspended users       : " "User di-suspend       : " "被暂停用户            : ")${_C_RED}$(cut -d: -f1 /var/lib/vpn-limits/suspended.db | tr '\n' ' ')${_C_RESET}"
fi

# 7. SSL certificate (acme.sh, v4.7)
echo "--------------------------------------------------------------------------------"
echo -e "${_C_BOLD}$(T "SSL CERTIFICATE (acme.sh):" "SERTIFIKAT SSL (acme.sh):" "SSL 证书 (acme.sh)：")${_C_RESET}"
if [[ -x /root/.acme.sh/acme.sh ]]; then
  if [[ -f /etc/vpn-ssl/params ]]; then
    # shellcheck disable=SC1091
    source /etc/vpn-ssl/params
    echo "$(T "Domain                : ${SSL_DOMAIN:-?}" "Domain                : ${SSL_DOMAIN:-?}" "域名                  : ${SSL_DOMAIN:-?}")"
    echo "$(T "Mode                  : ${SSL_MODE:-?}" "Mode                  : ${SSL_MODE:-?}" "模式                  : ${SSL_MODE:-?}")"
    cert_f="/etc/vpn-ssl/${SSL_DOMAIN:-}/fullchain.pem"
    if [[ -f "$cert_f" ]]; then
      if openssl x509 -in "$cert_f" -noout -checkend 0 >/dev/null 2>&1; then
        echo -e "$(T "Certificate           : " "Sertifikat            : " "证书                  : ")${_C_GREEN}[VALID]${_C_RESET} ($(T "expires: $(openssl x509 -in "$cert_f" -noout -enddate 2>/dev/null | cut -d= -f2)" "kedaluwarsa: $(openssl x509 -in "$cert_f" -noout -enddate 2>/dev/null | cut -d= -f2)" "到期：$(openssl x509 -in "$cert_f" -noout -enddate 2>/dev/null | cut -d= -f2)"))"
      else
        echo -e "$(T "Certificate           : " "Sertifikat            : " "证书                  : ")${_C_RED}[EXPIRED / INVALID]${_C_RESET}"
      fi
    else
      echo -e "$(T "Certificate file      : " "File sertifikat       : " "证书文件              : ")${_C_RED}[MISSING]${_C_RESET}"
    fi
  else
    echo "$(T "No certificate issued via this installer yet." "Belum ada sertifikat yang diterbitkan via installer ini." "尚未通过此安装程序签发任何证书。")"
  fi
  if crontab -l 2>/dev/null | grep -q "acme.sh.*--cron"; then
    echo -e "$(T "Auto-renew (cron)     : " "Auto-renew (cron)     : " "自动续期 (cron)        : ")${_C_GREEN}[ENABLED]${_C_RESET}"
  else
    echo -e "$(T "Auto-renew (cron)     : " "Auto-renew (cron)     : " "自动续期 (cron)        : ")${_C_YELLOW}[NOT SET]${_C_RESET}"
  fi
else
  echo -e "$(T "acme.sh               : " "acme.sh               : " "acme.sh               : ")${_C_YELLOW}[NOT INSTALLED]${_C_RESET} ($(T "run menu 24 or ./setup-ssl.sh" "jalankan menu 24 atau ./setup-ssl.sh" "请运行菜单 24 或 ./setup-ssl.sh"))"
fi

# 8. Saved account summary (v5: /etc/vpn-script/client-config.txt, secrets, mode 600)
echo "--------------------------------------------------------------------------------"
echo -e "${_C_BOLD}$(T "SAVED ACCOUNT SUMMARY:" "RINGKASAN AKUN TERSIMPAN:" "已保存账户摘要：")${_C_RESET}"
if [[ -f /etc/vpn-script/client-config.txt ]]; then
  echo "$(T "File                  : /etc/vpn-script/client-config.txt ($(wc -l < /etc/vpn-script/client-config.txt) lines, $(du -h /etc/vpn-script/client-config.txt 2>/dev/null | cut -f1))" "File                  : /etc/vpn-script/client-config.txt ($(wc -l < /etc/vpn-script/client-config.txt) baris, $(du -h /etc/vpn-script/client-config.txt 2>/dev/null | cut -f1))" "文件                  ：/etc/vpn-script/client-config.txt（$(wc -l < /etc/vpn-script/client-config.txt) 行，$(du -h /etc/vpn-script/client-config.txt 2>/dev/null | cut -f1)）")"
  echo "$(T "Re-show               : sudo ./show-account.sh [user] [--qr] (menu 25)" "Lihat lagi            : sudo ./show-account.sh [user] [--qr] (menu 25)" "再次查看              ：sudo ./show-account.sh [user] [--qr]（菜单 25）")"
else
  echo -e "$(T "Summary file          : " "File ringkasan        : " "摘要文件              : ")${_C_YELLOW}[$(T "NOT CREATED YET — new accounts save automatically" "BELUM DIBUAT — akun baru otomatis tersimpan" "尚未创建 — 新账户将自动保存")]${_C_RESET}"
fi

echo "================================================================================"
echo " $(T "By wrwb Store" "Dibuat oleh wrwb Store" "由 wrwb Store 打造")"
