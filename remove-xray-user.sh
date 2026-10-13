#!/bin/bash
# ==============================================================================
#  remove-xray-user.sh — Remove an Xray/V2Ray user from all inbounds
#  Usage:
#    sudo ./remove-xray-user.sh [username]
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

if [[ -z "$USERNAME" ]]; then
  echo "================================================================"
  echo -e "${_C_BOLD}$(T "REMOVE XRAY/V2RAY USER" "HAPUS USER XRAY/V2RAY" "删除 XRAY/V2RAY 用户")${_C_RESET}"
  echo "================================================================"
  xray_list_users
  echo ""
  read -rp "$(T "Username to remove: " "Nama user yang dihapus: " "要删除的用户名：")" USERNAME
fi

if [[ "${AUTO_YES:-0}" != "1" ]]; then
  read -rp "$(T "Really remove Xray user '$USERNAME'? [y/N]: " "Yakin hapus user Xray '$USERNAME'? [y/N]: " "确定删除 Xray 用户 '$USERNAME' 吗？[y/N]：")" confirm_del
  [[ "$confirm_del" =~ ^[Yy]$ ]] || die "$(T "Removal cancelled." "Penghapusan dibatalkan." "删除已取消。")"
fi

xray_remove_user "$USERNAME"
limits_remove "$USERNAME"

echo ""
log_success "$(T "Xray user '$USERNAME' has been removed." "User Xray '$USERNAME' berhasil dihapus." "Xray 用户 '$USERNAME' 已删除。")"
echo ""
