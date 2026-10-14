#!/bin/bash
# ==============================================================================
#  remove-amneziawg-user.sh — Remove an AmneziaWG client (v5)
#  Branding: wrwb Store
#  Usage:
#    sudo ./remove-amneziawg-user.sh [client_name]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/amneziawg.sh
source "$SCRIPT_DIR/lib/amneziawg.sh"

install_cleanup_trap
need_root

CLIENT_NAME="${1:-}"

echo "================================================================"
echo -e "${_C_BOLD}$(T "REMOVE AMNEZIAWG CLIENT — wrwb Store" "HAPUS CLIENT AMNEZIAWG — wrwb Store" "删除 AMNEZIAWG 客户端 — wrwb Store")${_C_RESET}"
echo "================================================================"

if [[ -z "$CLIENT_NAME" ]]; then
  read -rp "$(T "Enter client name to remove: " "Masukkan nama client yang dihapus: " "输入要删除的客户端名称：")" CLIENT_NAME
fi
validate_client_name "$CLIENT_NAME"

awg_remove_client "$CLIENT_NAME"
