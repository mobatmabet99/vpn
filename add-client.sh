#!/bin/bash
# ==============================================================================
#  add-client.sh — Menambah Client WireGuard Baru
#  Penggunaan:
#    sudo ./add-client.sh [nama_client]
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

if [[ -z "$CLIENT_NAME" ]]; then
  echo "================================================================"
  echo -e "${_C_BOLD}TAMBAH CLIENT WIREGUARD BARU${_C_RESET}"
  echo "================================================================"
  read -rp "Masukkan nama client baru (contoh: hp-andi, laptop-kerja): " CLIENT_NAME
fi

# Validasi format nama
validate_client_name "$CLIENT_NAME"

# Buat client
wg_create_client "$CLIENT_NAME"

echo ""
echo "==================== DETAIL CLIENT WIREGUARD ===================="
echo " Nama Client      : $CLIENT_NAME"
echo " IP Client (IPv4) : $CLIENT_IPV4"
echo " IP Client (IPv6) : $CLIENT_IPV6"
echo " File Konfigurasi : $LAST_CLIENT_CONF"
echo " File QR Code PNG : $LAST_CLIENT_PNG"
echo "================================================================="

# Tampilkan QR Code di terminal
wg_show_client_qr "$LAST_CLIENT_CONF"

echo "Panduan Pemakaian:"
echo " 1. HP / Tablet: Buka aplikasi WireGuard lalu scan QR Code di atas."
echo " 2. Laptop / Desktop: Unduh dan import file: $LAST_CLIENT_CONF"
echo ""
