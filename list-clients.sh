#!/bin/bash
# ==============================================================================
#  list-clients.sh — List WireGuard clients & connection status (bilingual EN/ID)
#  Usage:
#    sudo ./list-clients.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/wireguard.sh
source "$SCRIPT_DIR/lib/wireguard.sh"

need_root
load_params

echo "================================================================================"
echo -e "${_C_BOLD}$(T "WIREGUARD CLIENT LIST & CONNECTION STATUS" "DAFTAR CLIENT WIREGUARD & STATUS KONEKSI")${_C_RESET}"
echo "================================================================================"

if [[ ! -f "$WG_CONF" ]]; then
  die "$(T "Config $WG_CONF not found. WireGuard is not installed yet." "Konfigurasi $WG_CONF tidak ditemukan. WireGuard belum terpasang.")"
fi

# Parse client data from wg0.conf
# Collect name, allowed IPs, and public key
declare -A CLIENT_PUBKEYS
declare -A CLIENT_IPS
CLIENT_NAMES=()

current_name=""
current_ip=""
current_pub=""

while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^###\ Client:\ (.*)$ ]]; then
    current_name="${BASH_REMATCH[1]}"
    CLIENT_NAMES+=("$current_name")
  elif [[ -n "$current_name" && "$line" =~ ^PublicKey\ =\ (.*)$ ]]; then
    current_pub="${BASH_REMATCH[1]}"
    CLIENT_PUBKEYS["$current_name"]="$current_pub"
  elif [[ -n "$current_name" && "$line" =~ ^AllowedIPs\ =\ (.*)$ ]]; then
    current_ip="${BASH_REMATCH[1]}"
    CLIENT_IPS["$current_name"]="$current_ip"
  elif [[ "$line" =~ ^###\ End:\ (.*)$ ]]; then
    current_name=""
  fi
done < "$WG_CONF"

if [[ ${#CLIENT_NAMES[@]} -eq 0 ]]; then
  echo "$(T "No clients registered yet." "Belum ada client yang terdaftar.")"
  echo "$(T "Run 'sudo ./add-client.sh' to create the first client." "Jalankan 'sudo ./add-client.sh' untuk membuat client pertama.")"
  exit 0
fi

# Grab runtime wg dump when active
WG_DUMP=""
if systemctl is-active --quiet wg-quick@wg0 && command -v wg &>/dev/null; then
  WG_DUMP="$(wg show wg0 dump 2>/dev/null || true)"
fi

human_bytes() {
  local bytes="${1:-0}"
  if [[ "$bytes" -lt 1024 ]]; then
    echo "${bytes} B"
  elif [[ "$bytes" -lt 1048576 ]]; then
    echo "$((bytes / 1024)) KB"
  elif [[ "$bytes" -lt 1073741824 ]]; then
    echo "$((bytes / 1048576)) MB"
  else
    echo "$((bytes / 1073741824)) GB"
  fi
}

human_time() {
  local epoch="${1:-0}"
  if [[ "$epoch" -eq 0 ]]; then
    echo "$(T "Never" "Belum pernah")"
    return
  fi
  local now diff
  now="$(date +%s)"
  diff=$((now - epoch))
  if [[ "$diff" -lt 60 ]]; then
    echo "$(T "${diff}s ago" "${diff} detik lalu")"
  elif [[ "$diff" -lt 3600 ]]; then
    echo "$(T "$((diff / 60))m ago" "$((diff / 60)) menit lalu")"
  elif [[ "$diff" -lt 86400 ]]; then
    echo "$(T "$((diff / 3600))h ago" "$((diff / 3600)) jam lalu")"
  else
    echo "$(T "$((diff / 86400))d ago" "$((diff / 86400)) hari lalu")"
  fi
}

printf "%-16s %-16s %-16s %-12s %-12s\n" "$(T "CLIENT NAME" "NAMA CLIENT")" "$(T "CLIENT IP" "IP CLIENT")" "$(T "LAST SEEN" "TERAKHIR KONEK")" "DOWNLOAD" "UPLOAD"
echo "--------------------------------------------------------------------------------"

for name in "${CLIENT_NAMES[@]}"; do
  ip="${CLIENT_IPS[$name]:-N/A}"
  pub="${CLIENT_PUBKEYS[$name]:-}"
  # trim to the IPv4 prefix only for a tidy table
  ip_short="$(echo "$ip" | cut -d, -f1 | tr -d ' ')"

  last_seen="$(T "Never" "Belum pernah")"
  rx_str="0 B"
  tx_str="0 B"

  if [[ -n "$WG_DUMP" && -n "$pub" ]]; then
    # wg show dump format:
    # public-key preshared-key endpoint allowed-ips latest-handshake rx-bytes tx-bytes persistent-keepalive
    peer_line="$(echo "$WG_DUMP" | grep "^${pub}" || true)"
    if [[ -n "$peer_line" ]]; then
      handshake="$(echo "$peer_line" | awk '{print $5}')"
      rx="$(echo "$peer_line" | awk '{print $6}')"
      tx="$(echo "$peer_line" | awk '{print $7}')"

      if [[ "$handshake" -gt 0 ]]; then
        last_seen="$(human_time "$handshake")"
      fi
      rx_str="$(human_bytes "$rx")"
      tx_str="$(human_bytes "$tx")"
    fi
  fi

  printf "%-16s %-16s %-16s %-12s %-12s\n" "$name" "$ip_short" "$last_seen" "$rx_str" "$tx_str"
done

echo "--------------------------------------------------------------------------------"
echo "$(T "Total registered clients: ${#CLIENT_NAMES[@]}" "Total client terdaftar: ${#CLIENT_NAMES[@]}")"
echo "$(T "Config folder location: $CLIENTS_DIR/<client_name>/" "Lokasi folder konfigurasi: $CLIENTS_DIR/<nama_client>/")"
echo "$(T "Show QR code again  : sudo ./show-qr.sh <client_name>" "Tampilkan QR code lagi : sudo ./show-qr.sh <nama_client>")"
echo "================================================================================"
