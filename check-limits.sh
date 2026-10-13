#!/bin/bash
# ==============================================================================
#  check-limits.sh — View IP limits, bandwidth usage & suspend status
#  Bilingual EN/ID (default: English). By wrwb Store
#  Usage:
#    sudo ./check-limits.sh [username]   # empty = all users
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
echo -e "${_C_BOLD}$(T "IP & BANDWIDTH LIMITS — wrwb Store" "LIMIT IP & BANDWIDTH — wrwb Store")${_C_RESET}"
echo "======================================================================"
printf "%-18s %-8s %-8s %-20s %-14s\n" "USER" "MAX-IP" "$(T "ACTIVE" "AKTIF")" "$(T "QUOTA (USED/MAX)" "KUOTA (PAKAI/MAX)")" "STATUS"
echo "----------------------------------------------------------------------"

if [[ ! -s "$LIMITS_DB" ]]; then
  echo " $(T "(No users registered in the limit database yet)" "(Belum ada user yang terdaftar di database limit)")"
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
    status="$(T "ACTIVE" "AKTIF")"
    if suspend_is_active "$user"; then
      remain="$(suspend_remaining "$user")"
      status="SUSPEND ${remain}s"
    elif ! usage_check_limit "$user" 2>/dev/null; then
      status="OVER-QUOTA"
    fi
    printf "%-18s %-8s %-8s %-20s %-14s\n" "$user" "$max_ip" "$active_ips" "${gb_used}/${max_gb} GB" "$status"
  done < "$LIMITS_DB"
fi

echo "----------------------------------------------------------------------"
echo "$(T "Default for new accounts: 2 concurrent IPs, 100 GB/month." "Default akun baru: 2 IP concurrent, 100 GB/bulan.")"
echo "$(T "Multi-login over the limit = auto-suspend 5 minutes + auto-clear sessions." "Multi-login > limit = auto-suspend 5 menit + auto-clear sesi.")"
echo "$(T "By wrwb Store" "Dibuat oleh wrwb Store")"
echo "======================================================================"
