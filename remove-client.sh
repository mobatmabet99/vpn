#!/bin/bash
# ==============================================================================
#  remove-client.sh — Menghapus Client WireGuard
#  Penggunaan:
#    sudo ./remove-client.sh [nama_client]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/wireguard.sh
source "$SCRIPT_DIR/lib/wireguard.sh"

need_root
load_params

CLIENT_NAME="${1:-}"

# Kumpulkan semua client yang terdaftar
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
  log_warn "Tidak ada client yang terdaftar di $WG_CONF."
  exit 0
fi

if [[ -z "$CLIENT_NAME" ]]; then
  echo "================================================================"
  echo -e "${_C_BOLD}HAPUS CLIENT WIREGUARD${_C_RESET}"
  echo "================================================================"
  echo "Pilih client yang ingin dihapus:"
  for i in "${!CLIENT_LIST[@]}"; do
    printf "  %2d) %s\n" "$((i+1))" "${CLIENT_LIST[$i]}"
  done
  echo ""
  read -rp "Pilih nomor atau ketik nama client: " choice

  if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 && "$choice" -le "${#CLIENT_LIST[@]}" ]]; then
    CLIENT_NAME="${CLIENT_LIST[$((choice-1))]}"
  else
    CLIENT_NAME="$choice"
  fi
fi

validate_client_name "$CLIENT_NAME"

if ! wg_client_exists "$CLIENT_NAME"; then
  die "Client '$CLIENT_NAME' tidak ditemukan di daftar client aktif."
fi

# Konfirmasi penghapusan
if [[ "${AUTO_YES:-0}" != "1" ]]; then
  echo ""
  read -rp "Yakin ingin menghapus client '$CLIENT_NAME'? [y/N]: " confirm_del
  [[ "$confirm_del" =~ ^[Yy]$ ]] || die "Penghapusan dibatalkan."
fi

wg_remove_client "$CLIENT_NAME"

echo ""
log_success "Client '$CLIENT_NAME' berhasil dihapus dari server."
echo ""
