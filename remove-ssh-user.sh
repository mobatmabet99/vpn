#!/bin/bash
# ==============================================================================
#  remove-ssh-user.sh — Remove an SSH VPN account
#  Usage:
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
  echo -e "${_C_BOLD}$(T "REMOVE SSH VPN ACCOUNT" "HAPUS AKUN SSH VPN" "删除 SSH VPN 账号")${_C_RESET}"
  echo "================================================================"
  if [[ -s "$SSH_ACCOUNTS_DB" ]]; then
    echo "$(T "Registered accounts:" "Akun terdaftar:" "已注册账号：")"
    cut -d: -f1 "$SSH_ACCOUNTS_DB" | sort | sed 's/^/  - /'
    echo ""
  fi
  read -rp "$(T "Username to remove: " "Username yang dihapus: " "要删除的用户名：")" USERNAME
fi

if [[ "${AUTO_YES:-0}" != "1" ]]; then
  read -rp "$(T "Really remove SSH account '$USERNAME'? [y/N]: " "Yakin hapus akun SSH '$USERNAME'? [y/N]: " "确定删除 SSH 账号 '$USERNAME' 吗？[y/N]：")" confirm_del
  [[ "$confirm_del" =~ ^[Yy]$ ]] || die "$(T "Removal cancelled." "Penghapusan dibatalkan." "删除已取消。")"
fi

ssh_remove_user "$USERNAME"
limits_remove "$USERNAME"

echo ""
log_success "$(T "SSH account '$USERNAME' has been removed." "Akun SSH '$USERNAME' berhasil dihapus." "SSH 账号 '$USERNAME' 已删除。")"
echo ""
