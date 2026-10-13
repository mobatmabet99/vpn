#!/bin/bash
# ==============================================================================
#  add-client.sh — Add a new WireGuard client (with IP & bandwidth limits)
#  Branding: wrwb Store
#  Usage:
#    sudo ./add-client.sh [client_name] [max_ip] [max_gb]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/wireguard.sh
source "$SCRIPT_DIR/lib/wireguard.sh"
# shellcheck source=lib/limits.sh
source "$SCRIPT_DIR/lib/limits.sh"

need_root

CLIENT_NAME="${1:-}"
MAX_IP="${2:-}"
MAX_GB="${3:-}"

echo "================================================================"
echo -e "${_C_BOLD}$(T "ADD NEW WIREGUARD CLIENT — wrwb Store" "TAMBAH CLIENT WIREGUARD BARU — wrwb Store")${_C_RESET}"
echo "================================================================"

if [[ -z "$CLIENT_NAME" ]]; then
  read -rp "$(T "Enter new client name (e.g. phone-andi): " "Masukkan nama client baru (contoh: hp-andi): ")" CLIENT_NAME
  read -rp "$(T "Concurrent IP limit [Default: 2]: " "Limit IP concurrent [Default: 2]: ")" ip_input
  MAX_IP="${ip_input:-2}"
  read -rp "$(T "Bandwidth limit GB / month [Default: 100]: " "Limit Bandwidth GB / bulan [Default: 100]: ")" gb_input
  MAX_GB="${gb_input:-100}"
fi

[[ -z "$MAX_IP" ]] && MAX_IP="2"
[[ -z "$MAX_GB" ]] && MAX_GB="100"

validate_client_name "$CLIENT_NAME"
[[ "$MAX_IP" =~ ^[0-9]+$ ]] || die "$(T "IP limit must be a number." "Limit IP harus berupa angka.")"
[[ "$MAX_GB" =~ ^[0-9]+$ ]] || die "$(T "Bandwidth limit must be a number." "Limit bandwidth harus berupa angka.")"

wg_create_client "$CLIENT_NAME"
limits_set "$CLIENT_NAME" "$MAX_IP" "$MAX_GB"

echo ""
echo "==================== $(T "LIMIT ATTRIBUTES (wrwb Store)" "ATRIBUT LIMIT (wrwb Store)") ===================="
echo " $(T "Client     : $CLIENT_NAME" "Client      : $CLIENT_NAME")"
echo " $(T "IP limit   : $MAX_IP concurrent (auto-suspend 5 min when over $MAX_IP IPs)" "Limit IP    : $MAX_IP concurrent (Auto-suspend 5 menit jika > $MAX_IP IP)")"
echo " $(T "Data quota : $MAX_GB GB / month" "Limit Kuota : $MAX_GB GB / bulan")"
echo "===================================================================="
log_success "$(T "WireGuard client '$CLIENT_NAME' created and saved!" "Client WireGuard '$CLIENT_NAME' berhasil dibuat dan disimpan!")"
echo ""
