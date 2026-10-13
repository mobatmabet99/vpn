#!/bin/bash
# ==============================================================================
#  remove-xray-user.sh — Menghapus User Xray/V2Ray dari Semua Inbound
#  Penggunaan:
#    sudo ./remove-xray-user.sh [nama_user]
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
  echo -e "${_C_BOLD}HAPUS USER XRAY/V2RAY${_C_RESET}"
  echo "================================================================"
  xray_list_users
  echo ""
  read -rp "Nama user yang dihapus: " USERNAME
fi

if [[ "${AUTO_YES:-0}" != "1" ]]; then
  read -rp "Yakin hapus user Xray '$USERNAME'? [y/N]: " confirm_del
  [[ "$confirm_del" =~ ^[Yy]$ ]] || die "Penghapusan dibatalkan."
fi

xray_remove_user "$USERNAME"

echo ""
log_success "User Xray '$USERNAME' berhasil dihapus."
echo ""
