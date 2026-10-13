#!/bin/bash
# ==============================================================================
#  add-xray-user.sh — Membuat User Xray/V2Ray Baru (dengan limit IP & bandwidth)
#  Branding: wrwb Store
#  Penggunaan:
#    sudo ./add-xray-user.sh [nama_user] [max_ip] [max_gb]
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
echo -e "${_C_BOLD}BUAT USER XRAY/V2RAY BARU — wrwb Store${_C_RESET}"
echo "================================================================"

if [[ -z "$USERNAME" ]]; then
  read -rp "Nama user baru (contoh: hp-andi): " USERNAME
  read -rp "Limit IP concurrent [Default: 2]: " ip_input
  MAX_IP="${ip_input:-2}"
  read -rp "Limit Bandwidth GB / bulan [Default: 100]: " gb_input
  MAX_GB="${gb_input:-100}"
fi

[[ -z "$MAX_IP" ]] && MAX_IP="2"
[[ -z "$MAX_GB" ]] && MAX_GB="100"

[[ "$MAX_IP" =~ ^[0-9]+$ ]] || die "Limit IP harus berupa angka."
[[ "$MAX_GB" =~ ^[0-9]+$ ]] || die "Limit bandwidth harus berupa angka."

xray_create_user "$USERNAME"
limits_set "$USERNAME" "$MAX_IP" "$MAX_GB"

echo ""
echo "==================== ATRIBUT LIMIT (wrwb Store) ===================="
echo " Username    : $USERNAME"
echo " Limit IP    : $MAX_IP concurrent (Auto-suspend 5 menit jika > $MAX_IP IP)"
echo " Limit Kuota : $MAX_GB GB / bulan"
echo "===================================================================="
echo "Panduan Pemakaian:"
echo " 1. Salin salah satu link di atas ke aplikasi client:"
echo "    Android: v2rayNG / NekoBox | iOS: Streisand / FoXray / Shadowrocket"
echo "    Desktop: Nekoray / Invisible Man Xray / Hiddify"
echo " 2. Prioritas: VLESS REALITY (anti-blokir) > VLESS XTLS > VMess/VLESS/Trojan WS."
echo ""
