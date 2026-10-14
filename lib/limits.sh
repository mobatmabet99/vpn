#!/bin/bash
#
# lib/limits.sh — IP & bandwidth limit enforcement (wrwb Store, trilingual EN/ID/ZH)
#
# v1.2 features:
#   - Concurrent IP limit per user/client (default: 2 IPs)
#   - Bandwidth limit per user/client (default: 100 GB/month)
#   - 5-minute auto-suspend on multi-login detection (> IP limit)
#   - Auto-clear sessions after suspend so the next count starts fresh
#   - Database: /var/lib/vpn-limits/*.db
#   - Compatible: Debian 10/11/12/13, Ubuntu 20.04/22.04/24.04/26.04
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This file is a library. Do not run it directly." >&2
  exit 1
fi

LIMITS_DIR="/var/lib/vpn-limits"
LIMITS_DB="$LIMITS_DIR/limits.db"
USAGE_DB="$LIMITS_DIR/usage.db"
USAGE_LAST_DB="$LIMITS_DIR/usage_last.db"
SESSION_DB="$LIMITS_DIR/sessions.db"
SUSPEND_DB="$LIMITS_DIR/suspended.db"
WG_ENDPOINT_DB="$LIMITS_DIR/wg_endpoints.db"

# Default limit (dioverride per user saat pembuatan akun)
DEFAULT_MAX_IP="${DEFAULT_MAX_IP:-2}"
DEFAULT_MAX_GB="${DEFAULT_MAX_GB:-100}"
# Durasi suspend default: 300 detik = 5 menit
SUSPEND_SECONDS_DEFAULT=300
# Jendela sesi aktif: 600 detik = 10 menit
SESSION_WINDOW_DEFAULT=600

limits_init() {
  mkdir -p "$LIMITS_DIR"
  chmod 700 "$LIMITS_DIR"
  touch "$LIMITS_DB" "$USAGE_DB" "$USAGE_LAST_DB" "$SESSION_DB" "$SUSPEND_DB" "$WG_ENDPOINT_DB"
  chmod 600 "$LIMITS_DB" "$USAGE_DB" "$USAGE_LAST_DB" "$SESSION_DB" "$SUSPEND_DB" "$WG_ENDPOINT_DB"
}

# ------------------------------------------------------- Database helper
limits_set() {
  local user="$1" max_ip="${2:-$DEFAULT_MAX_IP}" max_gb="${3:-$DEFAULT_MAX_GB}"
  limits_init
  [[ "$max_ip" =~ ^[0-9]+$ ]] || max_ip="$DEFAULT_MAX_IP"
  [[ "$max_gb" =~ ^[0-9]+$ ]] || max_gb="$DEFAULT_MAX_GB"
  # Hapus entri lama user ini lalu tambah baru (aman untuk nama user aneh)
  if [[ -f "$LIMITS_DB" ]]; then
    local tmp
    tmp="$(mktemp)"
    track_temp "$tmp"
    grep -v "^${user}:" "$LIMITS_DB" > "$tmp" 2>/dev/null || true
    cat "$tmp" > "$LIMITS_DB"
    rm -f "$tmp"
  fi
  echo "${user}:${max_ip}:${max_gb}" >> "$LIMITS_DB"
}

limits_get() {
  local user="$1"
  limits_init
  local entry=""
  if [[ -f "$LIMITS_DB" ]]; then
    entry="$(grep "^${user}:" "$LIMITS_DB" 2>/dev/null | head -n1 || true)"
  fi
  if [[ -n "$entry" ]]; then
    echo "$entry"
  else
    echo "${user}:${DEFAULT_MAX_IP}:${DEFAULT_MAX_GB}"
  fi
}

limits_remove() {
  local user="$1"
  for f in "$LIMITS_DB" "$USAGE_DB" "$USAGE_LAST_DB" "$SESSION_DB" "$SUSPEND_DB" "$WG_ENDPOINT_DB"; do
    if [[ -f "$f" ]]; then
      local tmp
      tmp="$(mktemp)"
      track_temp "$tmp"
      grep -v "^${user}:" "$f" > "$tmp" 2>/dev/null || true
      cat "$tmp" > "$f"
      rm -f "$tmp"
    fi
  done
}

limits_show_user() {
  local user="$1"
  local entry max_ip max_gb bytes_used gb_used ips
  entry="$(limits_get "$user")"
  max_ip="$(echo "$entry" | cut -d: -f2)"
  max_gb="$(echo "$entry" | cut -d: -f3)"
  bytes_used="$(usage_get_bytes "$user")"
  gb_used="$(awk -v b="$bytes_used" 'BEGIN { printf "%.2f", b/1073741824 }')"
  ips="$(session_count_ips "$user")"
  echo "User: $user | $(T "IP limit: $max_ip (active: $ips)" "Limit IP: $max_ip (aktif: $ips)" "IP 限制：$max_ip（活跃：$ips）") | $(T "Quota: ${gb_used}/${max_gb} GB" "Kuota: ${gb_used}/${max_gb} GB" "配额：${gb_used}/${max_gb} GB")"
  if suspend_is_active "$user"; then
    echo "Status: SUSPENDED ($(T "multi-login, wait 5 minutes" "multi-login, tunggu 5 menit" "多登录，请等待 5 分钟"))"
  fi
}

# ------------------------------------------------------- Usage tracking (bandwidth)
_next_month_first_day() {
  # GNU date (Debian/Ubuntu) — hasil: YYYY-MM-01 bulan depan
  date -d "+1 month" +%Y-%m-01 2>/dev/null || date -d "next month" +%Y-%m-01 2>/dev/null || echo ""
}

usage_get_bytes() {
  local user="$1"
  limits_init
  local entry bytes_total reset_date now reset_epoch
  entry="$(grep "^${user}:" "$USAGE_DB" 2>/dev/null | head -n1 || true)"
  if [[ -z "$entry" ]]; then
    echo "0"
    return 0
  fi
  bytes_total="$(echo "$entry" | cut -d: -f2)"
  reset_date="$(echo "$entry" | cut -d: -f3)"
  [[ "$bytes_total" =~ ^[0-9]+$ ]] || bytes_total="0"
  now="$(date +%s)"
  reset_epoch="$(date -d "$reset_date" +%s 2>/dev/null || echo "")"
  if [[ -n "$reset_epoch" && "$now" -ge "$reset_epoch" ]]; then
    # Bulan baru: reset counter
    local new_reset
    new_reset="$(_next_month_first_day)"
    [[ -z "$new_reset" ]] && new_reset="$reset_date"
    local tmp
    tmp="$(mktemp)"
    track_temp "$tmp"
    grep -v "^${user}:" "$USAGE_DB" > "$tmp" 2>/dev/null || true
    cat "$tmp" > "$USAGE_DB"
    rm -f "$tmp"
    echo "${user}:0:${new_reset}" >> "$USAGE_DB"
    # Reset juga counter last (WireGuard delta)
    if [[ -f "$USAGE_LAST_DB" ]]; then
      tmp="$(mktemp)"
      track_temp "$tmp"
      grep -v "^${user}:" "$USAGE_LAST_DB" > "$tmp" 2>/dev/null || true
      cat "$tmp" > "$USAGE_LAST_DB"
      rm -f "$tmp"
    fi
    echo "0"
    return 0
  fi
  echo "$bytes_total"
}

usage_add_bytes() {
  local user="$1" add_bytes="$2"
  limits_init
  [[ "$add_bytes" =~ ^[0-9]+$ ]] || return 0
  local current_bytes new_total reset_date entry
  current_bytes="$(usage_get_bytes "$user")"
  entry="$(grep "^${user}:" "$USAGE_DB" 2>/dev/null | head -n1 || true)"
  if [[ -n "$entry" ]]; then
    reset_date="$(echo "$entry" | cut -d: -f3)"
  else
    reset_date="$(_next_month_first_day)"
    [[ -z "$reset_date" ]] && reset_date="$(date +%Y-%m-%d)"
  fi
  new_total="$((current_bytes + add_bytes))"
  local tmp
  tmp="$(mktemp)"
  track_temp "$tmp"
  grep -v "^${user}:" "$USAGE_DB" > "$tmp" 2>/dev/null || true
  cat "$tmp" > "$USAGE_DB"
  rm -f "$tmp"
  echo "${user}:${new_total}:${reset_date}" >> "$USAGE_DB"
}

usage_check_limit() {
  local user="$1"
  local limit_entry max_gb bytes_used
  limit_entry="$(limits_get "$user")"
  max_gb="$(echo "$limit_entry" | cut -d: -f3)"
  [[ "$max_gb" =~ ^[0-9]+$ ]] || max_gb="$DEFAULT_MAX_GB"
  bytes_used="$(usage_get_bytes "$user")"
  # Bandingkan dalam bytes agar presisi
  local max_bytes
  max_bytes="$((max_gb * 1073741824))"
  if [[ "$bytes_used" -ge "$max_bytes" ]]; then
    return 1
  fi
  return 0
}

# Kumpulkan pemakaian WireGuard otomatis (delta rx+tx per peer).
# Dipanggil setiap enforcement loop. Aman jika wg belum terpasang.
usage_collect_wireguard() {
  limits_init
  command -v wg &>/dev/null || return 0
  [[ -f /etc/wireguard/wg0.conf ]] || return 0
  wg show wg0 dump 2>/dev/null | tail -n +2 | while read -r pubkey _ _ _ rx tx _; do
    [[ -z "$pubkey" ]] && continue
    [[ "$rx" =~ ^[0-9]+$ ]] || continue
    [[ "$tx" =~ ^[0-9]+$ ]] || continue
    # Petakan pubkey -> nama client via wg0.conf (blok ### Client: <nama>)
    local cname=""
    cname="$(awk -v k="$pubkey" '
      /^### Client: / { name=$3 }
      $1=="PublicKey" && $3==k { print name; exit }
    ' /etc/wireguard/wg0.conf 2>/dev/null || true)"
    [[ -z "$cname" ]] && continue
    local total=$((rx + tx))
    local last="0"
    last="$(grep "^${cname}:" "$USAGE_LAST_DB" 2>/dev/null | cut -d: -f2 | head -n1 || true)"
    [[ "$last" =~ ^[0-9]+$ ]] || last="0"
    local delta=0
    if [[ "$total" -ge "$last" ]]; then
      delta=$((total - last))
    else
      # Counter reset (reboot/service restart): anggap total saat ini sebagai delta
      delta="$total"
    fi
    if [[ "$delta" -gt 0 ]]; then
      usage_add_bytes "$cname" "$delta"
    fi
    # Simpan counter terakhir
    local tmp
    tmp="$(mktemp)"
    track_temp "$tmp"
    grep -v "^${cname}:" "$USAGE_LAST_DB" > "$tmp" 2>/dev/null || true
    cat "$tmp" > "$USAGE_LAST_DB"
    rm -f "$tmp"
    echo "${cname}:${total}" >> "$USAGE_LAST_DB"
  done
}

# ------------------------------------------------------- Session tracking
session_add() {
  local user="$1" ip="$2"
  limits_init
  [[ -z "$user" || -z "$ip" ]] && return 0
  local timestamp
  timestamp="$(date +%s)"
  echo "${user}:${ip}:${timestamp}" >> "$SESSION_DB"
  # Bersihkan session kedaluwarsa (>10 menit)
  local cutoff tmp
  cutoff="$((timestamp - SESSION_WINDOW_DEFAULT))"
  tmp="$(mktemp)"
  track_temp "$tmp"
  awk -F: -v cut="$cutoff" 'NF==3 && $3 >= cut' "$SESSION_DB" > "$tmp" 2>/dev/null || true
  cat "$tmp" > "$SESSION_DB"
  rm -f "$tmp"
}

session_count_ips() {
  local user="$1"
  limits_init
  [[ -f "$SESSION_DB" ]] || { echo "0"; return 0; }
  local cutoff
  cutoff="$(($(date +%s) - SESSION_WINDOW_DEFAULT))"
  grep "^${user}:" "$SESSION_DB" 2>/dev/null | awk -F: -v cut="$cutoff" 'NF==3 && $3 >= cut {print $2}' | sort -u | grep -c . 2>/dev/null || true
}

session_list_ips() {
  local user="$1"
  limits_init
  [[ -f "$SESSION_DB" ]] || return 0
  local cutoff
  cutoff="$(($(date +%s) - SESSION_WINDOW_DEFAULT))"
  grep "^${user}:" "$SESSION_DB" 2>/dev/null | awk -F: -v cut="$cutoff" 'NF==3 && $3 >= cut {print $2}' | sort -u || true
}

# Kumpulkan sesi nyata dari sistem (SSH + WireGuard + Xray access log).
# Dipanggil setiap enforcement loop sebelum cek limit.
limits_collect_sessions() {
  limits_init
  local now cutoff tmp
  now="$(date +%s)"
  cutoff="$((now - SESSION_WINDOW_DEFAULT))"

  # 1. SSH: sesi login aktif via `who` (user + IP remote)
  if command -v who &>/dev/null; then
    who 2>/dev/null | while read -r user _ _ _ ip_rest; do
      [[ -z "$user" ]] && continue
      # Format who: user tty date time (ip). Ambil IP dalam kurung.
      local ip
      ip="$(echo "$ip_rest" | tr -d '()' | awk '{print $NF}')"
      [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
      # Hanya catat user yang ada di limits.db (akun VPN)
      if grep -q "^${user}:" "$LIMITS_DB" 2>/dev/null; then
        echo "${user}:${ip}:${now}" >> "$SESSION_DB"
      fi
    done
  fi

  # 2. Extra SSH: TCP connections to ports 22/143/444 via ss (fallback when who is empty)
  #    Map sshd PID -> user via ps. Only for accounts in limits.db.
  #    Portable awk is used instead of grep -oP (missing on Alpine/minimal RHEL).
  if command -v ss &>/dev/null && command -v ps &>/dev/null; then
    ss -tnp state established 2>/dev/null | grep -E ':22 |:143 |:444 ' | while read -r line; do
      local peer_ip pid user
      peer_ip="$(echo "$line" | awk '{print $5}' | cut -d: -f1)"
      [[ "$peer_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
      pid="$(echo "$line" | awk '{for (i=1; i<=NF; i++) if ($i ~ /^pid=/) { split($i, a, "="); sub(/[^0-9].*$/, "", a[2]); print a[2]; exit }}' 2>/dev/null | head -n1 || true)"
      [[ -z "$pid" ]] && continue
      user="$(ps -o user= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
      [[ -z "$user" ]] && continue
      if grep -q "^${user}:" "$LIMITS_DB" 2>/dev/null; then
        echo "${user}:${peer_ip}:${now}" >> "$SESSION_DB"
      fi
    done
  fi

  # 3. WireGuard: endpoint aktif per peer -> petakan ke nama client
  if command -v wg &>/dev/null && [[ -f /etc/wireguard/wg0.conf ]]; then
    wg show wg0 endpoints 2>/dev/null | while read -r pubkey endpoint; do
      [[ -z "$pubkey" || -z "$endpoint" ]] && continue
      [[ "$endpoint" == "(none)" ]] && continue
      local ep_ip cname
      ep_ip="$(echo "$endpoint" | cut -d: -f1)"
      [[ "$ep_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
      cname="$(awk -v k="$pubkey" '
        /^### Client: / { name=$3 }
        $1=="PublicKey" && $3==k { print name; exit }
      ' /etc/wireguard/wg0.conf 2>/dev/null || true)"
      [[ -z "$cname" ]] && continue
      echo "${cname}:${ep_ip}:${now}" >> "$SESSION_DB"
    done
  fi

  # 4. Xray/V2Ray: access log (when enabled at /var/log/xray/access.log)
  #    Default format: ... from 1.2.3.4:port ... email: <name>
  #    Portable awk/sed instead of grep -oP.
  if [[ -f /var/log/xray/access.log ]]; then
    # Take the last 500 lines within 10 minutes (avoid huge files)
    tail -n 500 /var/log/xray/access.log 2>/dev/null | while read -r line; do
      local ip email
      ip="$(echo "$line" | sed -n 's/.*from \([0-9][0-9.]*\)[: ].*/\1/p' 2>/dev/null | head -n1 || true)"
      email="$(echo "$line" | sed -n 's/.*email: \([^ ]*\).*/\1/p' 2>/dev/null | head -n1 || true)"
      [[ -z "$ip" || -z "$email" ]] && continue
      if grep -q "^${email}:" "$LIMITS_DB" 2>/dev/null; then
        echo "${email}:${ip}:${now}" >> "$SESSION_DB"
      fi
    done
  fi

  # Clean up expired entries + deduplicate (user:ip -> newest timestamp)
  tmp="$(mktemp)"
  track_temp "$tmp"
  awk -F: -v cut="$cutoff" 'NF==3 && $3 >= cut { key=$1":"$2; if ($3 > seen[key]) seen[key]=$3 } END { for (k in seen) print k":"seen[k] }' "$SESSION_DB" > "$tmp" 2>/dev/null || true
  cat "$tmp" > "$SESSION_DB"
  rm -f "$tmp"
}

# ------------------------------------------------------- Suspend enforcement
suspend_add() {
  local user="$1" duration="${2:-$SUSPEND_SECONDS_DEFAULT}"
  limits_init
  [[ "$duration" =~ ^[0-9]+$ ]] || duration="$SUSPEND_SECONDS_DEFAULT"
  local until_epoch
  until_epoch="$(($(date +%s) + duration))"
  local tmp
  tmp="$(mktemp)"
  track_temp "$tmp"
  grep -v "^${user}:" "$SUSPEND_DB" > "$tmp" 2>/dev/null || true
  cat "$tmp" > "$SUSPEND_DB"
  rm -f "$tmp"
  echo "${user}:${until_epoch}" >> "$SUSPEND_DB"
  if declare -f log_warn &>/dev/null; then
    log_warn "$(T "User '$user' suspended for $((duration / 60)) minutes (multi-login)." "User '$user' di-suspend sementara selama $((duration / 60)) menit karena multi-login." "用户 '$user' 因多登录被暂停 $((duration / 60)) 分钟。")"
  else
    echo "[WARN] $(T "User '$user' suspended for $((duration / 60)) minutes (multi-login)." "User '$user' di-suspend sementara selama $((duration / 60)) menit karena multi-login." "用户 '$user' 因多登录被暂停 $((duration / 60)) 分钟。")" >&2
  fi
}

suspend_is_active() {
  local user="$1"
  limits_init
  [[ -f "$SUSPEND_DB" ]] || return 1
  local entry until_epoch now tmp
  entry="$(grep "^${user}:" "$SUSPEND_DB" 2>/dev/null | head -n1 || true)"
  [[ -z "$entry" ]] && return 1
  until_epoch="$(echo "$entry" | cut -d: -f2)"
  [[ "$until_epoch" =~ ^[0-9]+$ ]] || return 1
  now="$(date +%s)"
  if [[ "$now" -lt "$until_epoch" ]]; then
    return 0
  else
    # Masa suspend habis: hapus + bersihkan sesi agar perhitungan fresh
    tmp="$(mktemp)"
    track_temp "$tmp"
    grep -v "^${user}:" "$SUSPEND_DB" > "$tmp" 2>/dev/null || true
    cat "$tmp" > "$SUSPEND_DB"
    rm -f "$tmp"
    suspend_clear_sessions "$user" "silent"
    return 1
  fi
}

suspend_remaining() {
  local user="$1"
  local entry until_epoch now
  entry="$(grep "^${user}:" "$SUSPEND_DB" 2>/dev/null | head -n1 || true)"
  [[ -z "$entry" ]] && { echo "0"; return 0; }
  until_epoch="$(echo "$entry" | cut -d: -f2)"
  now="$(date +%s)"
  if [[ "$now" -lt "$until_epoch" ]]; then
    echo "$((until_epoch - now))"
  else
    echo "0"
  fi
}

suspend_clear_sessions() {
  local user="$1" mode="${2:-}"
  # Remove every session of the user from the database so the next IP count is fresh
  if [[ -f "$SESSION_DB" ]]; then
    local tmp
    tmp="$(mktemp)"
    track_temp "$tmp"
    grep -v "^${user}:" "$SESSION_DB" > "$tmp" 2>/dev/null || true
    cat "$tmp" > "$SESSION_DB"
    rm -f "$tmp"
  fi
  # Kill the user's active system connections (SSH accounts)
  if id "$user" &>/dev/null; then
    pkill -u "$user" 2>/dev/null || true
  fi
  if [[ "$mode" != "silent" ]]; then
    if declare -f log_info &>/dev/null; then
      log_info "$(T "All sessions of user '$user' were cleared." "Semua sesi user '$user' dibersihkan." "用户 '$user' 的所有会话已清除。")"
    fi
  fi
}

# ------------------------------------------------------- Enforcement utama (dipanggil periodik)
limits_enforce_all() {
  limits_init
  [[ -f "$LIMITS_DB" ]] || return 0
  # Collect WireGuard bandwidth + real sessions first
  usage_collect_wireguard || true
  limits_collect_sessions || true

  while IFS=: read -r user max_ip max_gb _rest; do
    [[ -z "$user" ]] && continue
    [[ "$user" =~ ^# ]] && continue
    [[ "$max_ip" =~ ^[0-9]+$ ]] || max_ip="$DEFAULT_MAX_IP"
    [[ "$max_gb" =~ ^[0-9]+$ ]] || max_gb="$DEFAULT_MAX_GB"

    # 1. Skip users still inside their suspend window
    if suspend_is_active "$user"; then
      continue
    fi

    # 2. Check the bandwidth limit
    if ! usage_check_limit "$user"; then
      if declare -f log_warn &>/dev/null; then
        log_warn "$(T "User '$user' exceeded the ${max_gb} GB/month bandwidth limit. Disable manually when needed." "User '$user' melebihi bandwidth limit ${max_gb} GB/bulan. Nonaktifkan manual bila perlu." "用户 '$user' 已超出 ${max_gb} GB/月的带宽限制。如有需要请手动停用。")"
      fi
      continue
    fi

    # 3. Check the IP limit (multi-login)
    local current_ips
    current_ips="$(session_count_ips "$user")"
    [[ "$current_ips" =~ ^[0-9]+$ ]] || current_ips="0"
    if [[ "$current_ips" -gt "$max_ip" ]]; then
      local ip_list
      ip_list="$(session_list_ips "$user" | tr '\n' ' ')"
      if declare -f log_warn &>/dev/null; then
        log_warn "$(T "User '$user' multi-login: $current_ips IPs (limit: $max_ip) [$ip_list]. Auto-suspend 5 min + clear sessions." "User '$user' multi-login: $current_ips IP (limit: $max_ip) [$ip_list]. Auto-suspend 5 menit + clear sesi." "用户 '$user' 多登录：$current_ips 个 IP（限制：$max_ip）[$ip_list]。自动暂停 5 分钟并清除会话。")"
      fi
      suspend_add "$user" "$SUSPEND_SECONDS_DEFAULT"
      suspend_clear_sessions "$user"
    fi
  done < "$LIMITS_DB"
}

# ------------------------------------------------------- Systemd monitor service
limits_install_monitor_service() {
  if declare -f log_step &>/dev/null; then
    log_step "$(T "Installing the wrwb Store limit monitor service (checks every 60 seconds)..." "Memasang layanan monitor limit wrwb Store (cek setiap 60 detik)..." "正在安装由 wrwb Store 打造的限制监控服务（每 60 秒检查一次）...")"
  fi

  local repo_lib_dir="$SCRIPT_DIR/lib"
  # Fallback: cari lib di lokasi umum bila SCRIPT_DIR tidak tersedia (dipanggil manual)
  if [[ ! -d "$repo_lib_dir" ]]; then
    for d in "./lib" "/opt/vpn/lib" "/root/vpn/lib"; do
      if [[ -d "$d" ]]; then
        repo_lib_dir="$d"
        break
      fi
    done
  fi

  mkdir -p /usr/local/share/vpn-libs
  if [[ -d "$repo_lib_dir" ]]; then
    cp -f "$repo_lib_dir/common.sh" /usr/local/share/vpn-libs/common.sh 2>/dev/null || true
    cp -f "$repo_lib_dir/limits.sh" /usr/local/share/vpn-libs/limits.sh 2>/dev/null || true
    chmod 644 /usr/local/share/vpn-libs/common.sh /usr/local/share/vpn-libs/limits.sh 2>/dev/null || true
  fi

  cat > /usr/local/bin/vpn-limits-monitor.sh <<'MONITOR_EOF'
#!/bin/bash
# Monitor limit IP & bandwidth — wrwb Store (cek setiap 60 detik)
source "/usr/local/share/vpn-libs/common.sh" 2>/dev/null || {
  _C_RESET=""; _C_RED=""; _C_GREEN=""; _C_YELLOW=""; _C_BLUE=""; _C_BOLD=""
  log_info() { echo "[INFO] $*"; }
  log_warn() { echo "[WARN] $*" >&2; }
  log_step() { echo "==> $*"; }
  log_success() { echo "[OK] $*"; }
  log_error() { echo "[ERROR] $*" >&2; }
}
source "/usr/local/share/vpn-libs/limits.sh" 2>/dev/null || exit 1

while true; do
  limits_enforce_all 2>/dev/null || true
  sleep 60
done
MONITOR_EOF
  chmod 755 /usr/local/bin/vpn-limits-monitor.sh

  cat > /etc/systemd/system/vpn-limits.service <<'SERVICE_EOF'
[Unit]
Description=VPN Limits Monitor — wrwb Store (IP + Bandwidth Enforcement)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/vpn-limits-monitor.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE_EOF

  systemctl daemon-reload 2>/dev/null || true
  systemctl enable vpn-limits.service >/dev/null 2>&1 || true
  systemctl restart vpn-limits.service 2>/dev/null || true

  if declare -f log_success &>/dev/null; then
    log_success "$(T "Limit monitor service is active (checks every 60 seconds) — wrwb Store." "Layanan monitor limit aktif (cek setiap 60 detik) — wrwb Store." "限制监控服务运行中（每 60 秒检查一次）——由 wrwb Store 打造。")"
  fi
}

limits_uninstall_monitor_service() {
  systemctl stop vpn-limits.service 2>/dev/null || true
  systemctl disable vpn-limits.service 2>/dev/null || true
  rm -f /etc/systemd/system/vpn-limits.service /usr/local/bin/vpn-limits-monitor.sh
  rm -rf /usr/local/share/vpn-libs
  systemctl daemon-reload 2>/dev/null || true
}
