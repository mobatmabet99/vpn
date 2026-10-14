#!/bin/bash
# ==============================================================================
#  add-amneziawg-user.sh — Create a new AmneziaWG client (v5, with QR)
#  Branding: wrwb Store
#  Usage:
#    sudo ./add-amneziawg-user.sh [client_name]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/amneziawg.sh
source "$SCRIPT_DIR/lib/amneziawg.sh"
# shellcheck source=lib/limits.sh
source "$SCRIPT_DIR/lib/limits.sh"

install_cleanup_trap
need_root

CLIENT_NAME="${1:-}"
MAX_IP="${2:-}"
MAX_GB="${3:-}"

echo "================================================================"
echo -e "${_C_BOLD}$(T "ADD NEW AMNEZIAWG CLIENT — wrwb Store" "TAMBAH CLIENT AMNEZIAWG BARU — wrwb Store" "添加新的 AMNEZIAWG 客户端 — wrwb Store")${_C_RESET}"
echo "================================================================"

if [[ -z "$CLIENT_NAME" ]]; then
  read -rp "$(T "Enter new client name (e.g. phone-andi): " "Masukkan nama client baru (mis. hp-andi): " "输入新客户端名称（例如 phone-andi）：")" CLIENT_NAME
fi
validate_client_name "$CLIENT_NAME"

awg_create_client "$CLIENT_NAME"

# Register default limits when args provided (same convention as add-client.sh)
if [[ -n "$MAX_IP" || -n "$MAX_GB" ]]; then
  limits_set "$CLIENT_NAME" "${MAX_IP:-2}" "${MAX_GB:-100}" || true
fi
