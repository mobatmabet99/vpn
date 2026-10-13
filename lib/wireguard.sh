#!/bin/bash
#
# lib/wireguard.sh — WireGuard core logic (server & client management, trilingual EN/ID/ZH)
# Branding: wrwb Store
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This file is a library. Do not run it directly." >&2
  exit 1
fi

WG_DIR="/etc/wireguard"
WG_CONF="${WG_CONF:-$WG_DIR/wg0.conf}"
CLIENTS_DIR="${CLIENTS_DIR:-$WG_DIR/clients}"

# ----------------------------------------------------------- Inisialisasi Server
wg_init_dirs() {
  mkdir -p "$WG_DIR" "$CLIENTS_DIR"
  chmod 700 "$WG_DIR" "$CLIENTS_DIR"
}

wg_generate_server_keys() {
  wg_init_dirs
  local priv_file="$WG_DIR/server_private.key"
  local pub_file="$WG_DIR/server_public.key"

  if [[ ! -f "$priv_file" || ! -f "$pub_file" ]]; then
    log_info "$(T "Generating a new server keypair..." "Membuat server keypair baru..." "正在生成新的服务器密钥对...")"
    wg genkey | tee "$priv_file" | wg pubkey > "$pub_file"
    chmod 600 "$priv_file"
    chmod 644 "$pub_file"
    log_success "$(T "Server keypair created." "Server keypair berhasil dibuat." "服务器密钥对已创建。")"
  else
    log_info "$(T "Server keypair already exists, reusing it." "Server keypair sudah ada, menggunakan kunci yang sudah tersedia." "服务器密钥对已存在，将重复使用。")"
  fi

  SERVER_PRIV_KEY="$(cat "$priv_file")"
  SERVER_PUB_KEY="$(cat "$pub_file")"
  export SERVER_PRIV_KEY SERVER_PUB_KEY
}

# ----------------------------------------------------------- Config Server
wg_write_server_conf() {
  local port="${1:-$SERVER_PORT}"
  local iface="${2:-$NET_IFACE}"
  local srv_v4="${3:-10.66.66.1/24}"
  local srv_v6="${4:-fd42:42:42::1/64}"

  log_step "$(T "Writing server config to $WG_CONF..." "Menulis konfigurasi server di $WG_CONF..." "正在将服务器配置写入 $WG_CONF...")"

  # Back up the old config when present
  if [[ -f "$WG_CONF" ]]; then
    local bak="$WG_CONF.bak.$(date +%Y%m%d%H%M%S)"
    cp "$WG_CONF" "$bak"
    log_info "$(T "Old config backed up to $bak" "Backup konfigurasi lama disimpan ke $bak" "旧配置已备份到 $bak")"
  fi

  cat > "$WG_CONF" <<EOF
[Interface]
Address = $srv_v4, $srv_v6
ListenPort = $port
PrivateKey = $SERVER_PRIV_KEY
SaveConfig = false
# MTU 1420 = 1500 - 80 byte overhead WireGuard (mencegah fragmentasi & lambat)
MTU = 1420

# NAT & Routing: otomatis diterapkan saat wg0 UP, dibersihkan saat DOWN
PostUp = iptables -I FORWARD -i %i -j ACCEPT; iptables -I FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -I POSTROUTING -o $iface -j MASQUERADE; ip6tables -I FORWARD -i %i -j ACCEPT; ip6tables -I FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; ip6tables -t nat -I POSTROUTING -o $iface -j MASQUERADE 2>/dev/null || true
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -o $iface -j MASQUERADE; ip6tables -D FORWARD -i %i -j ACCEPT; ip6tables -D FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; ip6tables -t nat -D POSTROUTING -o $iface -j MASQUERADE 2>/dev/null || true

### CLIENTS_START
EOF

  chmod 600 "$WG_CONF"
  log_success "$(T "WireGuard server config written." "Konfigurasi server WireGuard berhasil ditulis." "WireGuard 服务器配置已写入。")"
}

# ----------------------------------------------------------- Systemd Service
wg_enable_and_start() {
  log_step "$(T "Enabling and starting WireGuard (wg-quick@wg0)..." "Mengaktifkan dan menjalankan layanan WireGuard (wg-quick@wg0)..." "正在启用并启动 WireGuard 服务（wg-quick@wg0）...")"
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable wg-quick@wg0 >/dev/null 2>&1 || true
  systemctl restart wg-quick@wg0

  if systemctl is-active --quiet wg-quick@wg0; then
    log_success "$(T "wg-quick@wg0 is active and running normally." "Layanan wg-quick@wg0 aktif dan berjalan normal." "wg-quick@wg0 服务运行中，一切正常。")"
  else
    log_error "$(T "wg-quick@wg0 failed to start. Systemd log:" "Layanan wg-quick@wg0 gagal berjalan. Log systemd:" "wg-quick@wg0 启动失败。Systemd 日志：")"
    journalctl -u wg-quick@wg0 -n 20 --no-pager || true
    die "$(T "WireGuard failed to start." "Instalasi WireGuard gagal dijalankan." "WireGuard 启动失败。")"
  fi
}

wg_reload_config() {
  if systemctl is-active --quiet wg-quick@wg0; then
    # Muat ulang tanpa memutus koneksi (strip FILE konfigurasi, bukan nama interface)
    if command -v wg-quick &>/dev/null; then
      wg syncconf wg0 <(wg-quick strip "$WG_CONF" 2>/dev/null) 2>/dev/null || {
        systemctl restart wg-quick@wg0
      }
    else
      systemctl restart wg-quick@wg0
    fi
  fi
}

# ----------------------------------------------------------- IP Allocator
# Mencari IP host berikutnya di subnet 10.66.66.0/24 (mulai dari 2 s/d 254)
wg_get_next_ip() {
  local base_v4="10.66.66"
  local base_v6="fd42:42:42"

  local used_ips=()
  if [[ -f "$WG_CONF" ]]; then
    # Ambil semua octet terakhir dari AllowedIPs = 10.66.66.X/32
    while IFS= read -r line; do
      if [[ "$line" =~ 10\.66\.66\.([0-9]+) ]]; then
        used_ips+=("${BASH_REMATCH[1]}")
      fi
    done < "$WG_CONF"
  fi

  local next_host=0
  for ((i=2; i<=254; i++)); do
    local found=0
    for u in "${used_ips[@]}"; do
      if [[ "$u" -eq "$i" ]]; then
        found=1
        break
      fi
    done
    if [[ "$found" -eq 0 ]]; then
      next_host="$i"
      break
    fi
  done

  if [[ "$next_host" -eq 0 ]]; then
    die "$(T "Subnet 10.66.66.0/24 is full (253 clients registered). No IP available." "Subnet 10.66.66.0/24 penuh (253 client terdaftar). Tidak ada IP tersedia." "子网 10.66.66.0/24 已满（已注册 253 个客户端）。没有可用 IP。")"
  fi

  CLIENT_IPV4="${base_v4}.${next_host}"
  CLIENT_IPV6="${base_v6}::${next_host}"
  export CLIENT_IPV4 CLIENT_IPV6
}

# ----------------------------------------------------------- Client helpers
wg_client_exists() {
  local name="$1"
  if [[ -f "$WG_CONF" ]] && grep -q "^### Client: ${name}\$" "$WG_CONF"; then
    return 0
  fi
  if [[ -d "$CLIENTS_DIR/$name" ]]; then
    return 0
  fi
  return 1
}

wg_create_client() {
  local name="$1"
  validate_client_name "$name"

  if wg_client_exists "$name"; then
    die "$(T "A client named '$name' is already registered! Pick another name." "Client dengan nama '$name' sudah terdaftar! Pilih nama lain." "名为 '$name' 的客户端已存在！请选择其他名称。")"
  fi

  wg_get_next_ip
  log_info "$(T "Allocated IP for client '$name': IPv4=$CLIENT_IPV4, IPv6=$CLIENT_IPV6" "Alokasi IP untuk client '$name': IPv4=$CLIENT_IPV4, IPv6=$CLIENT_IPV6" "已为客户端 '$name' 分配 IP：IPv4=$CLIENT_IPV4，IPv6=$CLIENT_IPV6")"

  # Buat direktori client
  local c_dir="$CLIENTS_DIR/$name"
  mkdir -p "$c_dir"
  chmod 700 "$c_dir"

  # Generate Client Keys & Pre-Shared Key (PSK untuk quantum-resistance)
  local priv_key pub_key psk
  priv_key="$(wg genkey)"
  pub_key="$(echo "$priv_key" | wg pubkey)"
  psk="$(wg genpsk)"

  echo "$priv_key" > "$c_dir/private.key"; chmod 600 "$c_dir/private.key"
  echo "$pub_key"  > "$c_dir/public.key";  chmod 644 "$c_dir/public.key"
  echo "$psk"      > "$c_dir/preshared.key"; chmod 600 "$c_dir/preshared.key"

  # Tambahkan Peer ke wg0.conf server
  cat >> "$WG_CONF" <<EOF

### Client: $name
[Peer]
PublicKey = $pub_key
PresharedKey = $psk
AllowedIPs = ${CLIENT_IPV4}/32, ${CLIENT_IPV6}/128
### End: $name
EOF

  # Tambahkan secara dinamis ke interface berjalan jika wg aktif
  if systemctl is-active --quiet wg-quick@wg0; then
    wg set wg0 peer "$pub_key" \
      preshared-key <(echo "$psk") \
      allowed-ips "${CLIENT_IPV4}/32,${CLIENT_IPV6}/128" 2>/dev/null || {
      wg_reload_config
    }
  fi

  # Buat file konfigurasi client .conf
  local conf_file="$c_dir/${name}.conf"
  local dns_list="${SERVER_DNS:-1.1.1.1, 1.0.0.1}"
  local endpoint="${SERVER_PUB_IP}:${SERVER_PORT}"

  cat > "$conf_file" <<EOF
[Interface]
PrivateKey = $priv_key
Address = ${CLIENT_IPV4}/32, ${CLIENT_IPV6}/128
DNS = $dns_list
MTU = 1420

[Peer]
PublicKey = $SERVER_PUB_KEY
PresharedKey = $psk
Endpoint = $endpoint
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
  chmod 600 "$conf_file"

  # Generate QR code PNG jika qrencode mendukung
  local png_file="$c_dir/${name}.png"
  qrencode -t png -o "$png_file" < "$conf_file" 2>/dev/null || true

  log_success "$(T "Client '$name' added!" "Client '$name' berhasil ditambahkan!" "客户端 '$name' 添加成功！")"
  log_info "$(T "Config file : $conf_file" "File konfigurasi : $conf_file" "配置文件：$conf_file")"
  [[ -f "$png_file" ]] && log_info "$(T "QR code image : $png_file" "QR code gambar   : $png_file" "二维码图片：$png_file")"

  LAST_CLIENT_CONF="$conf_file"
  LAST_CLIENT_PNG="$png_file"
  export LAST_CLIENT_CONF LAST_CLIENT_PNG
}

wg_show_client_qr() {
  local conf_file="$1"
  [[ -f "$conf_file" ]] || return 1
  echo ""
  echo "==================== $(T "SCAN QR CODE (FOR PHONES / TABLETS)" "SCAN QR CODE (UNTUK HP / TABLET)" "扫描二维码（用于手机/平板）") ===================="
  qrencode -t ansiutf8 < "$conf_file" 2>/dev/null || {
    log_warn "$(T "Cannot render the ANSI QR code in this terminal. Use the config file directly." "Tidak dapat menampilkan QR ANSI di terminal. Gunakan file konfigurasi langsung." "无法在此终端显示 ANSI 二维码。请直接使用配置文件。")"
  }
  echo "=========================================================================="
  echo ""
}

wg_remove_client() {
  local name="$1"
  validate_client_name "$name"

  if ! wg_client_exists "$name"; then
    die "$(T "Client '$name' was not found." "Client '$name' tidak ditemukan." "未找到客户端 '$name'。")"
  fi

  log_step "$(T "Removing client '$name'..." "Menghapus client '$name'..." "正在删除客户端 '$name'...")"

  # Ambil public key client jika tersimpan di file atau di wg0.conf
  local pub_key=""
  if [[ -f "$CLIENTS_DIR/$name/public.key" ]]; then
    pub_key="$(cat "$CLIENTS_DIR/$name/public.key")"
  fi

  # Hapus dari runtime wg0 jika interface aktif
  if [[ -n "$pub_key" ]] && systemctl is-active --quiet wg-quick@wg0; then
    wg set wg0 peer "$pub_key" remove 2>/dev/null || true
  fi

  # Hapus blok client dari wg0.conf
  # Hapus dari '### Client: <name>' sampai '### End: <name>'
  if [[ -f "$WG_CONF" ]]; then
    local tmp_file
    tmp_file="$(mktemp)"
    awk -v client="$name" '
      BEGIN { skip=0 }
      $0 ~ "^### Client: " client "$" { skip=1; next }
      $0 ~ "^### End: " client "$"    { skip=0; next }
      !skip { print }
    ' "$WG_CONF" > "$tmp_file"
    cat "$tmp_file" > "$WG_CONF"
    rm -f "$tmp_file"
  fi

  # Arsipkan / hapus folder client
  local c_dir="$CLIENTS_DIR/$name"
  if [[ -d "$c_dir" ]]; then
    rm -rf "$c_dir"
  fi

  # Re-apply when wg0 is running
  wg_reload_config

  log_success "$(T "Client '$name' removed." "Client '$name' berhasil dihapus." "客户端 '$name' 已删除。")"
}

wg_list_clients() {
  [[ -f "$WG_CONF" ]] || die "$(T "WireGuard is not configured yet. Run install.sh first." "WireGuard belum terkonfigurasi. Jalankan install.sh dulu." "WireGuard 尚未配置。请先运行 install.sh。")"

  echo "======================================================================"
  echo -e "${_C_BOLD}$(T "REGISTERED WIREGUARD CLIENTS" "DAFTAR CLIENT WIREGUARD TERDAFTAR" "已注册的 WIREGUARD 客户端列表")${_C_RESET}"
  echo "======================================================================"
  printf "%-18s %-20s %-25s\n" "CLIENT NAME" "IP ADDRESS" "STATUS / FILES"
  echo "----------------------------------------------------------------------"

  local count=0
  local in_block=0 current_client="" current_ip=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^###\ Client:\ (.*)$ ]]; then
      in_block=1
      current_client="${BASH_REMATCH[1]}"
      current_ip=""
    elif [[ "$in_block" -eq 1 && "$line" =~ ^AllowedIPs\ =\ (.*)$ ]]; then
      current_ip="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^###\ End:\ (.*)$ ]]; then
      local cname="${BASH_REMATCH[1]}"
      local conf_path="$CLIENTS_DIR/$cname/${cname}.conf"
      local status="$(T "conf present" "conf ada" "配置存在")"
      [[ ! -f "$conf_path" ]] && status="$(T "conf missing" "conf hilang" "配置缺失")"
      printf "%-18s %-20s %-25s\n" "$cname" "${current_ip:-N/A}" "$status"
      ((count++)) || true
      in_block=0
      current_client=""
    fi
  done < "$WG_CONF"

  if [[ "$count" -eq 0 ]]; then
    echo " ($(T "No clients registered yet" "Belum ada client yang terdaftar" "暂无已注册的客户端"))"
  fi
  echo "----------------------------------------------------------------------"
  echo "$(T "Total clients: $count" "Total client: $count" "客户端总数：$count")"
  echo "======================================================================"
}
