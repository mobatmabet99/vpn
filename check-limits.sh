#!/bin/bash
# ==============================================================================
#  check-limits.sh — Lihat limit IP, pemakaian bandwidth & status suspend
#  Dibuat oleh wrwb Store
#  Penggunaan:
#    sudo ./check-limits.sh [nama_user]   # kosong = semua user
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/limits.sh
source "$SCRIPT_DIR/lib/limits.sh"

need_root
limits_init

FILTER="${1:-}"

echo "======================================================================"
echo -e "${_C_BOLD}LIMIT IP & BANDWIDTH — wrwb Store${_C_RESET}"
echo "======================================================================"
printf "%-18s %-8s %-8s %-20s %-14s\n" "USER" "MAX-IP" "AKTIF" "KUOTA (PAKAI/MAX)" "STATUS"
echo "----------------------------------------------------------------------"

if [[ ! -s "$LIMITS_DB" ]]; then
  echo " (Belum ada user yang terdaftar di database limit)"
else
  while IFS=: read -r user max_ip max_gb _rest; do
    [[ -z "$user" ]] && continue
    [[ "$user" =~ ^# ]] && continue
    if [[ -n "$FILTER" && "$user" != "$FILTER" ]]; then
      continue
    fi
    [[ "$max_ip" =~ ^[0-9]+$ ]] || max_ip="$DEFAULT_MAX_IP"
    [[ "$max_gb" =~ ^[0-9]+$ ]] || max_gb="$DEFAULT_MAX_GB"
    active_ips="$(session_count_ips "$user")"
    bytes_used="$(usage_get_bytes "$user")"
    gb_used="$(awk -v b="$bytes_used" 'BEGIN { printf "%.2f", b/1073741824 }')"
    status="AKTIF"
    if suspend_is_active "$user"; then
      remain="$(suspend_remaining "$user")"
      status="SUSPEND ${remain}s"
    elif ! usage_check_limit "$user" 2>/dev/null; then
      status="OVER-KUOTA"
    fi
    printf "%-18s %-8s %-8s %-20s %-14s\n" "$user" "$max_ip" "$active_ips" "${gb_used}/${max_gb} GB" "$status"
  done < "$LIMITS_DB"
fi

echo "----------------------------------------------------------------------"
echo "Default akun baru: 2 IP concurrent, 100 GB/bulan."
echo "Multi-login > limit = auto-suspend 5 menit + auto-clear sesi."
echo "Dibuat oleh wrwb Store"
echo "======================================================================"
