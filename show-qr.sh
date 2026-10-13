#!/bin/bash
# ==============================================================================
#  show-qr.sh — Show a WireGuard client QR code and config (bilingual EN/ID)
#  Usage:
#    sudo ./show-qr.sh [client_name]
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

# Find clients that own a .conf file
find_clients() {
  find "$CLIENTS_DIR" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" 2>/dev/null || true
}

mapfile -t CLIENT_LIST < <(find_clients | sort)

if [[ ${#CLIENT_LIST[@]} -eq 0 ]]; then
  die "$(T "No clients registered yet. Run './add-client.sh' first." "Belum ada client yang terdaftar. Jalankan './add-client.sh' terlebih dahulu.")"
fi

if [[ -z "$CLIENT_NAME" ]]; then
  echo "================================================================"
  echo -e "${_C_BOLD}$(T "SHOW WIREGUARD CLIENT QR CODE" "TAMPILKAN QR CODE CLIENT WIREGUARD")${_C_RESET}"
  echo "================================================================"
  echo "$(T "Select a client:" "Pilih client:")"
  for i in "${!CLIENT_LIST[@]}"; do
    printf "  %2d) %s\n" "$((i+1))" "${CLIENT_LIST[$i]}"
  done
  echo ""
  read -rp "$(T "Choose a number or client name: " "Pilih nomor atau nama client: ")" choice

  if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 && "$choice" -le "${#CLIENT_LIST[@]}" ]]; then
    CLIENT_NAME="${CLIENT_LIST[$((choice-1))]}"
  else
    CLIENT_NAME="$choice"
  fi
fi

CONF_PATH="$CLIENTS_DIR/$CLIENT_NAME/${CLIENT_NAME}.conf"

if [[ ! -f "$CONF_PATH" ]]; then
  die "$(T "Config file not found: $CONF_PATH" "File konfigurasi tidak ditemukan: $CONF_PATH")"
fi

echo ""
echo "==================== QR CODE: $CLIENT_NAME ===================="
if command -v qrencode &>/dev/null; then
  qrencode -t ansiutf8 < "$CONF_PATH"
else
  log_warn "$(T "qrencode is not installed yet. Showing the plain text config instead:" "Perintah qrencode belum terpasang. Menampilkan isi konfigurasi text saja:")"
fi
echo "================================================================"
echo "$(T "Config file location: $CONF_PATH" "Lokasi file konfigurasi: $CONF_PATH")"
if [[ -f "$CLIENTS_DIR/$CLIENT_NAME/${CLIENT_NAME}.png" ]]; then
  echo "$(T "PNG image location : $CLIENTS_DIR/$CLIENT_NAME/${CLIENT_NAME}.png" "Lokasi file gambar PNG : $CLIENTS_DIR/$CLIENT_NAME/${CLIENT_NAME}.png")"
fi
echo ""
echo "$(T "Config file contents ($CONF_PATH):" "Isi file konfigurasi ($CONF_PATH):")"
echo "----------------------------------------------------------------"
cat "$CONF_PATH"
echo "----------------------------------------------------------------"
echo ""
