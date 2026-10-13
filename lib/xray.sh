#!/bin/bash
#
# lib/xray.sh — Modul Xray-core / V2Ray (VMess, VLESS, Trojan + XTLS/REALITY)
#
# Engine default: Xray-core v26.3.27 (stabil, mendukung XTLS-Vision + REALITY).
# Alternatif: v2ray-core v5.53.0 (dipilih via XRAY_ENGINE=v2ray).
#
# Inbound yang dipasang sekaligus (port default):
#   VMess WS            10001/tcp  (path /vmess)
#   VLESS WS            10002/tcp  (path /vless)
#   Trojan WS           10003/tcp  (path /trojan, password = UUID user)
#   VLESS TCP XTLS      10004/tcp  (flow xtls-rprx-vision)
#   VLESS TCP REALITY   443/tcp    (flow xtls-rprx-vision, SNI microsoft.com)
#
# Setiap user mendapat 1 UUID yang berlaku untuk SEMUA protokol di atas.
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "File ini adalah library. Jangan dijalankan langsung." >&2
  exit 1
fi

XRAY_DIR="/etc/xray"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG="$XRAY_DIR/config.json"
XRAY_PARAMS="$XRAY_DIR/params"
XRAY_ACCOUNTS_DB="$XRAY_DIR/accounts.db"
XRAY_SERVICE="xray"

# Versi stabil (cek terbaru di https://github.com/XTLS/Xray-core/releases
# dan https://github.com/v2fly/v2ray-core/releases). Diperbarui berkala.
XRAY_VERSION_DEFAULT="v26.3.27"
V2RAY_VERSION_DEFAULT="v5.53.0"

# Engine: "xray" (default) atau "v2ray". Bisa dioverride: XRAY_ENGINE=v2ray ./install.sh
XRAY_ENGINE_DEFAULT="xray"

# Port default tiap inbound
XPORT_VMESS_WS="${XPORT_VMESS_WS:-10001}"
XPORT_VLESS_WS="${XPORT_VLESS_WS:-10002}"
XPORT_TROJAN_WS="${XPORT_TROJAN_WS:-10003}"
XPORT_VLESS_XTLS="${XPORT_VLESS_XTLS:-10004}"
XPORT_VLESS_REALITY="${XPORT_VLESS_REALITY:-443}"

# SNI REALITY default: domain besar yang mendukung TLSv1.3 + H2
XREALITY_SNI_DEFAULT="${XREALITY_SNI_DEFAULT:-www.microsoft.com}"
XREALITY_DEST_DEFAULT="${XREALITY_DEST_DEFAULT:-www.microsoft.com:443}"

xray_detect_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) echo "64" ;;
    aarch64|arm64) echo "arm64-v8a" ;;
    armv7l|armhf) echo "arm32-v7a" ;;
    *) die "Arsitektur CPU '$arch' belum didukung otomatis untuk Xray/V2Ray." ;;
  esac
}

install_xray_binary() {
  local engine="${XRAY_ENGINE:-$XRAY_ENGINE_DEFAULT}"
  log_step "Mengunduh dan menyiapkan binary ${engine}..."

  mkdir -p "$XRAY_DIR" /usr/local/bin /usr/local/share/xray
  chmod 700 "$XRAY_DIR"

  local arch_suffix
  arch_suffix="$(xray_detect_arch)"

  local ver url zip_name
  if [[ "$engine" == "v2ray" ]]; then
    ver="${V2RAY_VERSION:-$V2RAY_VERSION_DEFAULT}"
    zip_name="v2ray-linux-${arch_suffix}.zip"
    url="https://github.com/v2fly/v2ray-core/releases/download/${ver}/${zip_name}"
  else
    engine="xray"
    ver="${XRAY_VERSION:-$XRAY_VERSION_DEFAULT}"
    zip_name="Xray-linux-${arch_suffix}.zip"
    url="https://github.com/XTLS/Xray-core/releases/download/${ver}/${zip_name}"
  fi

  local tmp_zip
  tmp_zip="$(mktemp --suffix=.zip)"
  log_info "Mengunduh ${engine} ${ver} (${zip_name}) dari GitHub..."

  if curl -fsSL "$url" -o "$tmp_zip"; then
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    if command -v unzip &>/dev/null; then
      unzip -o -q "$tmp_zip" -d "$tmp_dir"
    elif command -v python3 &>/dev/null; then
      python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$tmp_zip" "$tmp_dir"
    else
      rm -rf "$tmp_dir" "$tmp_zip"
      die "Butuh 'unzip' atau 'python3' untuk mengekstrak ${engine}."
    fi

    # Nama binary di dalam zip: "xray" (Xray) atau "v2ray" (V2Ray)
    local src_bin=""
    for b in "$tmp_dir/xray" "$tmp_dir/v2ray"; do
      if [[ -f "$b" ]]; then
        src_bin="$b"
        break
      fi
    done
    [[ -n "$src_bin" ]] || { rm -rf "$tmp_dir" "$tmp_zip"; die "Binary ${engine} tidak ditemukan di dalam arsip unduhan."; }

    cp -f "$src_bin" "$XRAY_BIN"
    chmod 755 "$XRAY_BIN"

    # Sertakan geoip/geosite bila tersedia di arsip
    for dat in geoip.dat geosite.dat; do
      [[ -f "$tmp_dir/$dat" ]] && cp -f "$tmp_dir/$dat" "/usr/local/share/xray/$dat"
    done

    rm -rf "$tmp_dir" "$tmp_zip"
    log_success "Binary ${engine} ${ver} terpasang di $XRAY_BIN ($("$XRAY_BIN" version 2>/dev/null | head -n1 || echo "$engine"))."
  else
    rm -f "$tmp_zip"
    die "Gagal mengunduh ${engine} ${ver} dari GitHub. Periksa koneksi internet."
  fi

  XRAY_ENGINE="$engine"
  export XRAY_ENGINE
}

xray_gen_uuid() {
  if [[ -x "$XRAY_BIN" ]]; then
    "$XRAY_BIN" uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid
  elif command -v uuidgen &>/dev/null; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    cat /proc/sys/kernel/random/uuid
  fi
}

xray_gen_reality_keys() {
  if [[ -x "$XRAY_BIN" ]]; then
    "$XRAY_BIN" x25519 2>/dev/null || echo ""
  else
    echo ""
  fi
}

xray_setup_server() {
  local pub_ip="${1:-$(get_public_ip)}"
  local engine="${XRAY_ENGINE:-$XRAY_ENGINE_DEFAULT}"

  install_xray_binary

  log_step "Membuat konfigurasi ${XRAY_ENGINE} (VMess/VLESS/Trojan + XTLS/REALITY)..."

  # UUID server (akun pertama / default) + kredensial REALITY
  local server_uuid short_id reality_out priv_key pub_key
  server_uuid="$(xray_gen_uuid)"
  short_id="$(openssl rand -hex 8 2>/dev/null || head -c8 /dev/urandom | od -An -tx1 | tr -d ' \n')"

  reality_out="$(xray_gen_reality_keys)"
  priv_key="$(echo "$reality_out" | awk '/PrivateKey|Private key/ {print $NF}')"
  pub_key="$(echo "$reality_out" | awk '/PublicKey|Public key|Password/ {print $NF}')"
  if [[ -z "$priv_key" || -z "$pub_key" ]]; then
    # Fallback: generate x25519 via openssl (format base64-url aman untuk REALITY)
    priv_key="$(openssl rand -base64 32 | tr '/+' '_-' | tr -d '=')"
    pub_key="$priv_key"
    log_warn "x25519 via binary gagal — memakai kunci darurat. Jalankan ulang bila REALITY bermasalah."
  fi

  # Simpan kredensial inti (dibaca add/remove user)
  cat > "$XRAY_PARAMS" <<EOF
XRAY_ENGINE="$XRAY_ENGINE"
XRAY_PUB_IP="$pub_ip"
XRAY_UUID_SERVER="$server_uuid"
XREALITY_PRIV="$priv_key"
XREALITY_PUB="$pub_key"
XREALITY_SHORTID="$short_id"
XREALITY_SNI="$XREALITY_SNI_DEFAULT"
XREALITY_DEST="$XREALITY_DEST_DEFAULT"
XPORT_VMESS_WS="$XPORT_VMESS_WS"
XPORT_VLESS_WS="$XPORT_VLESS_WS"
XPORT_TROJAN_WS="$XPORT_TROJAN_WS"
XPORT_VLESS_XTLS="$XPORT_VLESS_XTLS"
XPORT_VLESS_REALITY="$XPORT_VLESS_REALITY"
EOF
  chmod 600 "$XRAY_PARAMS"

  cat > "$XRAY_CONFIG" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $XPORT_VMESS_WS,
      "protocol": "vmess",
      "settings": { "clients": [ { "id": "$server_uuid", "alterId": 0 } ] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/vmess" } }
    },
    {
      "listen": "0.0.0.0",
      "port": $XPORT_VLESS_WS,
      "protocol": "vless",
      "settings": { "clients": [ { "id": "$server_uuid" } ], "decryption": "none" },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/vless" } }
    },
    {
      "listen": "0.0.0.0",
      "port": $XPORT_TROJAN_WS,
      "protocol": "trojan",
      "settings": { "clients": [ { "password": "$server_uuid" } ] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/trojan" } }
    },
    {
      "listen": "0.0.0.0",
      "port": $XPORT_VLESS_XTLS,
      "protocol": "vless",
      "settings": { "clients": [ { "id": "$server_uuid", "flow": "xtls-rprx-vision" } ], "decryption": "none" },
      "streamSettings": { "network": "tcp", "security": "none" }
    },
    {
      "listen": "0.0.0.0",
      "port": $XPORT_VLESS_REALITY,
      "protocol": "vless",
      "settings": { "clients": [ { "id": "$server_uuid", "flow": "xtls-rprx-vision" } ], "decryption": "none" },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$XREALITY_DEST_DEFAULT",
          "xver": 0,
          "serverNames": [ "$XREALITY_SNI_DEFAULT" ],
          "privateKey": "$priv_key",
          "shortIds": [ "$short_id" ]
        }
      }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "tag": "direct" } ]
}
EOF
  chmod 600 "$XRAY_CONFIG"

  # Validasi konfigurasi sebelum dijalankan
  "$XRAY_BIN" run -test -config "$XRAY_CONFIG" 2>&1 | tail -n5 || true

  # Systemd service
  cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray/V2Ray Service (VMess/VLESS/Trojan + XTLS/REALITY)
After=network.target

[Service]
Type=simple
User=root
ExecStart=$XRAY_BIN run -config $XRAY_CONFIG
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable xray >/dev/null 2>&1 || true
  systemctl restart xray

  if ! systemctl is-active --quiet xray; then
    log_error "Service xray gagal berjalan. Log:"
    journalctl -u xray -n 20 --no-pager || true
    die "Instalasi ${XRAY_ENGINE} gagal dijalankan."
  fi

  # Buka semua port inbound di firewall
  for p in "$XPORT_VMESS_WS" "$XPORT_VLESS_WS" "$XPORT_TROJAN_WS" "$XPORT_VLESS_XTLS" "$XPORT_VLESS_REALITY"; do
    open_firewall_port "$p" "tcp"
  done

  # Daftarkan akun server default
  touch "$XRAY_ACCOUNTS_DB"
  chmod 600 "$XRAY_ACCOUNTS_DB"
  echo "server-default:${server_uuid}:$(date +%Y-%m-%d)" >> "$XRAY_ACCOUNTS_DB"

  log_success "${XRAY_ENGINE} aktif (VMess/VLESS/Trojan + XTLS-Vision + REALITY)."

  xray_print_links "server-default" "$server_uuid"
}

# ------------------------------------------------------- link generator
# Mencetak link vmess://, vless://, dan trojan:// + QR untuk 1 UUID
xray_print_links() {
  local name="${1:?nama user wajib diisi}"
  local uuid="${2:?uuid wajib diisi}"
  # shellcheck disable=SC1090
  [[ -f "$XRAY_PARAMS" ]] && source "$XRAY_PARAMS"

  local ip="${XRAY_PUB_IP:-$(get_public_ip)}"
  local sni="${XREALITY_SNI:-$XREALITY_SNI_DEFAULT}"
  local pbk="${XREALITY_PUB:-}"
  local sid="${XREALITY_SHORTID:-}"

  # VMess WS (base64 JSON)
  local vmess_json
  vmess_json="$(printf '{"v":"2","ps":"%s-vmess-ws","add":"%s","port":"%s","id":"%s","aid":"0","net":"ws","type":"none","host":"","path":"/vmess","tls":""}' "$name" "$ip" "$XPORT_VMESS_WS" "$uuid")"
  local vmess_link="vmess://$(echo -n "$vmess_json" | base64 -w 0 2>/dev/null || echo -n "$vmess_json" | base64 | tr -d '\n')"

  # VLESS WS
  local vless_ws_link="vless://${uuid}@${ip}:${XPORT_VLESS_WS}?encryption=none&security=none&type=ws&path=%2Fvless#${name}-vless-ws"

  # Trojan WS (password = UUID)
  local trojan_link="trojan://${uuid}@${ip}:${XPORT_TROJAN_WS}?security=none&type=ws&path=%2Ftrojan#${name}-trojan-ws"

  # VLESS TCP XTLS-Vision (tanpa TLS, untuk balik Nginx/CDN TLS di depannya bila perlu)
  local vless_xtls_link="vless://${uuid}@${ip}:${XPORT_VLESS_XTLS}?encryption=none&flow=xtls-rprx-vision&security=none&type=tcp#${name}-vless-xtls"

  # VLESS TCP REALITY + XTLS-Vision (utama: anti-blokir & efisien)
  local vless_reality_link="vless://${uuid}@${ip}:${XPORT_VLESS_REALITY}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${pbk}&sid=${sid}&type=tcp#${name}-vless-reality"

  echo ""
  echo "==================== LINK KONEKSI: $name ===================="
  echo "--- [1] VLESS + TCP + XTLS-Vision + REALITY (UTAMA, paling efisien & anti-blokir)"
  echo "$vless_reality_link"
  echo ""
  echo "--- [2] VLESS + TCP + XTLS-Vision"
  echo "$vless_xtls_link"
  echo ""
  echo "--- [3] VMess + WebSocket"
  echo "$vmess_link"
  echo ""
  echo "--- [4] VLESS + WebSocket"
  echo "$vless_ws_link"
  echo ""
  echo "--- [5] Trojan + WebSocket"
  echo "$trojan_link"
  echo "=============================================================="

  if command -v qrencode &>/dev/null; then
    echo ""
    echo "QR Code (VLESS REALITY — pindai dengan v2rayNG / Streisand / FoXray):"
    qrencode -t ansiutf8 "$vless_reality_link" || true
  fi

  XRAY_LAST_VMESS="$vmess_link"
  XRAY_LAST_REALITY="$vless_reality_link"
  export XRAY_LAST_VMESS XRAY_LAST_REALITY
}

# ------------------------------------------------------- manajemen user
xray_user_exists() {
  local name="$1"
  [[ -f "$XRAY_CONFIG" ]] && grep -q "\"ps\": *\"${name}-" "$XRAY_CONFIG" 2>/dev/null && return 0
  if [[ -f "$XRAY_ACCOUNTS_DB" ]]; then
    grep -q "^${name}:" "$XRAY_ACCOUNTS_DB" && return 0
  fi
  return 1
}

xray_create_user() {
  local name="$1"
  validate_client_name "$name"
  [[ -f "$XRAY_PARAMS" ]] || die "Xray/V2Ray belum terpasang. Jalankan instalasi server dulu."
  # shellcheck disable=SC1090
  source "$XRAY_PARAMS"

  if xray_user_exists "$name"; then
    die "User Xray '$name' sudah terdaftar! Pilih nama lain."
  fi

  local uuid
  uuid="$(xray_gen_uuid)"

  # Sisipkan client baru ke tiap inbound yang punya daftar clients/passwords.
  # Format config ditulis skrip ini sehingga pola JSON-nya dapat diprediksi:
  #   VMess/VLESS : { "id": "<uuid>" ... }  (VLESS+XTLS/REALITY memakai flow)
  #   Trojan      : { "password": "<uuid>" }
  local tmp
  tmp="$(mktemp)"
  cp "$XRAY_CONFIG" "${XRAY_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"

  python3 - "$XRAY_CONFIG" "$tmp" "$uuid" <<'PYEOF'
import json, sys
cfg_path, tmp_path, uuid = sys.argv[1], sys.argv[2], sys.argv[3]
with open(cfg_path) as f:
    cfg = json.load(f)
for inb in cfg.get("inbounds", []):
    proto = inb.get("protocol", "")
    settings = inb.setdefault("settings", {})
    clients = settings.setdefault("clients", [])
    stream = inb.get("streamSettings", {})
    flow = ""
    for c in clients:
        if isinstance(c, dict) and "flow" in c:
            flow = c["flow"]
            break
    if proto in ("vmess", "vless"):
        entry = {"id": uuid}
        if flow:
            entry["flow"] = flow
        if proto == "vmess":
            entry["alterId"] = 0
        clients.append(entry)
    elif proto == "trojan":
        clients.append({"password": uuid})
with open(tmp_path, "w") as f:
    json.dump(cfg, f, indent=2)
PYEOF

  cat "$tmp" > "$XRAY_CONFIG"
  rm -f "$tmp"
  chmod 600 "$XRAY_CONFIG"

  # Validasi & reload service
  "$XRAY_BIN" run -test -config "$XRAY_CONFIG" || die "Konfigurasi Xray baru tidak valid, dibatalkan."
  systemctl restart xray
  systemctl is-active --quiet xray || die "Service xray gagal restart setelah tambah user."

  echo "${name}:${uuid}:$(date +%Y-%m-%d)" >> "$XRAY_ACCOUNTS_DB"

  log_success "User Xray '$name' dibuat (UUID: $uuid)."
  xray_print_links "$name" "$uuid"
}

xray_remove_user() {
  local name="$1"
  validate_client_name "$name"
  [[ -f "$XRAY_PARAMS" ]] || die "Xray/V2Ray belum terpasang."
  # shellcheck disable=SC1090
  source "$XRAY_PARAMS"

  # Ambil UUID user dari database
  local uuid=""
  if [[ -f "$XRAY_ACCOUNTS_DB" ]]; then
    uuid="$(awk -F: -v u="$name" '$1==u {print $2}' "$XRAY_ACCOUNTS_DB" | head -n1)"
  fi
  [[ -n "$uuid" ]] || die "User Xray '$name' tidak ditemukan."

  local tmp
  tmp="$(mktemp)"
  cp "$XRAY_CONFIG" "${XRAY_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"

  python3 - "$XRAY_CONFIG" "$tmp" "$uuid" <<'PYEOF'
import json, sys
cfg_path, tmp_path, uuid = sys.argv[1], sys.argv[2], sys.argv[3]
with open(cfg_path) as f:
    cfg = json.load(f)
for inb in cfg.get("inbounds", []):
    clients = inb.get("settings", {}).get("clients", [])
    inb["settings"]["clients"] = [
        c for c in clients
        if not (isinstance(c, dict) and (c.get("id") == uuid or c.get("password") == uuid))
    ]
with open(tmp_path, "w") as f:
    json.dump(cfg, f, indent=2)
PYEOF

  cat "$tmp" > "$XRAY_CONFIG"
  rm -f "$tmp"
  chmod 600 "$XRAY_CONFIG"

  sed -i "/^${name}:/d" "$XRAY_ACCOUNTS_DB"
  systemctl restart xray || true

  log_success "User Xray '$name' berhasil dihapus dari semua inbound."
}

xray_list_users() {
  echo "======================================================================"
  echo -e "${_C_BOLD}DAFTAR USER XRAY/V2RAY${_C_RESET}"
  echo "======================================================================"
  printf "%-18s %-40s %-12s\n" "USERNAME" "UUID" "DIBUAT"
  echo "----------------------------------------------------------------------"

  local count=0
  if [[ -s "$XRAY_ACCOUNTS_DB" ]]; then
    while IFS=: read -r user uuid created _rest; do
      [[ -z "$user" ]] && continue
      printf "%-18s %-40s %-12s\n" "$user" "$uuid" "$created"
      ((count++)) || true
    done < "$XRAY_ACCOUNTS_DB"
  fi

  if [[ "$count" -eq 0 ]]; then
    echo " (Belum ada user yang terdaftar)"
  fi
  echo "----------------------------------------------------------------------"
  echo "Total user: $count"
  echo "Engine: ${XRAY_ENGINE:-xray} | Config: $XRAY_CONFIG"
  echo "======================================================================"
}
