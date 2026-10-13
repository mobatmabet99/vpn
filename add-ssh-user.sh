#!/bin/bash
# ==============================================================================
#  add-ssh-user.sh — Create a new SSH VPN account (expiry, IP & bandwidth limits)
#  Branding: wrwb Store
#  Usage:
#    sudo ./add-ssh-user.sh [username] [password] [valid_days] [max_ip] [max_gb]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/ssh.sh
source "$SCRIPT_DIR/lib/ssh.sh"
# shellcheck source=lib/limits.sh
source "$SCRIPT_DIR/lib/limits.sh"

need_root

USERNAME="${1:-}"
PASSWORD="${2:-}"
DAYS="${3:-30}"
MAX_IP="${4:-}"
MAX_GB="${5:-}"

echo "================================================================"
echo -e "${_C_BOLD}$(T "CREATE NEW SSH VPN ACCOUNT — wrwb Store" "BUAT AKUN SSH VPN BARU — wrwb Store")${_C_RESET}"
echo "================================================================"

if [[ -z "$USERNAME" ]]; then
  read -rp "$(T "New username (e.g. andi): " "Username baru (contoh: andi): ")" USERNAME
  read -rp "$(T "Password (empty = auto-generate): " "Password (kosongkan = auto-generate): ")" PASSWORD
  read -rp "$(T "Validity in days [30]: " "Masa berlaku hari [30]: ")" days_input
  DAYS="${days_input:-30}"

  read -rp "$(T "Concurrent IP limit [Default: 2]: " "Limit IP concurrent [Default: 2]: ")" ip_input
  MAX_IP="${ip_input:-2}"

  read -rp "$(T "Bandwidth limit GB / month [Default: 100]: " "Limit Bandwidth GB / bulan [Default: 100]: ")" gb_input
  MAX_GB="${gb_input:-100}"
fi

[[ -z "$MAX_IP" ]] && MAX_IP="2"
[[ -z "$MAX_GB" ]] && MAX_GB="100"

[[ "$DAYS" =~ ^[0-9]+$ ]] || die "$(T "Validity must be a number of days." "Masa berlaku harus berupa angka hari.")"
[[ "$MAX_IP" =~ ^[0-9]+$ ]] || die "$(T "IP limit must be a number." "Limit IP harus berupa angka.")"
[[ "$MAX_GB" =~ ^[0-9]+$ ]] || die "$(T "Bandwidth limit must be a number." "Limit bandwidth harus berupa angka.")"

ssh_create_user "$USERNAME" "$PASSWORD" "$DAYS"
limits_set "$USERNAME" "$MAX_IP" "$MAX_GB"

# Fetch connection info when params are available
SSH_HOST="SERVER-IP"
SSH_PORT="22"
if [[ -f "$SSH_PARAMS" ]]; then
  # shellcheck disable=SC1090
  source "$SSH_PARAMS"
  SSH_HOST="${SSH_PUB_IP:-$SSH_HOST}"
  SSH_PORT="${SSH_PORT:-22}"
fi

echo ""
echo "==================== $(T "SSH ACCOUNT DETAILS (wrwb Store)" "DETAIL AKUN SSH (wrwb Store)") ===================="
echo " $(T "Host         : $SSH_HOST" "Host         : $SSH_HOST")"
echo " $(T "SSH port     : $SSH_PORT" "Port SSH     : $SSH_PORT")"
echo " $(T "Username     : $SSH_LAST_USER" "Username     : $SSH_LAST_USER")"
echo " $(T "Password     : $SSH_LAST_PASS" "Password     : $SSH_LAST_PASS")"
echo " $(T "Valid until  : $SSH_LAST_EXPIRE" "Berlaku s/d  : $SSH_LAST_EXPIRE")"
echo " $(T "IP limit     : $MAX_IP concurrent (auto-suspend 5m on multi-login)" "Limit IP     : $MAX_IP concurrent (Auto-suspend 5m jika multi-login)")"
echo " $(T "Data quota   : $MAX_GB GB / month" "Limit Kuota  : $MAX_GB GB / bulan")"
echo "======================================================================"
echo "$(T "Connection example : ssh -p $SSH_PORT $SSH_LAST_USER@$SSH_HOST" "Contoh koneksi : ssh -p $SSH_PORT $SSH_LAST_USER@$SSH_HOST")"
echo ""
