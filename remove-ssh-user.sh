#!/bin/bash
# ==============================================================================
#  remove-ssh-user.sh — Menghapus Akun SSH VPN
#  Penggunaan:
#    sudo ./remove-ssh-user.sh [username]
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

if [[ -z "$USERNAME" ]]; then
  echo "================================================================"
  echo -e "${_C_BOLD}HAPUS AKUN SSH VPN${_C_RESET}"
  echo "================================================================"
  if [[ -s "$SSH_ACCOUNTS_DB" ]]; then
    echo "Akun terdaftar:"
    cut -d: -f1 "$SSH_ACCOUNTS_DB" | sort | sed 's/^/  - /'
    echo ""
  fi
  read -rp "Username yang dihapus: " USERNAME
fi

if [[ "${AUTO_YES:-0}" != "1" ]]; then
  read -rp "Yakin hapus akun SSH '$USERNAME'? [y/N]: " confirm_del
  [[ "$confirm_del" =~ ^[Yy]$ ]] || die "Penghapusan dibatalkan."
fi

ssh_remove_user "$USERNAME"
limits_remove "$USERNAME"

echo ""
log_success "Akun SSH '$USERNAME' berhasil dihapus."
echo ""
