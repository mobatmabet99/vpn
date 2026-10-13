#!/bin/bash
# ==============================================================================
#  add-xray-user.sh — Create a new Xray/V2Ray user (with IP & bandwidth limits)
#  Branding: wrwb Store
#  Usage:
#    sudo ./add-xray-user.sh [username] [max_ip] [max_gb]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/xray.sh
source "$SCRIPT_DIR/lib/xray.sh"
# shellcheck source=lib/limits.sh
source "$SCRIPT_DIR/lib/limits.sh"

need_root

USERNAME="${1:-}"
MAX_IP="${2:-}"
MAX_GB="${3:-}"

echo "================================================================"
echo -e "${_C_BOLD}$(T "CREATE NEW XRAY/V2RAY USER — wrwb Store" "BUAT USER XRAY/V2RAY BARU — wrwb Store" "创建新的 XRAY/V2RAY 用户 — wrwb Store")${_C_RESET}"
echo "================================================================"

if [[ -z "$USERNAME" ]]; then
  read -rp "$(T "New username (e.g. phone-andi): " "Nama user baru (contoh: hp-andi): " "新用户名（例如 phone-andi）：")" USERNAME
  read -rp "$(T "Concurrent IP limit [Default: 2]: " "Limit IP concurrent [Default: 2]: " "并发 IP 限制 [默认: 2]：")" ip_input
  MAX_IP="${ip_input:-2}"
  read -rp "$(T "Bandwidth limit GB / month [Default: 100]: " "Limit Bandwidth GB / bulan [Default: 100]: " "带宽限制 GB/月 [默认: 100]：")" gb_input
  MAX_GB="${gb_input:-100}"
fi

[[ -z "$MAX_IP" ]] && MAX_IP="2"
[[ -z "$MAX_GB" ]] && MAX_GB="100"

[[ "$MAX_IP" =~ ^[0-9]+$ ]] || die "$(T "IP limit must be a number." "Limit IP harus berupa angka." "IP 限制必须为数字。")"
[[ "$MAX_GB" =~ ^[0-9]+$ ]] || die "$(T "Bandwidth limit must be a number." "Limit bandwidth harus berupa angka." "带宽限制必须为数字。")"

xray_create_user "$USERNAME"
limits_set "$USERNAME" "$MAX_IP" "$MAX_GB"

echo ""
echo "==================== $(T "LIMIT ATTRIBUTES (wrwb Store)" "ATRIBUT LIMIT (wrwb Store)" "限制属性 (wrwb Store)") ===================="
echo " $(T "Username   : $USERNAME" "Username    : $USERNAME" "用户名     : $USERNAME")"
echo " $(T "IP limit   : $MAX_IP concurrent (auto-suspend 5 min when over $MAX_IP IPs)" "Limit IP    : $MAX_IP concurrent (Auto-suspend 5 menit jika > $MAX_IP IP)" "IP 限制    : $MAX_IP 并发（超过 $MAX_IP 个 IP 自动暂停 5 分钟）")"
echo " $(T "Data quota : $MAX_GB GB / month" "Limit Kuota : $MAX_GB GB / bulan" "流量配额   : $MAX_GB GB/月")"
echo "===================================================================="
echo "$(T "Usage guide:" "Panduan Pemakaian:" "使用指南：")"
echo " 1. $(T "Copy one of the links above into a client app:" "Salin salah satu link di atas ke aplikasi client:" "将上方任一链接复制到客户端应用：")"
echo "    Android: v2rayNG / NekoBox | iOS: Streisand / FoXray / Shadowrocket"
echo "    Desktop: Nekoray / Hiddify"
echo " 2. $(T "Priority: VLESS REALITY (anti-blocking) > VLESS XTLS > VMess/VLESS/Trojan WS." "Prioritas: VLESS REALITY (anti-blokir) > VLESS XTLS > VMess/VLESS/Trojan WS." "优先级：VLESS REALITY（防封锁）> VLESS XTLS > VMess/VLESS/Trojan WS。")"
echo ""
