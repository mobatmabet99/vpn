#!/bin/bash
# ==============================================================================
#  add-ssh-user.sh — Membuat Akun SSH VPN Baru (dengan masa berlaku)
#  Penggunaan:
#    sudo ./add-ssh-user.sh [username] [password] [masa_hari]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/ssh.sh
source "$SCRIPT_DIR/lib/ssh.sh"

need_root

USERNAME="${1:-}"
PASSWORD="${2:-}"
DAYS="${3:-30}"

if [[ -z "$USERNAME" ]]; then
  echo "================================================================"
  echo -e "${_C_BOLD}BUAT AKUN SSH VPN BARU${_C_RESET}"
  echo "================================================================"
  read -rp "Username baru (contoh: andi): " USERNAME
  read -rp "Password (kosongkan = auto-generate): " PASSWORD
  read -rp "Masa berlaku hari [30]: " DAYS_INPUT
  DAYS="${DAYS_INPUT:-30}"
fi

[[ "$DAYS" =~ ^[0-9]+$ ]] || die "Masa berlaku harus berupa angka hari (contoh: 30)."

ssh_create_user "$USERNAME" "$PASSWORD" "$DAYS"

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
echo "==================== DETAIL AKUN SSH ===================="
echo " Host         : $SSH_HOST"
echo " Port SSH     : $SSH_PORT"
echo " Username     : $SSH_LAST_USER"
echo " Password     : $SSH_LAST_PASS"
echo " Berlaku s/d  : $SSH_LAST_EXPIRE"
echo "=========================================================="
echo "Contoh koneksi : ssh -p $SSH_PORT $SSH_LAST_USER@$SSH_HOST"
echo ""
