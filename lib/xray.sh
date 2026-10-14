#!/bin/bash
#
# lib/xray.sh — Xray-core / V2Ray module (VMess, VLESS, Trojan + XTLS/REALITY, trilingual EN/ID/ZH)
# Branding: wrwb Store
#
# Default engine: Xray-core v26.10.10 (stable, supports XTLS-Vision + REALITY + XHTTP).
# Alternative: v2ray-core v5.53.0 (selected via XRAY_ENGINE=v2ray).
#
# Inbounds installed together (default ports):
#   VMess WS            10001/tcp  (path /vmess)
#   VLESS WS            10002/tcp  (path /vless)
#   Trojan WS           10003/tcp  (path /trojan, password = user UUID)
#   VLESS TCP XTLS      10004/tcp  (flow xtls-rprx-vision)
#   VLESS TCP REALITY   443/tcp    (flow xtls-rprx-vision, SNI microsoft.com)
#   VMess gRPC          10005/tcp  (serviceName VMessGRPC) — v4
#   VLESS gRPC          10006/tcp  (serviceName VLessGRPC) — v4
#   Trojan gRPC         10007/tcp  (serviceName TrojanGRPC) — v4
#   VLESS REALITY gRPC  10008/tcp  (serviceName RealityGRPC, with REALITY) — v4
#   VMess XHTTP         80/tcp     (path /vmess-xhttp) — v4.2
#   VLESS XHTTP         80/tcp     (path /vless-xhttp) — v4.2
#   Trojan XHTTP        80/tcp     (path /trojan-xhttp) — v4.2
#   VLESS REALITY XHTTP 443/tcp    (path /reality-xhttp, with REALITY) — v4.2 🏆 BEST
#
# Each user gets 1 UUID valid for ALL protocols above (13 inbounds total).
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This file is a library. Do not run it directly." >&2
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
# v4: Updated to latest stable with full gRPC support (Oct 2026)
XRAY_VERSION_DEFAULT="v26.10.10"
V2RAY_VERSION_DEFAULT="v5.53.0"

# Engine: "xray" (default) atau "v2ray". Bisa dioverride: XRAY_ENGINE=v2ray ./install.sh
XRAY_ENGINE_DEFAULT="xray"

# Port default tiap inbound
XPORT_VMESS_WS="${XPORT_VMESS_WS:-10001}"
XPORT_VLESS_WS="${XPORT_VLESS_WS:-10002}"
XPORT_TROJAN_WS="${XPORT_TROJAN_WS:-10003}"
XPORT_VLESS_XTLS="${XPORT_VLESS_XTLS:-10004}"
XPORT_VLESS_REALITY="${XPORT_VLESS_REALITY:-443}"

# v4: gRPC ports (efficient, HTTP/2 based, excellent for CDN/reverse proxy)
XPORT_VMESS_GRPC="${XPORT_VMESS_GRPC:-10005}"
XPORT_VLESS_GRPC="${XPORT_VLESS_GRPC:-10006}"
XPORT_TROJAN_GRPC="${XPORT_TROJAN_GRPC:-10007}"
XPORT_VLESS_REALITY_GRPC="${XPORT_VLESS_REALITY_GRPC:-10008}"

# v4.2: XHTTP ports (newest transport, most HTTP-like, best stealth)
# Port 80 shared with path routing, port 443 with fallback to existing REALITY TCP
XPORT_XHTTP_SHARED="${XPORT_XHTTP_SHARED:-80}"
XPORT_VLESS_REALITY_XHTTP="${XPORT_VLESS_REALITY_XHTTP:-443}"

# SNI REALITY default: domain besar yang mendukung TLSv1.3 + H2
XREALITY_SNI_DEFAULT="${XREALITY_SNI_DEFAULT:-www.microsoft.com}"
XREALITY_DEST_DEFAULT="${XREALITY_DEST_DEFAULT:-www.microsoft.com:443}"

xray_detect_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) 
      echo "64" 
      ;;
    aarch64|arm64) 
      echo "arm64-v8a" 
      ;;
    armv7l|armhf|armv7*) 
      echo "arm32-v7a" 
      ;;
    armv6l|armv6*) 
      echo "arm32-v6" 
      ;;
    *) 
      log_error "$(T "CPU architecture '$arch' is not supported for Xray/V2Ray auto-install." "Arsitektur CPU '$arch' tidak didukung untuk instalasi otomatis Xray/V2Ray." "CPU 架构 '$arch' 不支持 Xray/V2Ray 自动安装。")"
      log_error "$(T "Supported: x86_64 (amd64), aarch64 (arm64), armv7 (arm32)" "Didukung: x86_64 (amd64), aarch64 (arm64), armv7 (arm32)" "支持：x86_64（amd64）、aarch64（arm64）、armv7（arm32）")"
      die "$(T "Unsupported CPU architecture: $arch" "Arsitektur CPU tidak didukung: $arch" "不支持的 CPU 架构：$arch")"
      ;;
  esac
}

install_xray_binary() {
  local engine="${XRAY_ENGINE:-$XRAY_ENGINE_DEFAULT}"
  log_step "$(T "Downloading and preparing the ${engine} binary..." "Mengunduh dan menyiapkan binary ${engine}..." "正在下载并准备 ${engine} 可执行文件...")"

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
  log_info "$(T "Downloading ${engine} ${ver} (${zip_name}) from GitHub..." "Mengunduh ${engine} ${ver} (${zip_name}) dari GitHub..." "正在从 GitHub 下载 ${engine} ${ver}（${zip_name}）...")"

  if curl -fsSL "$url" -o "$tmp_zip"; then
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    if command -v unzip &>/dev/null; then
      unzip -o -q "$tmp_zip" -d "$tmp_dir"
    elif command -v python3 &>/dev/null; then
      python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$tmp_zip" "$tmp_dir"
    else
      rm -rf "$tmp_dir" "$tmp_zip"
      die "$(T "'unzip' or 'python3' is required to extract ${engine}." "Butuh 'unzip' atau 'python3' untuk mengekstrak ${engine}." "解压 ${engine} 需要 'unzip' 或 'python3'。")"
    fi

    # Binary name inside the zip: "xray" (Xray) or "v2ray" (V2Ray)
    local src_bin=""
    for b in "$tmp_dir/xray" "$tmp_dir/v2ray"; do
      if [[ -f "$b" ]]; then
        src_bin="$b"
        break
      fi
    done
    [[ -n "$src_bin" ]] || { rm -rf "$tmp_dir" "$tmp_zip"; die "$(T "${engine} binary was not found inside the downloaded archive." "Binary ${engine} tidak ditemukan di dalam arsip unduhan." "在下载的压缩包中未找到 ${engine} 可执行文件。")"; }

    cp -f "$src_bin" "$XRAY_BIN"
    chmod 755 "$XRAY_BIN"

    # Include geoip/geosite when bundled in the archive
    for dat in geoip.dat geosite.dat; do
      [[ -f "$tmp_dir/$dat" ]] && cp -f "$tmp_dir/$dat" "/usr/local/share/xray/$dat"
    done

    rm -rf "$tmp_dir" "$tmp_zip"
    log_success "$(T "${engine} ${ver} installed at $XRAY_BIN ($("$XRAY_BIN" version 2>/dev/null | head -n1 || echo "$engine"))." "Binary ${engine} ${ver} terpasang di $XRAY_BIN ($("$XRAY_BIN" version 2>/dev/null | head -n1 || echo "$engine"))." "${engine} ${ver} 可执行文件已安装到 $XRAY_BIN（$("$XRAY_BIN" version 2>/dev/null | head -n1 || echo "$engine")）。")"
  else
    rm -f "$tmp_zip"
    die "$(T "Failed to download ${engine} ${ver} from GitHub. Check the internet connection." "Gagal mengunduh ${engine} ${ver} dari GitHub. Periksa koneksi internet." "从 GitHub 下载 ${engine} ${ver} 失败。请检查网络连接。")"
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

  log_step "$(T "Creating the ${XRAY_ENGINE} config (VMess/VLESS/Trojan + XTLS/REALITY)..." "Membuat konfigurasi ${XRAY_ENGINE} (VMess/VLESS/Trojan + XTLS/REALITY)..." "正在创建 ${XRAY_ENGINE} 配置（VMess/VLESS/Trojan + XTLS/REALITY）...")"

  # Server UUID (first / default account) + REALITY credentials
  local server_uuid short_id reality_out priv_key pub_key
  server_uuid="$(xray_gen_uuid)"
  short_id="$(openssl rand -hex 8 2>/dev/null || head -c8 /dev/urandom | od -An -tx1 | tr -d ' \n')"

  reality_out="$(xray_gen_reality_keys)"
  priv_key="$(echo "$reality_out" | awk '/PrivateKey|Private key/ {print $NF}')"
  pub_key="$(echo "$reality_out" | awk '/PublicKey|Public key|Password/ {print $NF}')"
  if [[ -z "$priv_key" || -z "$pub_key" ]]; then
    # Fallback: generate x25519 via openssl (base64-url format, safe for REALITY)
    priv_key="$(openssl rand -base64 32 | tr '/+' '_-' | tr -d '=')"
    pub_key="$priv_key"
    log_warn "$(T "x25519 via binary failed — using an emergency key. Re-run if REALITY has trouble." "x25519 via binary gagal — memakai kunci darurat. Jalankan ulang bila REALITY bermasalah." "通过可执行文件生成 x25519 失败——正使用应急密钥。若 REALITY 异常请重新运行。")"
  fi

  # Store core credentials (read by add/remove user)
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
XPORT_VMESS_GRPC="$XPORT_VMESS_GRPC"
XPORT_VLESS_GRPC="$XPORT_VLESS_GRPC"
XPORT_TROJAN_GRPC="$XPORT_TROJAN_GRPC"
XPORT_VLESS_REALITY_GRPC="$XPORT_VLESS_REALITY_GRPC"
XPORT_XHTTP_SHARED="$XPORT_XHTTP_SHARED"
XPORT_VLESS_REALITY_XHTTP="$XPORT_VLESS_REALITY_XHTTP"
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
      "tag": "vless-reality-tcp",
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
          "shortIds": [ "$short_id", "" ]
        }
      }
    },
    {
      "listen": "0.0.0.0",
      "port": $XPORT_VMESS_GRPC,
      "protocol": "vmess",
      "settings": { "clients": [ { "id": "$server_uuid", "alterId": 0 } ] },
      "streamSettings": { 
        "network": "grpc", 
        "grpcSettings": { 
          "serviceName": "VMessGRPC",
          "multiMode": false
        } 
      }
    },
    {
      "listen": "0.0.0.0",
      "port": $XPORT_VLESS_GRPC,
      "protocol": "vless",
      "settings": { "clients": [ { "id": "$server_uuid" } ], "decryption": "none" },
      "streamSettings": { 
        "network": "grpc", 
        "grpcSettings": { 
          "serviceName": "VLessGRPC",
          "multiMode": false
        } 
      }
    },
    {
      "listen": "0.0.0.0",
      "port": $XPORT_TROJAN_GRPC,
      "protocol": "trojan",
      "settings": { "clients": [ { "password": "$server_uuid" } ] },
      "streamSettings": { 
        "network": "grpc", 
        "grpcSettings": { 
          "serviceName": "TrojanGRPC",
          "multiMode": false
        } 
      }
    },
    {
      "listen": "0.0.0.0",
      "port": $XPORT_VLESS_REALITY_GRPC,
      "protocol": "vless",
      "settings": { "clients": [ { "id": "$server_uuid" } ], "decryption": "none" },
      "streamSettings": {
        "network": "grpc",
        "security": "reality",
        "grpcSettings": { 
          "serviceName": "RealityGRPC",
          "multiMode": false
        },
        "realitySettings": {
          "show": false,
          "dest": "$XREALITY_DEST_DEFAULT",
          "xver": 0,
          "serverNames": [ "$XREALITY_SNI_DEFAULT" ],
          "privateKey": "$priv_key",
          "shortIds": [ "$short_id", "" ]
        }
      }
    },
    {
      "tag": "vmess-xhttp",
      "listen": "0.0.0.0",
      "port": $XPORT_XHTTP_SHARED,
      "protocol": "vmess",
      "settings": { "clients": [ { "id": "$server_uuid", "alterId": 0 } ] },
      "streamSettings": { 
        "network": "xhttp",
        "xhttpSettings": {
          "path": "/vmess-xhttp",
          "host": ""
        }
      }
    },
    {
      "tag": "vless-xhttp",
      "listen": "0.0.0.0",
      "port": $XPORT_XHTTP_SHARED,
      "protocol": "vless",
      "settings": { "clients": [ { "id": "$server_uuid" } ], "decryption": "none" },
      "streamSettings": { 
        "network": "xhttp",
        "xhttpSettings": {
          "path": "/vless-xhttp",
          "host": ""
        }
      }
    },
    {
      "tag": "trojan-xhttp",
      "listen": "0.0.0.0",
      "port": $XPORT_XHTTP_SHARED,
      "protocol": "trojan",
      "settings": { "clients": [ { "password": "$server_uuid" } ] },
      "streamSettings": { 
        "network": "xhttp",
        "xhttpSettings": {
          "path": "/trojan-xhttp",
          "host": ""
        }
      }
    },
    {
      "tag": "vless-reality-xhttp",
      "listen": "0.0.0.0",
      "port": $XPORT_VLESS_REALITY,
      "protocol": "vless",
      "settings": { "clients": [ { "id": "$server_uuid", "flow": "" } ], "decryption": "none" },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "xhttpSettings": {
          "path": "/reality-xhttp",
          "host": ""
        },
        "realitySettings": {
          "show": false,
          "dest": "$XREALITY_DEST_DEFAULT",
          "xver": 0,
          "serverNames": [ "$XREALITY_SNI_DEFAULT" ],
          "privateKey": "$priv_key",
          "shortIds": [ "$short_id", "" ]
        }
      }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "tag": "direct" } ]
}
EOF
  chmod 600 "$XRAY_CONFIG"

  # Validate the config before starting
  "$XRAY_BIN" run -test -config "$XRAY_CONFIG" 2>&1 | tail -n5 || true

  # Systemd service
  cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray/V2Ray Service v4.2 (13 inbounds: WS + gRPC + XHTTP + XTLS + REALITY)
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
    log_error "$(T "The xray service failed to start. Log:" "Service xray gagal berjalan. Log:" "xray 服务启动失败。日志：")"
    journalctl -u xray -n 20 --no-pager || true
    die "$(T "${XRAY_ENGINE} install failed to start." "Instalasi ${XRAY_ENGINE} gagal dijalankan." "${XRAY_ENGINE} 安装后启动失败。")"
  fi

  # Open every inbound port in the firewall (WebSocket + gRPC + XHTTP)
  for p in "$XPORT_VMESS_WS" "$XPORT_VLESS_WS" "$XPORT_TROJAN_WS" "$XPORT_VLESS_XTLS" "$XPORT_VLESS_REALITY" "$XPORT_VMESS_GRPC" "$XPORT_VLESS_GRPC" "$XPORT_TROJAN_GRPC" "$XPORT_VLESS_REALITY_GRPC" "$XPORT_XHTTP_SHARED"; do
    open_firewall_port "$p" "tcp"
  done

  # Register the default server account
  touch "$XRAY_ACCOUNTS_DB"
  chmod 600 "$XRAY_ACCOUNTS_DB"
  echo "server-default:${server_uuid}:$(date +%Y-%m-%d)" >> "$XRAY_ACCOUNTS_DB"

  log_success "$(T "${XRAY_ENGINE} v4.2 is active (13 inbounds: WS + gRPC + XHTTP + XTLS + REALITY)." "${XRAY_ENGINE} v4.2 aktif (13 inbound: WS + gRPC + XHTTP + XTLS + REALITY)." "${XRAY_ENGINE} v4.2 运行中（13 个入站：WS + gRPC + XHTTP + XTLS + REALITY）。")"

  xray_print_links "server-default" "$server_uuid"
}

# ------------------------------------------------------- link generator
# Prints vmess://, vless:// and trojan:// links (WS + gRPC + XHTTP) + QR for 1 UUID — v4.2
xray_print_links() {
  local name="${1:?$(T "username is required" "nama user wajib diisi" "用户名为必需")}"
  local uuid="${2:?$(T "uuid is required" "uuid wajib diisi" "uuid 为必需")}"
  # shellcheck disable=SC1090
  [[ -f "$XRAY_PARAMS" ]] && source "$XRAY_PARAMS"

  local ip="${XRAY_PUB_IP:-$(get_public_ip)}"
  local sni="${XREALITY_SNI:-$XREALITY_SNI_DEFAULT}"
  local pbk="${XREALITY_PUB:-}"
  local sid="${XREALITY_SHORTID:-}"

  # WebSocket links
  local vmess_json
  vmess_json="$(printf '{"v":"2","ps":"%s-vmess-ws","add":"%s","port":"%s","id":"%s","aid":"0","net":"ws","type":"none","host":"","path":"/vmess","tls":""}' "$name" "$ip" "$XPORT_VMESS_WS" "$uuid")"
  local vmess_link="vmess://$(echo -n "$vmess_json" | base64 -w 0 2>/dev/null || echo -n "$vmess_json" | base64 | tr -d '\n')"

  local vless_ws_link="vless://${uuid}@${ip}:${XPORT_VLESS_WS}?encryption=none&security=none&type=ws&path=%2Fvless#${name}-vless-ws"
  local trojan_link="trojan://${uuid}@${ip}:${XPORT_TROJAN_WS}?security=none&type=ws&path=%2Ftrojan#${name}-trojan-ws"

  # gRPC links (v4: HTTP/2 based, excellent for CDN/reverse proxy)
  local vmess_json_grpc
  vmess_json_grpc="$(printf '{"v":"2","ps":"%s-vmess-grpc","add":"%s","port":"%s","id":"%s","aid":"0","net":"grpc","type":"none","host":"","path":"VMessGRPC","tls":""}' "$name" "$ip" "$XPORT_VMESS_GRPC" "$uuid")"
  local vmess_grpc_link="vmess://$(echo -n "$vmess_json_grpc" | base64 -w 0 2>/dev/null || echo -n "$vmess_json_grpc" | base64 | tr -d '\n')"

  local vless_grpc_link="vless://${uuid}@${ip}:${XPORT_VLESS_GRPC}?encryption=none&security=none&type=grpc&serviceName=VLessGRPC#${name}-vless-grpc"
  local trojan_grpc_link="trojan://${uuid}@${ip}:${XPORT_TROJAN_GRPC}?security=none&type=grpc&serviceName=TrojanGRPC#${name}-trojan-grpc"

  # XHTTP links (v4.2: newest transport, most HTTP-like, best stealth on port 80/443)
  local vmess_json_xhttp
  vmess_json_xhttp="$(printf '{"v":"2","ps":"%s-vmess-xhttp","add":"%s","port":"%s","id":"%s","aid":"0","net":"xhttp","type":"none","host":"","path":"/vmess-xhttp","tls":""}' "$name" "$ip" "$XPORT_XHTTP_SHARED" "$uuid")"
  local vmess_xhttp_link="vmess://$(echo -n "$vmess_json_xhttp" | base64 -w 0 2>/dev/null || echo -n "$vmess_json_xhttp" | base64 | tr -d '\n')"

  local vless_xhttp_link="vless://${uuid}@${ip}:${XPORT_XHTTP_SHARED}?encryption=none&security=none&type=xhttp&path=%2Fvless-xhttp#${name}-vless-xhttp"
  local trojan_xhttp_link="trojan://${uuid}@${ip}:${XPORT_XHTTP_SHARED}?security=none&type=xhttp&path=%2Ftrojan-xhttp#${name}-trojan-xhttp"

  # XTLS & REALITY
  local vless_xtls_link="vless://${uuid}@${ip}:${XPORT_VLESS_XTLS}?encryption=none&flow=xtls-rprx-vision&security=none&type=tcp#${name}-vless-xtls"
  local vless_reality_link="vless://${uuid}@${ip}:${XPORT_VLESS_REALITY}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${pbk}&sid=${sid}&type=tcp#${name}-vless-reality-tcp"

  # REALITY + gRPC (v4: best for heavy censorship + CDN compatibility)
  local vless_reality_grpc_link="vless://${uuid}@${ip}:${XPORT_VLESS_REALITY_GRPC}?encryption=none&security=reality&type=grpc&serviceName=RealityGRPC&sni=${sni}&fp=chrome&pbk=${pbk}&sid=${sid}#${name}-vless-reality-grpc"

  # REALITY + XHTTP (v4.2: BEST stealth on port 443, most HTTP-like)
  local vless_reality_xhttp_link="vless://${uuid}@${ip}:${XPORT_VLESS_REALITY_XHTTP}?encryption=none&security=reality&type=xhttp&path=%2Freality-xhttp&sni=${sni}&fp=chrome&pbk=${pbk}&sid=${sid}#${name}-vless-reality-xhttp"

  echo ""
  echo "==================== $(T "CONNECTION LINKS v4.2 (13 PROTOCOLS)" "LINK KONEKSI v4.2 (13 PROTOKOL)" "连接链接 v4.2（13 种协议）"): $name ===================="
  echo ""
  echo "$(T "=== RECOMMENDED (Top 4) ===" "=== REKOMENDASI (4 Teratas) ===" "=== 推荐（前 4 名）===")"
  echo ""
  echo "--- [1] VLESS + XHTTP + REALITY @ Port 443 ($(T "🏆 BEST: Most HTTP-like, port 443, ultimate stealth" "🏆 TERBAIK: Paling mirip HTTP, port 443, stealth maksimal" "🏆 最佳：最像 HTTP，端口 443，终极隐身"))"
  echo "$vless_reality_xhttp_link"
  echo ""
  echo "--- [2] VLESS + TCP + XTLS-Vision + REALITY @ Port 443 ($(T "Most efficient & anti-blocking" "Paling efisien & anti-blokir" "最高效且抗封锁"))"
  echo "$vless_reality_link"
  echo ""
  echo "--- [3] VLESS + gRPC + REALITY ($(T "Best for CDN & heavy censorship" "Terbaik untuk CDN & sensor berat" "最适合 CDN 与严重审查"))"
  echo "$vless_reality_grpc_link"
  echo ""
  echo "--- [4] VLESS + TCP + XTLS-Vision @ Port 10004"
  echo "$vless_xtls_link"
  echo ""
  echo "$(T "=== XHTTP Transports (Port 80, newest, most HTTP-like) ===" "=== Transport XHTTP (Port 80, terbaru, paling mirip HTTP) ===" "=== XHTTP 传输（端口 80，最新，最像 HTTP）===")"
  echo ""
  echo "--- [5] VMess + XHTTP @ Port 80"
  echo "$vmess_xhttp_link"
  echo ""
  echo "--- [6] VLESS + XHTTP @ Port 80"
  echo "$vless_xhttp_link"
  echo ""
  echo "--- [7] Trojan + XHTTP @ Port 80"
  echo "$trojan_xhttp_link"
  echo ""
  echo "$(T "=== WebSocket Transports (CDN compatible) ===" "=== Transport WebSocket (kompatibel CDN) ===" "=== WebSocket 传输（兼容 CDN）===")"
  echo ""
  echo "--- [8] VMess + WebSocket"
  echo "$vmess_link"
  echo ""
  echo "--- [9] VLESS + WebSocket"
  echo "$vless_ws_link"
  echo ""
  echo "--- [10] Trojan + WebSocket"
  echo "$trojan_link"
  echo ""
  echo "$(T "=== gRPC Transports (HTTP/2, efficient, CDN compatible) ===" "=== Transport gRPC (HTTP/2, efisien, kompatibel CDN) ===" "=== gRPC 传输（HTTP/2，高效，兼容 CDN）===")"
  echo ""
  echo "--- [11] VMess + gRPC"
  echo "$vmess_grpc_link"
  echo ""
  echo "--- [12] VLESS + gRPC"
  echo "$vless_grpc_link"
  echo ""
  echo "--- [13] Trojan + gRPC"
  echo "$trojan_grpc_link"
  echo "=============================================================="

  if command -v qrencode &>/dev/null; then
    echo ""
    echo "$(T "QR code (VLESS REALITY XHTTP — scan with v2rayNG / NekoBox / Streisand):" "QR Code (VLESS REALITY XHTTP — pindai dengan v2rayNG / NekoBox / Streisand):" "二维码（VLESS REALITY XHTTP——请用 v2rayNG / NekoBox / Streisand 扫描）：")"
    qrencode -t ansiutf8 "$vless_reality_xhttp_link" || true
  fi

  XRAY_LAST_VMESS="$vmess_link"
  XRAY_LAST_REALITY="$vless_reality_link"
  XRAY_LAST_REALITY_GRPC="$vless_reality_grpc_link"
  XRAY_LAST_REALITY_XHTTP="$vless_reality_xhttp_link"
  export XRAY_LAST_VMESS XRAY_LAST_REALITY XRAY_LAST_REALITY_GRPC XRAY_LAST_REALITY_XHTTP
}

# ------------------------------------------------------- user management
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
  [[ -f "$XRAY_PARAMS" ]] || die "$(T "Xray/V2Ray is not installed yet. Install the server first." "Xray/V2Ray belum terpasang. Jalankan instalasi server dulu." "Xray/V2Ray 尚未安装。请先安装服务器。")"
  # shellcheck disable=SC1090
  source "$XRAY_PARAMS"

  if xray_user_exists "$name"; then
    die "$(T "Xray user '$name' is already registered! Pick another name." "User Xray '$name' sudah terdaftar! Pilih nama lain." "Xray 用户 '$name' 已注册！请选择其他名称。")"
  fi

  local uuid
  uuid="$(xray_gen_uuid)"

  # Insert the new client into every inbound that owns a clients/passwords list.
  # The config is written by this script so its JSON shape is predictable:
  #   VMess/VLESS : { "id": "<uuid>" ... }  (VLESS+XTLS/REALITY use flow)
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

  # Validate & reload the service
  "$XRAY_BIN" run -test -config "$XRAY_CONFIG" || die "$(T "The new Xray config is invalid, aborting." "Konfigurasi Xray baru tidak valid, dibatalkan." "新的 Xray 配置无效，已中止。")"
  systemctl restart xray
  systemctl is-active --quiet xray || die "$(T "The xray service failed to restart after adding the user." "Service xray gagal restart setelah tambah user." "添加用户后 xray 服务重启失败。")"

  echo "${name}:${uuid}:$(date +%Y-%m-%d)" >> "$XRAY_ACCOUNTS_DB"

  log_success "$(T "Xray user '$name' created (UUID: $uuid)." "User Xray '$name' dibuat (UUID: $uuid)." "Xray 用户 '$name' 已创建（UUID：$uuid）。")"
  xray_print_links "$name" "$uuid"
}

xray_remove_user() {
  local name="$1"
  validate_client_name "$name"
  [[ -f "$XRAY_PARAMS" ]] || die "$(T "Xray/V2Ray is not installed." "Xray/V2Ray belum terpasang." "Xray/V2Ray 尚未安装。")"
  # shellcheck disable=SC1090
  source "$XRAY_PARAMS"

  # Look up the user UUID from the database
  local uuid=""
  if [[ -f "$XRAY_ACCOUNTS_DB" ]]; then
    uuid="$(awk -F: -v u="$name" '$1==u {print $2}' "$XRAY_ACCOUNTS_DB" | head -n1)"
  fi
  [[ -n "$uuid" ]] || die "$(T "Xray user '$name' was not found." "User Xray '$name' tidak ditemukan." "未找到 Xray 用户 '$name'。")"

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

  log_success "$(T "Xray user '$name' removed from all inbounds." "User Xray '$name' berhasil dihapus dari semua inbound." "Xray 用户 '$name' 已从所有入站中删除。")"
}

xray_list_users() {
  echo "======================================================================"
  echo -e "${_C_BOLD}$(T "XRAY/V2RAY USER LIST" "DAFTAR USER XRAY/V2RAY" "XRAY/V2RAY 用户列表")${_C_RESET}"
  echo "======================================================================"
  printf "%-18s %-40s %-12s\n" "USERNAME" "UUID" "$(T "CREATED" "DIBUAT" "创建时间")"
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
    echo " ($(T "No users registered yet" "Belum ada user yang terdaftar" "暂无已注册的用户"))"
  fi
  echo "----------------------------------------------------------------------"
  echo "$(T "Total users: $count" "Total user: $count" "用户总数：$count")"
  echo "Engine: ${XRAY_ENGINE:-xray} | Config: $XRAY_CONFIG"
  echo "======================================================================"
}
