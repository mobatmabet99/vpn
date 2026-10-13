#!/bin/bash
# ==============================================================================
#  add-xray-user.sh — Membuat User Xray/V2Ray Baru (VMess/VLESS/Trojan+REALITY)
#  Penggunaan:
#    sudo ./add-xray-user.sh [nama_user]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/xray.sh
source "$SCRIPT_DIR/lib/xray.sh"

need_root

USERNAME="${1:-}"

if [[ -z "$USERNAME" ]]; then
  echo "================================================================"
  echo -e "${_C_BOLD}BUAT USER XRAY/V2RAY BARU${_C_RESET}"
  echo "================================================================"
  read -rp "Nama user baru (contoh: hp-andi): " USERNAME
fi

xray_create_user "$USERNAME"

echo ""
echo "Panduan Pemakaian:"
echo " 1. Salin salah satu link di atas ke aplikasi client:"
echo "    Android: v2rayNG / NekoBox | iOS: Streisand / FoXray / Shadowrocket"
echo "    Desktop: Nekoray / Invisible Man Xray / Hiddify"
echo " 2. Prioritas: VLESS REALITY (anti-blokir) > VLESS XTLS > VMess/VLESS/Trojan WS."
echo ""
