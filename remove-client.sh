#!/bin/bash
# ==============================================================================
#  remove-client.sh — Remove a WireGuard client
#  Usage:
#    sudo ./remove-client.sh [client_name]
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
load_params

CLIENT_NAME="${1:-}"

# Collect all registered clients
get_registered_clients() {
  local clients=()
  if [[ -f "$WG_CONF" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ ^###\ Client:\ (.*)$ ]]; then
        clients+=("${BASH_REMATCH[1]}")
      fi
    done < "$WG_CONF"
  fi
  echo "${clients[@]}"
}

mapfile -t CLIENT_LIST < <(get_registered_clients | tr ' ' '\n' | grep -v '^$' || true)

if [[ ${#CLIENT_LIST[@]} -eq 0 ]]; then
  log_warn "$(T "No clients registered in $WG_CONF." "Tidak ada client yang terdaftar di $WG_CONF." "在 $WG_CONF 中未找到已注册的客户端。")"
  exit 0
fi

if [[ -z "$CLIENT_NAME" ]]; then
  echo "================================================================"
  echo -e "${_C_BOLD}$(T "REMOVE WIREGUARD CLIENT" "HAPUS CLIENT WIREGUARD" "删除 WIREGUARD 客户端")${_C_RESET}"
  echo "================================================================"
  echo "$(T "Select the client to remove:" "Pilih client yang ingin dihapus:" "选择要删除的客户端：")"
  for i in "${!CLIENT_LIST[@]}"; do
    printf "  %2d) %s\n" "$((i+1))" "${CLIENT_LIST[$i]}"
  done
  echo ""
  read -rp "$(T "Choose a number or type the client name: " "Pilih nomor atau ketik nama client: " "选择编号或输入客户端名称：")" choice

  if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 && "$choice" -le "${#CLIENT_LIST[@]}" ]]; then
    CLIENT_NAME="${CLIENT_LIST[$((choice-1))]}"
  else
    CLIENT_NAME="$choice"
  fi
fi

validate_client_name "$CLIENT_NAME"

if ! wg_client_exists "$CLIENT_NAME"; then
  die "$(T "Client '$CLIENT_NAME' was not found in the active client list." "Client '$CLIENT_NAME' tidak ditemukan di daftar client aktif." "在运行中的客户端列表中未找到客户端 '$CLIENT_NAME'。")"
fi

# Removal confirmation
if [[ "${AUTO_YES:-0}" != "1" ]]; then
  echo ""
  read -rp "$(T "Are you sure you want to remove client '$CLIENT_NAME'? [y/N]: " "Yakin ingin menghapus client '$CLIENT_NAME'? [y/N]: " "确定要删除客户端 '$CLIENT_NAME' 吗？[y/N]：")" confirm_del
  [[ "$confirm_del" =~ ^[Yy]$ ]] || die "$(T "Removal cancelled." "Penghapusan dibatalkan." "删除已取消。")"
fi

wg_remove_client "$CLIENT_NAME"
limits_remove "$CLIENT_NAME"

echo ""
log_success "$(T "Client '$CLIENT_NAME' has been removed from the server." "Client '$CLIENT_NAME' berhasil dihapus dari server." "客户端 '$CLIENT_NAME' 已从服务器删除。")"
echo ""
