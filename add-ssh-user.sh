#!/bin/bash
# ==============================================================================
#  add-ssh-user.sh — Membuat Akun SSH VPN Baru (dengan masa berlaku, limit IP & bandwidth)
#  Branding: wrwb Store
#  Penggunaan:
#    sudo ./add-ssh-user.sh [username] [password] [masa_hari] [max_ip] [max_gb]
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
echo -e "${_C_BOLD}BUAT AKUN SSH VPN BARU — wrwb Store${_C_RESET}"
echo "================================================================"

if [[ -z "$USERNAME" ]]; then
  read -rp "Username baru (contoh: andi): " USERNAME
  read -rp "Password (kosongkan = auto-generate): " PASSWORD
  read -rp "Masa berlaku hari [30]: " days_input
  DAYS="${days_input:-30}"
  
  read -rp "Limit IP concurrent [Default: 2]: " ip_input
  MAX_IP="${ip_input:-2}"
  
  read -rp "Limit Bandwidth GB / bulan [Default: 100]: " gb_input
  MAX_GB="${gb_input:-100}"
fi

[[ -z "$MAX_IP" ]] && MAX_IP="2"
[[ -z "$MAX_GB" ]] && MAX_GB="100"

[[ "$DAYS" =~ ^[0-9]+$ ]] || die "Masa berlaku harus berupa angka hari."
[[ "$MAX_IP" =~ ^[0-9]+$ ]] || die "Limit IP harus berupa angka."
[[ "$MAX_GB" =~ ^[0-9]+$ ]] || die "Limit bandwidth harus berupa angka."

ssh_create_user "$USERNAME" "$PASSWORD" "$DAYS"
limits_set "$USERNAME" "$MAX_IP" "$MAX_GB"

# Ambil info koneksi bila params tersedia
SSH_HOST="IP-SERVER"
SSH_PORT="22"
if [[ -f "$SSH_PARAMS" ]]; then
  # shellcheck disable=SC1090
  source "$SSH_PARAMS"
  SSH_HOST="${SSH_PUB_IP:-$SSH_HOST}"
  SSH_PORT="${SSH_PORT:-22}"
fi

echo ""
echo "==================== DETAIL AKUN SSH (wrwb Store) ===================="
echo " Host         : $SSH_HOST"
echo " Port SSH     : $SSH_PORT"
echo " Username     : $SSH_LAST_USER"
echo " Password     : $SSH_LAST_PASS"
echo " Berlaku s/d  : $SSH_LAST_EXPIRE"
echo " Limit IP     : $MAX_IP concurrent (Auto-suspend 5m jika multi-login)"
echo " Limit Kuota  : $MAX_GB GB / bulan"
echo "======================================================================"
echo "Contoh koneksi : ssh -p $SSH_PORT $SSH_LAST_USER@$SSH_HOST"
echo ""
