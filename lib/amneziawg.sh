#!/bin/bash
#
# lib/amneziawg.sh — AmneziaWG server (DPI-resistant WireGuard fork, trilingual EN/ID/ZH)
# Branding: wrwb Store
#
# Strategy (v5): AmneziaWG is installed as a SECOND UDP interface (awg0, port 51821)
# alongside the pure WireGuard foundation (wg0, port 51820, untouched).
# Binary path: try amneziawg-go userspace binary first (portable, no DKMS),
# fallback to distro amneziawg package (PPA, kernel module, apt only).
# If neither is available, AmneziaWG setup is SKIPPED softly (pure WG still works).
#
# Config: /etc/amneziawg/awg0.conf (wg-quick compatible) + clients in
# /etc/amneziawg/clients/<name>/<name>.conf (+ .png QR when qrencode present).
# Junk/obfuscation params (Jc/Jmin/Jmax/S1..S2/H1..H4) are auto-generated per
# server and copied into every client conf (AmneziaWG official app compatible).
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This file is a library. Do not run it directly." >&2
  exit 1
fi

AWG_DIR="/etc/amneziawg"
AWG_CONF="$AWG_DIR/awg0.conf"
AWG_CLIENTS_DIR="$AWG_DIR/clients"
AWG_PARAMS="$AWG_DIR/params"
AWG_BIN_CANDIDATES="/usr/local/bin/amneziawg-go /usr/bin/amneziawg-go /usr/bin/awg"
AWG_PORT="${AWG_PORT:-51821}"
AWG_SUBNET_V4="${AWG_SUBNET_V4:-10.66.77.0/24}"
AWG_SERVER_V4="${AWG_SERVER_V4:-10.66.77.1/24}"
AWG_SUBNET_V6="${AWG_SUBNET_V6:-fd42:42:77::/64}"
AWG_SERVER_V6="${AWG_SERVER_V6:-fd42:42:77::1/64}"

awg_find_bin() {
  local b
  for b in $AWG_BIN_CANDIDATES; do
    if [[ -x "$b" ]]; then
      echo "$b"
      return 0
    fi
  done
  if command -v awg-quick &>/dev/null; then
    echo "awg-quick"
    return 0
  fi
  # NOTE: plain `wg-quick` intentionally NOT accepted here — it drives the pure
  # WireGuard stack (wg0), not AmneziaWG. Falling back to it would silently start
  # a second plain-WG interface while claiming "AmneziaWG active".
  return 1
}

awg_detect_goarch() {
  local arch
  arch="$(uname -m)"
  # NOTE: only consumed by the OPT-IN GitHub attempt (AWG_GO_TRY_GITHUB=1).
  # amneziawg-go has no release binaries (tags only, as of 2026) so arch names
  # here are best-effort guesses for future assets — the PPA path is primary.
  case "$arch" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armhf|armv7*) echo "arm" ;;
    *) echo "" ;;
  esac
}

# Try to install amneziawg-go userspace binary from GitHub (best-effort).
# Returns 0 when a working AWG binary exists afterwards, 1 otherwise.
awg_install_binary() {
  if awg_find_bin >/dev/null 2>&1; then
    return 0
  fi
  detect_os
  # 1) Try distro package (PPA amnezia/ppa, Ubuntu/Debian apt only)
  if [[ "$PKG_MGR" == "apt" ]]; then
    log_info "$(T "Trying distro AmneziaWG package (ppa:amnezia/ppa)..." "Mencoba paket AmneziaWG distro (ppa:amnezia/ppa)..." "正在尝试发行版 AmneziaWG 软件包 (ppa:amnezia/ppa)...")"
    if command -v add-apt-repository &>/dev/null || apt-get install -y software-properties-common 2>/dev/null; then
      add-apt-repository -y ppa:amnezia/ppa 2>/dev/null || true
      apt-get update -y 2>/dev/null || true
      apt-get install -y amneziawg 2>/dev/null || true
    fi
    if awg_find_bin >/dev/null 2>&1; then
      log_success "$(T "AmneziaWG installed via distro package." "AmneziaWG terinstal via paket distro." "AmneziaWG 已通过发行版软件包安装。")"
      return 0
    fi
  fi
  # 2) Try amneziawg-go static binary from GitHub releases (best-effort).
  # NOTE: amneziawg-go publishes TAGS but (as of 2026) NO release binaries —
  # both URL guesses usually 404. Keep it cheap: skip the download attempt when
  # the caller pins a version that never had binaries, unless AWG_GO_TRY_GITHUB=1.
  # Build-from-source remains a manual step (see warning in awg_setup_server).
  local goarch
  goarch="$(awg_detect_goarch)"
  if [[ -n "$goarch" && "${AWG_GO_TRY_GITHUB:-0}" == "1" ]]; then
    local ver="${AWG_GO_VERSION:-v1.0.0}"
    local tmp
    # Portable mktemp (Alpine/busybox lacks --suffix, plain file is fine here).
    tmp="$(mktemp)"
    track_temp "$tmp"
    log_info "$(T "Trying amneziawg-go binary ($goarch) from GitHub..." "Mencoba binary amneziawg-go ($goarch) dari GitHub..." "正在从 GitHub 尝试 amneziawg-go 可执行文件 ($goarch)...")"
    local url
    for url in \
      "https://github.com/amnezia-vpn/amneziawg-go/releases/download/${ver}/amneziawg-go-linux-${goarch}" \
      "https://github.com/amnezia-vpn/amneziawg-go/releases/download/${ver}/amneziawg-${goarch}" \
    ; do
      if curl -fsSL --retry 2 --connect-timeout 20 "$url" -o "$tmp" 2>/dev/null && head -c4 "$tmp" 2>/dev/null | grep -q "ELF"; then
        cp -f "$tmp" /usr/local/bin/amneziawg-go
        chmod 755 /usr/local/bin/amneziawg-go
        rm -f "$tmp"
        log_success "$(T "amneziawg-go installed at /usr/local/bin/amneziawg-go" "amneziawg-go terinstal di /usr/local/bin/amneziawg-go" "amneziawg-go 已安装到 /usr/local/bin/amneziawg-go")"
        return 0
      fi
    done
    rm -f "$tmp"
  fi
  return 1
}

awg_gen_obfuscation() {
  # Jc: junk packet count, Jmin/Jmax: junk size range, S1/S2: junk size,
  # H1-H4: handshake header obfuscation (magic numbers, official client compatible)
  AWG_JC="${AWG_JC:-$((RANDOM % 8 + 3))}"
  AWG_JMIN="${AWG_JMIN:-50}"
  AWG_JMAX="${AWG_JMAX:-1000}"
  AWG_S1="${AWG_S1:-$((RANDOM % 400 + 100))}"
  AWG_S2="${AWG_S2:-$((RANDOM % 400 + 100))}"
  AWG_H1="${AWG_H1:-$((RANDOM % 900000000 + 100000000))}"
  AWG_H2="${AWG_H2:-$((RANDOM % 900000000 + 100000000))}"
  AWG_H3="${AWG_H3:-$((RANDOM % 900000000 + 100000000))}"
  AWG_H4="${AWG_H4:-$((RANDOM % 900000000 + 100000000))}"
  export AWG_JC AWG_JMIN AWG_JMAX AWG_S1 AWG_S2 AWG_H1 AWG_H2 AWG_H3 AWG_H4
}

awg_init_dirs() {
  mkdir -p "$AWG_DIR" "$AWG_CLIENTS_DIR"
  chmod 700 "$AWG_DIR" "$AWG_CLIENTS_DIR"
}

# Setup AmneziaWG server (soft-fail: returns 0 with warning when binary unavailable)
# Args: <pub_ip> [port] [iface]
awg_setup_server() {
  local pub_ip="${1:-$(get_public_ip)}"
  local port="${2:-$AWG_PORT}"
  local iface="${3:-$(get_default_iface)}"

  check_port_free "$port" "udp" "AmneziaWG" --soft || true

  if ! awg_install_binary; then
    log_warn "$(T "AmneziaWG binary unavailable — skipping AmneziaWG (pure WireGuard still works)." "Binary AmneziaWG tidak tersedia — AmneziaWG dilewati (WireGuard murni tetap jalan)." "AmneziaWG 可执行文件不可用 — 已跳过 AmneziaWG（原生 WireGuard 仍可用）。")"
    log_warn "$(T "Manual (Ubuntu/Debian): add-apt-repository ppa:amnezia/ppa && apt install amneziawg, then re-run install." "Manual (Ubuntu/Debian): add-apt-repository ppa:amnezia/ppa && apt install amneziawg, lalu jalankan ulang instalasi." "手动（Ubuntu/Debian）：add-apt-repository ppa:amnezia/ppa && apt install amneziawg，然后重新运行安装。")"
    log_warn "$(T "Manual (other distros): build amneziawg-go from source (go install github.com/amnezia-vpn/amneziawg-go@latest), then re-run install." "Manual (distro lain): build amneziawg-go dari source (go install github.com/amnezia-vpn/amneziawg-go@latest), lalu jalankan ulang instalasi." "手动（其他发行版）：从源码构建 amneziawg-go（go install github.com/amnezia-vpn/amneziawg-go@latest），然后重新运行安装。")"
    return 0
  fi

  awg_init_dirs
  awg_gen_obfuscation

  # Reuse wg tooling for key generation (same Curve25519)
  require_cmd wg
  local priv_file="$AWG_DIR/server_private.key"
  local pub_file="$AWG_DIR/server_public.key"
  if [[ ! -f "$priv_file" || ! -f "$pub_file" ]]; then
    wg genkey | tee "$priv_file" | wg pubkey > "$pub_file"
    chmod 600 "$priv_file"
    chmod 644 "$pub_file"
  fi
  local srv_priv srv_pub
  srv_priv="$(cat "$priv_file")"
  srv_pub="$(cat "$pub_file")"

  if [[ -f "$AWG_CONF" ]]; then
    cp "$AWG_CONF" "$AWG_CONF.bak.$(date +%Y%m%d%H%M%S)"
  fi

  cat > "$AWG_CONF" <<EOF
[Interface]
Address = $AWG_SERVER_V4, $AWG_SERVER_V6
ListenPort = $port
PrivateKey = $srv_priv
SaveConfig = false
MTU = 1420
# AmneziaWG obfuscation (server dialect — copied to every client conf)
Jc = $AWG_JC
Jmin = $AWG_JMIN
Jmax = $AWG_JMAX
S1 = $AWG_S1
S2 = $AWG_S2
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4

PostUp = iptables -I FORWARD -i %i -j ACCEPT; iptables -I FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -I POSTROUTING -o $iface -j MASQUERADE; ip6tables -I FORWARD -i %i -j ACCEPT 2>/dev/null || true
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -o $iface -j MASQUERADE; ip6tables -D FORWARD -i %i -j ACCEPT 2>/dev/null || true

### CLIENTS_START
EOF
  chmod 600 "$AWG_CONF"

  cat > "$AWG_PARAMS" <<EOF
AWG_PUB_IP="$pub_ip"
AWG_PORT="$port"
AWG_PUB_KEY="$srv_pub"
AWG_IFACE="$iface"
AWG_JC="$AWG_JC"
AWG_JMIN="$AWG_JMIN"
AWG_JMAX="$AWG_JMAX"
AWG_S1="$AWG_S1"
AWG_S2="$AWG_S2"
AWG_H1="$AWG_H1"
AWG_H2="$AWG_H2"
AWG_H3="$AWG_H3"
AWG_H4="$AWG_H4"
EOF
  chmod 600 "$AWG_PARAMS"

  # Try awg-quick@awg0 first (kernel module / amneziawg package),
  # fallback: generic unit (works with amneziawg-go userspace binary symlinked as awg-quick,
  # or plain wg-quick — config format is wg-quick compatible). Resolve binary lazily:
  # /usr/bin may not exist on all distros (NixOS, some minimal images use /run/current-system/...
  # or /usr/local/bin instead).
  local awg_unit="" _wq_bin=""
  if command -v awg-quick &>/dev/null; then
    _wq_bin="$(command -v awg-quick)"
  elif command -v wg-quick &>/dev/null; then
    _wq_bin="$(command -v wg-quick)"
  else
    _wq_bin="/usr/bin/wg-quick"
  fi
  if systemctl cat awg-quick@.service &>/dev/null || command -v awg-quick &>/dev/null; then
    mkdir -p /etc/systemd/system/awg-quick@awg0.service.d 2>/dev/null || true
    awg_unit="awg-quick@awg0"
    # When awg-quick template missing, create a minimal unit pointing at $AWG_CONF
    if ! systemctl cat awg-quick@.service &>/dev/null; then
      cat > /etc/systemd/system/awg-quick@awg0.service <<UNIT_EOF
[Unit]
Description=AmneziaWG via awg-quick for %i (v5, auto-start on boot)
After=network.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$_wq_bin up awg0
ExecStop=$_wq_bin down awg0
[Install]
WantedBy=multi-user.target
UNIT_EOF
    fi
  else
    # Generic unit using wg-quick with explicit config path
    cat > /etc/systemd/system/awg0.service <<EOF
[Unit]
Description=AmneziaWG interface awg0 via wg-quick (v5, auto-start on boot)
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$_wq_bin up $AWG_CONF
ExecStop=$_wq_bin down $AWG_CONF

[Install]
WantedBy=multi-user.target
EOF
    awg_unit="awg0"
  fi

  open_firewall_port "$port" "udp" "AmneziaWG"
  svc_restart "$awg_unit"

  log_success "$(T "AmneziaWG active — $pub_ip:$port/udp (interface awg0, $awg_unit)." "AmneziaWG aktif — $pub_ip:$port/udp (interface awg0, $awg_unit)." "AmneziaWG 运行中 — $pub_ip:$port/udp（接口 awg0，$awg_unit）。")"

  summary_block "AmneziaWG server (v5)" <<EOF
AmneziaWG server (DPI-resistant WireGuard fork, v5)
Endpoint   : $pub_ip:$port/udp (interface awg0, unit $awg_unit)
Subnet     : $AWG_SUBNET_V4 + $AWG_SUBNET_V6
Obfuscation: Jc=$AWG_JC Jmin=$AWG_JMIN Jmax=$AWG_JMAX S1=$AWG_S1 S2=$AWG_S2 H1=$AWG_H1 H2=$AWG_H2 H3=$AWG_H3 H4=$AWG_H4
Clients    : import /etc/amneziawg/clients/<name>/<name>.conf into AmneziaVPN / AmneziaWG app
Pure WG    : untouched on wg0 $pub_ip:${SERVER_PORT:-51820}/udp (foundation, fastest)
Re-show    : cat $VPN_SUMMARY_FILE
EOF
}

awg_get_next_ip() {
  # Derive bases from AWG_SUBNET_V4/V6 (single source of truth) instead of
  # hardcoded 10.66.77/fd42:42:77 — custom AWG_SUBNET_V4 env overrides in
  # awg_setup_server would otherwise allocate OUTSIDE the server subnet
  # (client gets .77.x IP while server listens on custom /24 → no traffic).
  local base_v4 base_v6
  base_v4="$(echo "$AWG_SUBNET_V4" | awk -F. '{print $1"."$2"."$3}')"
  base_v6="$(echo "$AWG_SUBNET_V6" | sed 's/::.*//')"
  [[ -n "$base_v4" && -n "$base_v6" ]] || die "$(T "Invalid AmneziaWG subnet config." "Konfigurasi subnet AmneziaWG tidak valid." "AmneziaWG 子网配置无效。")"
  local used=()
  if [[ -f "$AWG_CONF" ]]; then
    while IFS= read -r line; do
      if [[ "$line" =~ ${base_v4//./\\.}\.([0-9]+) ]]; then
        used+=("${BASH_REMATCH[1]}")
      fi
    done < "$AWG_CONF"
  fi
  local next=0
  local i found u
  for ((i=2; i<=254; i++)); do
    found=0
    for u in "${used[@]}"; do
      if [[ "$u" -eq "$i" ]]; then found=1; break; fi
    done
    if [[ "$found" -eq 0 ]]; then next="$i"; break; fi
  done
  [[ "$next" -ne 0 ]] || die "$(T "AmneziaWG subnet full (253 clients)." "Subnet AmneziaWG penuh (253 client)." "AmneziaWG 子网已满（253 个客户端）。")"
  AWG_CLIENT_IPV4="${base_v4}.${next}"
  AWG_CLIENT_IPV6="${base_v6}::${next}"
  export AWG_CLIENT_IPV4 AWG_CLIENT_IPV6
}

awg_client_exists() {
  local name="$1"
  # -F fixed-string: client names are validated ([A-Za-z0-9_-]) but -F makes
  # the intent explicit and immune to future charset changes. No regex chars
  # involved, so the old `\$`-inside-quotes BRE escape was pure noise.
  if [[ -f "$AWG_CONF" ]] && grep -qF "### Client: $name" "$AWG_CONF"; then return 0; fi
  if [[ -d "$AWG_CLIENTS_DIR/$name" ]]; then return 0; fi
  return 1
}

awg_create_client() {
  local name="$1"
  validate_client_name "$name"
  [[ -f "$AWG_PARAMS" ]] || die "$(T "AmneziaWG is not installed yet." "AmneziaWG belum terpasang." "AmneziaWG 尚未安装。")"
  # shellcheck disable=SC1090
  source "$AWG_PARAMS"
  require_cmd wg
  if awg_client_exists "$name"; then
    die "$(T "AmneziaWG client '$name' already exists." "Client AmneziaWG '$name' sudah ada." "AmneziaWG 客户端 '$name' 已存在。")"
  fi
  awg_get_next_ip
  local c_dir="$AWG_CLIENTS_DIR/$name"
  mkdir -p "$c_dir"
  chmod 700 "$c_dir"
  local priv_key pub_key psk
  priv_key="$(wg genkey)"
  pub_key="$(echo "$priv_key" | wg pubkey)"
  psk="$(wg genpsk)"
  echo "$priv_key" > "$c_dir/private.key"; chmod 600 "$c_dir/private.key"
  echo "$pub_key" > "$c_dir/public.key"; chmod 644 "$c_dir/public.key"
  echo "$psk" > "$c_dir/preshared.key"; chmod 600 "$c_dir/preshared.key"

  cat >> "$AWG_CONF" <<EOF

### Client: $name
[Peer]
PublicKey = $pub_key
PresharedKey = $psk
AllowedIPs = ${AWG_CLIENT_IPV4}/32, ${AWG_CLIENT_IPV6}/128
### End: $name
EOF

  # Live-apply when interface is up
  if ip link show awg0 &>/dev/null; then
    wg set awg0 peer "$pub_key" preshared-key <(echo "$psk") allowed-ips "${AWG_CLIENT_IPV4}/32,${AWG_CLIENT_IPV6}/128" 2>/dev/null || true
  fi

  local dns_list="${SERVER_DNS:-1.1.1.1, 1.0.0.1}"
  local endpoint="${AWG_PUB_IP}:${AWG_PORT}"
  local conf_file="$c_dir/${name}.conf"
  cat > "$conf_file" <<EOF
[Interface]
PrivateKey = $priv_key
Address = ${AWG_CLIENT_IPV4}/32, ${AWG_CLIENT_IPV6}/128
DNS = $dns_list
MTU = 1420
Jc = ${AWG_JC}
Jmin = ${AWG_JMIN}
Jmax = ${AWG_JMAX}
S1 = ${AWG_S1}
S2 = ${AWG_S2}
H1 = ${AWG_H1}
H2 = ${AWG_H2}
H3 = ${AWG_H3}
H4 = ${AWG_H4}

[Peer]
PublicKey = ${AWG_PUB_KEY}
PresharedKey = $psk
Endpoint = $endpoint
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
  chmod 600 "$conf_file"
  local png_file="$c_dir/${name}.png"
  qrencode -t png -o "$png_file" < "$conf_file" 2>/dev/null || true

  log_success "$(T "AmneziaWG client '$name' added!" "Client AmneziaWG '$name' ditambahkan!" "AmneziaWG 客户端 '$name' 添加成功！")"
  show_and_save "AmneziaWG client: $name" <<EOF
AmneziaWG client : $name
Endpoint         : $endpoint/udp (DPI-resistant, import into AmneziaVPN app)
Config file      : $conf_file
QR PNG           : ${png_file} (when qrencode available)
Address          : ${AWG_CLIENT_IPV4}/32, ${AWG_CLIENT_IPV6}/128
Obfuscation      : Jc=${AWG_JC} Jmin=${AWG_JMIN} Jmax=${AWG_JMAX} S1=${AWG_S1} S2=${AWG_S2} H1..H4 set
Re-show anytime  : sudo ./show-account.sh $name [--qr] | cat $VPN_SUMMARY_FILE
------ $conf_file ------
$(cat "$conf_file")
EOF
  wg_show_client_qr "$conf_file" || true
}

awg_remove_client() {
  local name="$1"
  validate_client_name "$name"
  if ! awg_client_exists "$name"; then
    die "$(T "AmneziaWG client '$name' not found." "Client AmneziaWG '$name' tidak ditemukan." "未找到 AmneziaWG 客户端 '$name'。")"
  fi
  local pub_key=""
  [[ -f "$AWG_CLIENTS_DIR/$name/public.key" ]] && pub_key="$(cat "$AWG_CLIENTS_DIR/$name/public.key")"
  if [[ -n "$pub_key" ]] && ip link show awg0 &>/dev/null; then
    wg set awg0 peer "$pub_key" remove 2>/dev/null || true
  fi
  if [[ -f "$AWG_CONF" ]]; then
    local tmp_file
    tmp_file="$(mktemp)"
    track_temp "$tmp_file"
    awk -v client="$name" '
      BEGIN { skip=0 }
      $0 ~ "^### Client: " client "$" { skip=1; next }
      $0 ~ "^### End: " client "$"    { skip=0; next }
      !skip { print }
    ' "$AWG_CONF" > "$tmp_file"
    cat "$tmp_file" > "$AWG_CONF"
    rm -f "$tmp_file"
  fi
  rm -rf "$AWG_CLIENTS_DIR/$name"
  log_success "$(T "AmneziaWG client '$name' removed." "Client AmneziaWG '$name' dihapus." "AmneziaWG 客户端 '$name' 已删除。")"
}

awg_remove() {
  log_info "$(T "Removing AmneziaWG..." "Menghapus AmneziaWG..." "正在删除 AmneziaWG...")"
  systemctl stop "awg-quick@awg0" 2>/dev/null || true
  systemctl disable "awg-quick@awg0" 2>/dev/null || true
  systemctl stop "awg0" 2>/dev/null || true
  systemctl disable "awg0" 2>/dev/null || true
  rm -f /etc/systemd/system/awg-quick@awg0.service /etc/systemd/system/awg0.service
  rmdir /etc/systemd/system/awg-quick@awg0.service.d 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
  if [[ -f "$AWG_PARAMS" ]]; then
    # shellcheck disable=SC1090
    source "$AWG_PARAMS" 2>/dev/null || true
    close_firewall_port "${AWG_PORT:-51821}" "udp" || true
  fi
  rm -rf "$AWG_DIR"
  log_success "$(T "AmneziaWG removed." "AmneziaWG dihapus." "AmneziaWG 已删除。")"
}
