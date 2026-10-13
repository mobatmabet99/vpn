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
  log_warn "$(T "No clients registered in $WG_CONF." "Tidak ada client yang terdaftar di $WG_CONF.")"
  exit 0
fi

if [[ -z "$CLIENT_NAME" ]]; then
  echo "================================================================"
  echo -e "${_C_BOLD}$(T "REMOVE WIREGUARD CLIENT" "HAPUS CLIENT WIREGUARD")${_C_RESET}"
  echo "================================================================"
  echo "$(T "Select the client to remove:" "Pilih client yang ingin dihapus:")"
  for i in "${!CLIENT_LIST[@]}"; do
    printf "  %2d) %s\n" "$((i+1))" "${CLIENT_LIST[$i]}"
  done
  echo ""
  read -rp "$(T "Choose a number or type the client name: " "Pilih nomor atau ketik nama client: ")" choice

  if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 && "$choice" -le "${#CLIENT_LIST[@]}" ]]; then
    CLIENT_NAME="${CLIENT_LIST[$((choice-1))]}"
  else
    CLIENT_NAME="$choice"
  fi
fi

validate_client_name "$CLIENT_NAME"

if ! wg_client_exists "$CLIENT_NAME"; then
  die "$(T "Client '$CLIENT_NAME' was not found in the active client list." "Client '$CLIENT_NAME' tidak ditemukan di daftar client aktif.")"
fi

# Removal confirmation
if [[ "${AUTO_YES:-0}" != "1" ]]; then
  echo ""
  read -rp "$(T "Are you sure you want to remove client '$CLIENT_NAME'? [y/N]: " "Yakin ingin menghapus client '$CLIENT_NAME'? [y/N]: ")" confirm_del
  [[ "$confirm_del" =~ ^[Yy]$ ]] || die "$(T "Removal cancelled." "Penghapusan dibatalkan.")"
fi

wg_remove_client "$CLIENT_NAME"
limits_remove "$CLIENT_NAME"

echo ""
log_success "$(T "Client '$CLIENT_NAME' has been removed from the server." "Client '$CLIENT_NAME' berhasil dihapus dari server.")"
echo ""
