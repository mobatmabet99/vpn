#!/bin/bash
#
# lib/xray.sh — Xray-core / V2Ray module (VMess, VLESS, Trojan + XTLS/REALITY, trilingual EN/ID/ZH)
# Branding: wrwb Store
#
# Default engine: Xray-core v26.10.10 (stable, supports XTLS-Vision + REALITY + XHTTP).
# Alternative: v2ray-core v5.53.0 (selected via XRAY_ENGINE=v2ray).
#
# Inbounds installed together (default ports) — v5 gateway architecture (XRAY engine):
#   Direct (public, fastest, no Nginx overhead):
#     VMess WS            10001/tcp  (path /vmess, 0.0.0.0)
#     VLESS WS            10002/tcp  (path /vless, 0.0.0.0)
#     Trojan WS           10003/tcp  (path /trojan, password = user UUID)
#     VLESS TCP XTLS      10004/tcp  (flow xtls-rprx-vision)
#     VLESS TCP REALITY   443/tcp    (flow xtls-rprx-vision, SNI www.microsoft.com,
#                                     + fallback -> 127.0.0.1:8443 for WS-TLS via 443)
#     VMess gRPC          10005/tcp  (serviceName VMessGRPC) — v4
#     VLESS gRPC          10006/tcp  (serviceName VLessGRPC) — v4
#     Trojan gRPC         10007/tcp  (serviceName TrojanGRPC) — v4
#     VLESS REALITY gRPC  10008/tcp  (serviceName RealityGRPC, with REALITY) — v4
#   XHTTP via gateway only (localhost, public via Nginx 80/8080/443/8443):
#     VMess XHTTP         127.0.0.1:10009 (path /vmess-xhttp) — v5 (was shared 80, broken)
#     VLESS XHTTP         127.0.0.1:10010 (path /vless-xhttp) — v5
#     Trojan XHTTP        127.0.0.1:10011 (path /trojan-xhttp) — v5
#     VLESS REALITY XHTTP 10012/tcp    (path /reality-xhttp, with REALITY) — v5 (was 443 duplicate)
#   Gateway (Nginx edge, lib/edge.sh):
#     80/tcp non-TLS + 8080/tcp alt  -> /vmess /vless /trojan /vmess-xhttp /vless-xhttp /trojan-xhttp /ssh-ws /wg-ws
#     8443/tcp TLS + 443/tcp via REALITY fallback (TLS only) -> same paths (wss://)
#   Total: 13 inbounds (Xray engine). v2ray engine (v5.53.0, NO REALITY/XHTTP/XTLS-Vision):
#     7 inbounds only — 3x WS (10001-10003) + 3x gRPC (10005-10007) + 1x plain TCP (10004).
#
# Each user gets 1 UUID valid for ALL protocols above (13 inbounds on xray, 7 on v2ray).
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

# v4.2: XHTTP backend ports (v5: localhost-only, public via Nginx gateway 80/8080/443/8443).
# v4.2 had 3 inbounds sharing port 80 + REALITY XHTTP duplicating 443 — Xray cannot
# bind multiple inbounds to one port, so only the FIRST inbound worked. v5 gives each
# inbound its own localhost port; Nginx routes /vmess-xhttp etc. per-path.
XPORT_VMESS_XHTTP="${XPORT_VMESS_XHTTP:-10009}"
XPORT_VLESS_XHTTP="${XPORT_VLESS_XHTTP:-10010}"
XPORT_TROJAN_XHTTP="${XPORT_TROJAN_XHTTP:-10011}"
XPORT_VLESS_REALITY_XHTTP="${XPORT_VLESS_REALITY_XHTTP:-10012}"
# Backward compat: old param files stored XPORT_XHTTP_SHARED=80 (v4.x). Migrate it.
XPORT_XHTTP_SHARED="${XPORT_XHTTP_SHARED:-80}"
# Public gateway ports for link generation (Nginx edge, lib/edge.sh)
XPORT_GW_PLAIN="${XPORT_GW_PLAIN:-80}"
XPORT_GW_ALT="${XPORT_GW_ALT:-8080}"
XPORT_GW_TLS="${XPORT_GW_TLS:-8443}"

# SNI REALITY default: domain besar yang mendukung TLSv1.3 + H2
XREALITY_SNI_DEFAULT="${XREALITY_SNI_DEFAULT:-www.microsoft.com}"
XREALITY_DEST_DEFAULT="${XREALITY_DEST_DEFAULT:-www.microsoft.com:443}"

xray_detect_arch() {
  local arch
  arch="$(uname -m)"
  # NOTE: return values are XRAY asset suffixes (Xray-linux-<suffix>.zip).
  # v2ray asset names differ on arm (v2ray-linux-arm32-v7a.zip vs v6a, and NO
  # official arm32-v6 zip at all) — install_xray_binary remaps per-engine.
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
      echo "arm32-v6a"
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
    # v2ray asset naming differs from Xray on ARM: v2ray-linux-arm32-v7a.zip
    # (v7a, plus arm64 just "arm64", 32-bit is "32.zip", mips variants exist).
    case "$arch_suffix" in
      64) zip_name="v2ray-linux-64.zip" ;;
      arm64-v8a) zip_name="v2ray-linux-arm64.zip" ;;
      arm32-v7a) zip_name="v2ray-linux-arm32-v7a.zip" ;;
      # armv6 has NO official v2ray zip — fall through to the v7a asset name so
      # the 404 error message shows a real candidate instead of a made-up file.
      arm32-v6a) zip_name="v2ray-linux-arm32-v7a.zip" ;;
      *) zip_name="v2ray-linux-${arch_suffix}.zip" ;;
    esac
    url="https://github.com/v2fly/v2ray-core/releases/download/${ver}/${zip_name}"
  else
    engine="xray"
    ver="${XRAY_VERSION:-$XRAY_VERSION_DEFAULT}"
    zip_name="Xray-linux-${arch_suffix}.zip"
    url="https://github.com/XTLS/Xray-core/releases/download/${ver}/${zip_name}"
  fi

  local tmp_zip
  # Alpine/busybox mktemp has NO --suffix flag (fails hard) — plain mktemp works
  # everywhere (same fix already needed for the .tar.xz path in lib/shadowsocks.sh).
  if tmp_zip="$(mktemp --suffix=.zip 2>/dev/null)"; then
    :
  else
    tmp_zip="$(mktemp)/xray.zip"
  fi
  track_temp "$tmp_zip"
  log_info "$(T "Downloading ${engine} ${ver} (${zip_name}) from GitHub..." "Mengunduh ${engine} ${ver} (${zip_name}) dari GitHub..." "正在从 GitHub 下载 ${engine} ${ver}（${zip_name}）...")"

  if curl -fsSL --retry 2 --connect-timeout 20 "$url" -o "$tmp_zip"; then
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    track_temp "$tmp_dir"
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
    # Both xray and v2ray binaries expose a `uuid` subcommand.
    "$XRAY_BIN" uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid
  elif command -v uuidgen &>/dev/null; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    cat /proc/sys/kernel/random/uuid
  fi
}

xray_gen_reality_keys() {
  # v2ray binary has NO x25519 subcommand (Xray-only); caller skips for v2ray.
  if [[ "${XRAY_ENGINE:-$XRAY_ENGINE_DEFAULT}" == "v2ray" ]]; then
    return 1
  fi
  if [[ -x "$XRAY_BIN" ]]; then
    "$XRAY_BIN" x25519 2>/dev/null || echo ""
  else
    echo ""
  fi
}

# Engine-aware config validation (v5): xray uses `run -test -config`,
# v2ray uses `test -c` (v2ray has no `-test` flag on `run`).
# Usage: xray_test_config [config_path]
# PIPESTATUS-based (not pipefail-dependent): callers without `set -o pipefail`
# (status.sh subshells, cron) still get the REAL binary exit code, not tail's 0.
xray_test_config() {
  local cfg="${1:-$XRAY_CONFIG}"
  local eng="${XRAY_ENGINE:-$XRAY_ENGINE_DEFAULT}"
  # Params file is authoritative when present (menu/status may not export engine)
  if [[ -f "$XRAY_PARAMS" ]]; then
    # shellcheck disable=SC1090
    source "$XRAY_PARAMS" 2>/dev/null || true
    eng="${XRAY_ENGINE:-$eng}"
  fi
  if [[ "$eng" == "v2ray" ]]; then
    "$XRAY_BIN" test -c "$cfg" 2>&1 | tail -n5
    return "${PIPESTATUS[0]:-0}"
  else
    "$XRAY_BIN" run -test -config "$cfg" 2>&1 | tail -n5
    return "${PIPESTATUS[0]:-0}"
  fi
}

xray_setup_server() {
  local pub_ip="${1:-$(get_public_ip)}"
  local engine="${XRAY_ENGINE:-$XRAY_ENGINE_DEFAULT}"
  # v5: port-conflict check. v2ray engine (v5.53.0) has NO REALITY/XHTTP/XTLS-Vision
  # inbounds: only WS (10001-10003), gRPC (10005-10007) and plain TCP (10004).
  # Skip REALITY/XHTTP checks on v2ray so menu 10 never warns about unbound ports.
  check_port_free "$XPORT_VMESS_WS" "tcp" "VMess-WS" --soft || true
  check_port_free "$XPORT_VLESS_WS" "tcp" "VLESS-WS" --soft || true
  check_port_free "$XPORT_TROJAN_WS" "tcp" "Trojan-WS" --soft || true
  check_port_free "$XPORT_VLESS_XTLS" "tcp" "VLESS-TCP" --soft || true
  check_port_free "$XPORT_VMESS_GRPC" "tcp" "VMess-gRPC" --soft || true
  check_port_free "$XPORT_VLESS_GRPC" "tcp" "VLESS-gRPC" --soft || true
  check_port_free "$XPORT_TROJAN_GRPC" "tcp" "Trojan-gRPC" --soft || true
  if [[ "$engine" != "v2ray" ]]; then
    check_port_free "$XPORT_VLESS_REALITY" "tcp" "VLESS-REALITY" --soft || true
    check_port_free "$XPORT_VLESS_REALITY_GRPC" "tcp" "VLESS-REALITY-gRPC" --soft || true
    check_port_free "$XPORT_VMESS_XHTTP" "tcp" "VMess-XHTTP-be" --soft || true
    check_port_free "$XPORT_VLESS_XHTTP" "tcp" "VLESS-XHTTP-be" --soft || true
    check_port_free "$XPORT_TROJAN_XHTTP" "tcp" "Trojan-XHTTP-be" --soft || true
    check_port_free "$XPORT_VLESS_REALITY_XHTTP" "tcp" "REALITY-XHTTP" --soft || true
  fi

  install_xray_binary

  log_step "$(T "Creating the ${XRAY_ENGINE} config (VMess/VLESS/Trojan + XTLS/REALITY)..." "Membuat konfigurasi ${XRAY_ENGINE} (VMess/VLESS/Trojan + XTLS/REALITY)..." "正在创建 ${XRAY_ENGINE} 配置（VMess/VLESS/Trojan + XTLS/REALITY）...")"

  # Server UUID (first / default account) + REALITY credentials (Xray-only;
  # v2ray has no REALITY inbounds so keys stay empty and emergency fallback is skipped).
  local server_uuid short_id reality_out priv_key pub_key
  server_uuid="$(xray_gen_uuid)"
  short_id="$(openssl rand -hex 8 2>/dev/null || head -c8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  priv_key=""; pub_key=""

  if [[ "$engine" != "v2ray" ]]; then
    reality_out="$(xray_gen_reality_keys)"
    priv_key="$(echo "$reality_out" | awk '/PrivateKey|Private key/ {print $NF}')"
    pub_key="$(echo "$reality_out" | awk '/PublicKey|Public key|Password/ {print $NF}')"
    if [[ -z "$priv_key" || -z "$pub_key" ]]; then
      # Fallback: generate x25519 via openssl (base64-url format, safe for REALITY)
      priv_key="$(openssl rand -base64 32 | tr '/+' '_-' | tr -d '=')"
      pub_key="$priv_key"
      log_warn "$(T "x25519 via binary failed — using an emergency key. Re-run if REALITY has trouble." "x25519 via binary gagal — memakai kunci darurat. Jalankan ulang bila REALITY bermasalah." "通过可执行文件生成 x25519 失败——正使用应急密钥。若 REALITY 异常请重新运行。")"
    fi
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
XPORT_VMESS_XHTTP="$XPORT_VMESS_XHTTP"
XPORT_VLESS_XHTTP="$XPORT_VLESS_XHTTP"
XPORT_TROJAN_XHTTP="$XPORT_TROJAN_XHTTP"
XPORT_VLESS_REALITY_XHTTP="$XPORT_VLESS_REALITY_XHTTP"
XPORT_GW_PLAIN="${XPORT_GW_PLAIN:-80}"
XPORT_GW_ALT="${XPORT_GW_ALT:-8080}"
XPORT_GW_TLS="${XPORT_GW_TLS:-8443}"
EOF
  chmod 600 "$XRAY_PARAMS"

  # v5: v2ray-core (v5.53.0) has NO xhttp transport, NO REALITY, NO XTLS-Vision.
  # Write a 7-inbound config for v2ray (3x WS direct + 3x gRPC + 1x Trojan-TCP);
  # the REALITY fallback chain (443 -> 127.0.0.1:8443) is Xray-only, so on v2ray
  # port 443 is plain Nginx TLS only via the gateway (no Xray listener on 443).
  # Keep gateway WS paths working (Nginx still proxies /vmess /vless /trojan).
  if [[ "$engine" == "v2ray" ]]; then
    # v2ray: no reality keys (no x25519 subcommand, no reality inbounds)
    priv_key=""; pub_key=""
    log_info "$(T "v2ray engine: writing 7-inbound config (WS + gRPC, no REALITY/XHTTP/XTLS-Vision)." "Engine v2ray: menulis config 7 inbound (WS + gRPC, tanpa REALITY/XHTTP/XTLS-Vision)." "v2ray 引擎：正在写入 7 入站配置（WS + gRPC，无 REALITY/XHTTP/XTLS-Vision）。")"
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
      "port": $XPORT_VLESS_XTLS,
      "protocol": "vless",
      "settings": { "clients": [ { "id": "$server_uuid" } ], "decryption": "none" },
      "streamSettings": { "network": "tcp", "security": "none" }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "tag": "direct" } ]
}
EOF
  else
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
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls"] },
      "fallbacks": [
        { "dest": "127.0.0.1:8443", "xver": 0 }
      ]
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
      "listen": "127.0.0.1",
      "port": $XPORT_VMESS_XHTTP,
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
      "listen": "127.0.0.1",
      "port": $XPORT_VLESS_XHTTP,
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
      "listen": "127.0.0.1",
      "port": $XPORT_TROJAN_XHTTP,
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
      "port": $XPORT_VLESS_REALITY_XHTTP,
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
  fi
  chmod 600 "$XRAY_CONFIG"

  # v4.9: validate config BEFORE restart (never restart on broken config)
  # v5: engine-aware (xray `run -test`, v2ray `test -c`).
  log_step "$(T "Validating the ${engine} config before starting..." "Memvalidasi konfigurasi ${engine} sebelum dijalankan..." "正在启动前验证 ${engine} 配置...")"
  xray_test_config "$XRAY_CONFIG" ||
    die "$(T "Xray config test FAILED — aborting before restart." "Tes konfigurasi Xray GAGAL — dibatalkan sebelum restart." "Xray 配置测试失败 — 已在重启前中止。")"

  # Systemd service (inbound count differs per engine: xray 13, v2ray 7).
  # v2ray `run` accepts the same `-config` flag as xray, so one unit works for both.
  local _inbound_desc="13 inbounds: WS + gRPC + XHTTP + XTLS + REALITY"
  [[ "$engine" == "v2ray" ]] && _inbound_desc="7 inbounds: WS + gRPC + TCP (no REALITY/XHTTP/XTLS-Vision)"
  cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray/V2Ray Service v5 (${_inbound_desc}, auto-start on boot)
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

  svc_restart "$XRAY_SERVICE"
  systemctl is-active --quiet xray ||
    die "$(T "${XRAY_ENGINE} install failed to start." "Instalasi ${XRAY_ENGINE} gagal dijalankan." "${XRAY_ENGINE} 安装后启动失败。")"

  # Open every inbound port in the firewall (direct + gateways).
  # XHTTP backends 10009-10011 are localhost-only (via Nginx). Like wstunnel's
  # 10081 they MUST NOT be opened publicly: opening them adds firewall rules
  # for ports no public client can use (worse: it misleads audits into
  # thinking XHTTP is directly exposed). Gateways 80/8080/8443 opened by edge.sh.
  # v2ray engine: no REALITY/XHTTP/XTLS-Vision ports exist — only WS + gRPC + plain TCP.
  if [[ "$engine" == "v2ray" ]]; then
    open_firewall_ports "Xray" "tcp" "$XPORT_VMESS_WS" "$XPORT_VLESS_WS" "$XPORT_TROJAN_WS" "$XPORT_VLESS_XTLS" "$XPORT_VMESS_GRPC" "$XPORT_VLESS_GRPC" "$XPORT_TROJAN_GRPC"
  else
    open_firewall_ports "Xray" "tcp" "$XPORT_VMESS_WS" "$XPORT_VLESS_WS" "$XPORT_TROJAN_WS" "$XPORT_VLESS_XTLS" "$XPORT_VLESS_REALITY" "$XPORT_VMESS_GRPC" "$XPORT_VLESS_GRPC" "$XPORT_TROJAN_GRPC" "$XPORT_VLESS_REALITY_GRPC" "$XPORT_VLESS_REALITY_XHTTP"
  fi

  # Register the default server account
  touch "$XRAY_ACCOUNTS_DB"
  chmod 600 "$XRAY_ACCOUNTS_DB"
  echo "server-default:${server_uuid}:$(date +%Y-%m-%d)" >> "$XRAY_ACCOUNTS_DB"

  if [[ "$engine" == "v2ray" ]]; then
    log_success "$(T "${XRAY_ENGINE} v5 is active (7 inbounds: WS + gRPC + TCP; WS via gateway 80/8080/8443)." "${XRAY_ENGINE} v5 aktif (7 inbound: WS + gRPC + TCP; WS via gateway 80/8080/8443)." "${XRAY_ENGINE} v5 运行中（7 个入站：WS + gRPC + TCP；WS 经网关 80/8080/8443）。")"
  else
    log_success "$(T "${XRAY_ENGINE} v5 is active (13 inbounds: WS + gRPC + XHTTP + XTLS + REALITY; XHTTP via gateway 80/8080/443/8443)." "${XRAY_ENGINE} v5 aktif (13 inbound: WS + gRPC + XHTTP + XTLS + REALITY; XHTTP via gateway 80/8080/443/8443)." "${XRAY_ENGINE} v5 运行中（13 个入站：WS + gRPC + XHTTP + XTLS + REALITY；XHTTP 经网关 80/8080/443/8443）。")"
  fi

  xray_print_links "server-default" "$server_uuid"
}

# ------------------------------------------------------- link generator
# Prints vmess://, vless:// and trojan:// links (direct + gateway WS/XHTTP) + QR — v5
# v4.9: SAVE=1 also appends the full block to $VPN_SUMMARY_FILE (re-readable).
xray_print_links() {
  local name="${1:?$(T "username is required" "nama user wajib diisi" "用户名为必需")}"
  local uuid="${2:?$(T "uuid is required" "uuid wajib diisi" "uuid 为必需")}"
  local save="${3:-1}"
  # shellcheck disable=SC1090
  [[ -f "$XRAY_PARAMS" ]] && source "$XRAY_PARAMS"
  local engine="${XRAY_ENGINE:-$XRAY_ENGINE_DEFAULT}"
  # v5: SSL_DOMAIN lives in /etc/vpn-ssl/params — source it so gateway TLS links
  # use the real SNI even when xray params lack it (async setup order).
  if [[ -f /etc/vpn-ssl/params ]]; then
    # shellcheck disable=SC1090
    source /etc/vpn-ssl/params 2>/dev/null || true
  fi

  local ip="${XRAY_PUB_IP:-$(get_public_ip)}"
  local sni="${XREALITY_SNI:-$XREALITY_SNI_DEFAULT}"
  local pbk="${XREALITY_PUB:-}"
  local sid="${XREALITY_SHORTID:-}"
  # Gateway ports (Nginx edge). Old param files lack these (default 80/8080/8443).
  local gw_plain="${XPORT_GW_PLAIN:-80}"
  local gw_alt="${XPORT_GW_ALT:-8080}"
  local gw_tls="${XPORT_GW_TLS:-8443}"
  # XHTTP backend ports never appear in links (localhost-only); users always
  # connect via the gateway (80/8080/443/8443).

  # WebSocket links (direct to Xray backends)
  local vmess_json
  vmess_json="$(printf '{"v":"2","ps":"%s-vmess-ws","add":"%s","port":"%s","id":"%s","aid":"0","net":"ws","type":"none","host":"","path":"/vmess","tls":""}' "$name" "$ip" "$XPORT_VMESS_WS" "$uuid")"
  local vmess_link="vmess://$(echo -n "$vmess_json" | base64 -w 0 2>/dev/null || echo -n "$vmess_json" | base64 | tr -d '\n')"

  local vless_ws_link="vless://${uuid}@${ip}:${XPORT_VLESS_WS}?encryption=none&security=none&type=ws&path=%2Fvless#${name}-vless-ws"
  local trojan_link="trojan://${uuid}@${ip}:${XPORT_TROJAN_WS}?security=none&type=ws&path=%2Ftrojan#${name}-trojan-ws"

  # WS via gateway (port 80 non-TLS, 8080 alt)
  local vmess_json_gw
  vmess_json_gw="$(printf '{"v":"2","ps":"%s-vmess-ws-80","add":"%s","port":"%s","id":"%s","aid":"0","net":"ws","type":"none","host":"","path":"/vmess","tls":""}' "$name" "$ip" "$gw_plain" "$uuid")"
  local vmess_gw80_link="vmess://$(echo -n "$vmess_json_gw" | base64 -w 0 2>/dev/null || echo -n "$vmess_json_gw" | base64 | tr -d '\n')"
  local vless_gw80_link="vless://${uuid}@${ip}:${gw_plain}?encryption=none&security=none&type=ws&path=%2Fvless&host=${ip}#${name}-vless-ws-80"
  local trojan_gw80_link="trojan://${uuid}@${ip}:${gw_plain}?security=none&type=ws&path=%2Ftrojan&host=${ip}#${name}-trojan-ws-80"

  # gRPC links (v4: HTTP/2 based, excellent for CDN/reverse proxy)
  local vmess_json_grpc
  vmess_json_grpc="$(printf '{"v":"2","ps":"%s-vmess-grpc","add":"%s","port":"%s","id":"%s","aid":"0","net":"grpc","type":"none","host":"","path":"VMessGRPC","tls":""}' "$name" "$ip" "$XPORT_VMESS_GRPC" "$uuid")"
  local vmess_grpc_link="vmess://$(echo -n "$vmess_json_grpc" | base64 -w 0 2>/dev/null || echo -n "$vmess_json_grpc" | base64 | tr -d '\n')"

  local vless_grpc_link="vless://${uuid}@${ip}:${XPORT_VLESS_GRPC}?encryption=none&security=none&type=grpc&serviceName=VLessGRPC#${name}-vless-grpc"
  local trojan_grpc_link="trojan://${uuid}@${ip}:${XPORT_TROJAN_GRPC}?security=none&type=grpc&serviceName=TrojanGRPC#${name}-trojan-grpc"

  # XHTTP links (v5: via Nginx gateway 80/8080 non-TLS — backends are localhost-only)
  local vmess_json_xhttp
  vmess_json_xhttp="$(printf '{"v":"2","ps":"%s-vmess-xhttp-80","add":"%s","port":"%s","id":"%s","aid":"0","net":"xhttp","type":"none","host":"","path":"/vmess-xhttp","tls":""}' "$name" "$ip" "$gw_plain" "$uuid")"
  local vmess_xhttp_link="vmess://$(echo -n "$vmess_json_xhttp" | base64 -w 0 2>/dev/null || echo -n "$vmess_json_xhttp" | base64 | tr -d '\n')"

  local vless_xhttp_link="vless://${uuid}@${ip}:${gw_plain}?encryption=none&security=none&type=xhttp&path=%2Fvless-xhttp&host=${ip}#${name}-vless-xhttp-80"
  local trojan_xhttp_link="trojan://${uuid}@${ip}:${gw_plain}?security=none&type=xhttp&path=%2Ftrojan-xhttp&host=${ip}#${name}-trojan-xhttp-80"

  # XHTTP via gateway alt port (8080 non-TLS)
  local vless_xhttp8080_link="vless://${uuid}@${ip}:${gw_alt}?encryption=none&security=none&type=xhttp&path=%2Fvless-xhttp&host=${ip}#${name}-vless-xhttp-8080"

  # XTLS & REALITY (foundation, untouched; xray engine only — on v2ray the 7th
  # inbound is plain TCP, so print it WITHOUT flow/security params).
  local vless_xtls_link
  if [[ "$engine" == "v2ray" ]]; then
    vless_xtls_link="vless://${uuid}@${ip}:${XPORT_VLESS_XTLS}?encryption=none&security=none&type=tcp#${name}-vless-tcp"
  else
    vless_xtls_link="vless://${uuid}@${ip}:${XPORT_VLESS_XTLS}?encryption=none&flow=xtls-rprx-vision&security=none&type=tcp#${name}-vless-xtls"
  fi
  local vless_reality_link="vless://${uuid}@${ip}:${XPORT_VLESS_REALITY}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${pbk}&sid=${sid}&type=tcp#${name}-vless-reality-tcp"

  # REALITY + gRPC (v4: best for heavy censorship + CDN compatibility)
  local vless_reality_grpc_link="vless://${uuid}@${ip}:${XPORT_VLESS_REALITY_GRPC}?encryption=none&security=reality&type=grpc&serviceName=RealityGRPC&sni=${sni}&fp=chrome&pbk=${pbk}&sid=${sid}#${name}-vless-reality-grpc"

  # REALITY + XHTTP (v5: dedicated port, no longer shares 443)
  local vless_reality_xhttp_link="vless://${uuid}@${ip}:${XPORT_VLESS_REALITY_XHTTP}?encryption=none&security=reality&type=xhttp&path=%2Freality-xhttp&sni=${sni}&fp=chrome&pbk=${pbk}&sid=${sid}#${name}-vless-reality-xhttp"

  # WS-TLS via gateway (8443 direct TLS + 443 via REALITY fallback on xray).
  # NOTE: on xray, 443 fallback speaks standard TLS (Nginx on 8443), NOT REALITY —
  # clients must use security=tls + the gateway SNI/host (no pbk/sid).
  # On v2ray there is NO xray listener on 443, so the 443 link is still printed
  # (Nginx TLS gateway may listen there via standalone setups) but marked optional.
  # When acme.sh cert exists for $SSL_DOMAIN use sni=$SSL_DOMAIN, else allowInsecure=1.
  local gw_host="${SSL_DOMAIN:-$ip}"
  local tls_note="tls+allowInsecure"
  [[ -n "${SSL_DOMAIN:-}" ]] && tls_note="tls($gw_host)"
  local vless_ws_tls_link="vless://${uuid}@${ip}:${gw_tls}?encryption=none&security=tls&sni=${gw_host}&type=ws&path=%2Fvless&host=${gw_host}#${name}-vless-ws-tls-${gw_tls}"
  local vless_ws443_link="vless://${uuid}@${ip}:443?encryption=none&security=tls&sni=${gw_host}&type=ws&path=%2Fvless&host=${gw_host}#${name}-vless-ws-tls-443"

  echo ""
  if [[ "$engine" == "v2ray" ]]; then
    echo "==================== $(T "CONNECTION LINKS v5 (7 PROTOCOLS + GATEWAY, v2ray engine)" "LINK KONEKSI v5 (7 PROTOKOL + GATEWAY, engine v2ray)" "连接链接 v5（7 种协议 + 网关，v2ray 引擎）"): $name ===================="
  else
    echo "==================== $(T "CONNECTION LINKS v5 (13 PROTOCOLS + GATEWAY, xray engine)" "LINK KONEKSI v5 (13 PROTOKOL + GATEWAY, engine xray)" "连接链接 v5（13 种协议 + 网关，xray 引擎）"): $name ===================="
  fi
  echo ""
  if [[ "$engine" == "v2ray" ]]; then
    echo "$(T "=== RECOMMENDED (v2ray: no REALITY/XHTTP — use WS/gRPC) ===" "=== REKOMENDASI (v2ray: tanpa REALITY/XHTTP — pakai WS/gRPC) ===" "=== 推荐（v2ray：无 REALITY/XHTTP — 请用 WS/gRPC）===")"
    echo ""
    echo "--- [1] VLESS + WebSocket (direct ${XPORT_VLESS_WS})"
    echo "$vless_ws_link"
    echo ""
    echo "--- [2] VLESS + gRPC (serviceName VLessGRPC)"
    echo "$vless_grpc_link"
    echo ""
    echo "--- [3] VLESS + TCP (plain @ Port ${XPORT_VLESS_XTLS})"
    echo "$vless_xtls_link"
    echo ""
    echo "--- [4] VMess + WS via gateway @ Port $gw_plain (ws://)"
    echo "$vmess_gw80_link"
    echo ""
  else
    echo "$(T "=== RECOMMENDED (Top 4) ===" "=== REKOMENDASI (4 Teratas) ===" "=== 推荐（前 4 名）===")"
    echo ""
    echo "--- [1] VLESS + XHTTP + REALITY @ Port ${XPORT_VLESS_REALITY_XHTTP} ($(T "🏆 BEST: Most HTTP-like, ultimate stealth" "🏆 TERBAIK: Paling mirip HTTP, stealth maksimal" "🏆 最佳：最像 HTTP，终极隐身"))"
    echo "$vless_reality_xhttp_link"
    echo ""
    echo "--- [2] VLESS + TCP + XTLS-Vision + REALITY @ Port ${XPORT_VLESS_REALITY} ($(T "Most efficient & anti-blocking" "Paling efisien & anti-blokir" "最高效且抗封锁"))"
    echo "$vless_reality_link"
    echo ""
    echo "--- [3] VLESS + gRPC + REALITY ($(T "Best for CDN & heavy censorship" "Terbaik untuk CDN & sensor berat" "最适合 CDN 与严重审查"))"
    echo "$vless_reality_grpc_link"
    echo ""
    echo "--- [4] VLESS + TCP + XTLS-Vision @ Port ${XPORT_VLESS_XTLS}"
    echo "$vless_xtls_link"
    echo ""
  fi
  if [[ "$engine" == "v2ray" ]]; then
    echo "$(T "=== WebSocket direct (CDN compatible) ===" "=== WebSocket direct (kompatibel CDN) ===" "=== WebSocket 直连（兼容 CDN）===")"
  else
    echo "$(T "=== XHTTP via Gateway (newest, most HTTP-like: 80/8080) ===" "=== XHTTP via Gateway (terbaru, paling mirip HTTP: 80/8080) ===" "=== 经网关 XHTTP（最新，最像 HTTP：80/8080）===")"
    echo ""
    echo "--- [5] VMess + XHTTP @ Port $gw_plain (gateway)"
    echo "$vmess_xhttp_link"
    echo ""
    echo "--- [6] VLESS + XHTTP @ Port $gw_plain (gateway)"
    echo "$vless_xhttp_link"
    echo ""
    echo "--- [7] Trojan + XHTTP @ Port $gw_plain (gateway)"
    echo "$trojan_xhttp_link"
    echo ""
    echo "$(T "=== WebSocket direct (CDN compatible) ===" "=== WebSocket direct (kompatibel CDN) ===" "=== WebSocket 直连（兼容 CDN）===")"
  fi
  echo ""
  echo "--- [8] VMess + WebSocket (direct ${XPORT_VMESS_WS})"
  echo "$vmess_link"
  echo ""
  echo "--- [9] VLESS + WebSocket (direct ${XPORT_VLESS_WS})"
  echo "$vless_ws_link"
  echo ""
  echo "--- [10] Trojan + WebSocket (direct ${XPORT_TROJAN_WS})"
  echo "$trojan_link"
  echo ""
  echo "$(T "=== WebSocket via Gateway (80 non-TLS / 8443+443 TLS) ===" "=== WebSocket via Gateway (80 non-TLS / 8443+443 TLS) ===" "=== 经网关 WebSocket (80 明文 / 8443+443 TLS) ===")"
  echo ""
  echo "--- [G1] VMess + WS @ Port $gw_plain (gateway, ws://)"
  echo "$vmess_gw80_link"
  echo ""
  echo "--- [G2] VLESS + WS @ Port $gw_plain (gateway, ws://)"
  echo "$vless_gw80_link"
  echo ""
  echo "--- [G3] Trojan + WS @ Port $gw_plain (gateway, ws://)"
  echo "$trojan_gw80_link"
  echo ""
  echo "--- [G4] VLESS + WS-TLS @ Port $gw_tls (gateway, wss:// $tls_note)"
  echo "$vless_ws_tls_link"
  echo ""
  if [[ "$engine" == "v2ray" ]]; then
    echo "--- [G5] VLESS + WS-TLS @ Port 443 (optional: only when Nginx TLS listens on 443, wss:// $tls_note)"
  else
    echo "--- [G5] VLESS + WS-TLS @ Port 443 (via REALITY fallback, wss:// $tls_note — needs gateway SNI, NOT reality pbk)"
  fi
  echo "$vless_ws443_link"
  echo ""
  if [[ "$engine" == "v2ray" ]]; then
    echo "--- [G6] VLESS + WS @ Port $gw_alt (gateway alt, ws://)"
    echo "vless://${uuid}@${ip}:${gw_alt}?encryption=none&security=none&type=ws&path=%2Fvless&host=${ip}#${name}-vless-ws-8080"
  else
    echo "--- [G6] VLESS + XHTTP @ Port $gw_alt (gateway alt)"
    echo "$vless_xhttp8080_link"
  fi
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
    if [[ "$engine" == "v2ray" ]]; then
      echo "$(T "QR code (VLESS WS direct — scan with v2rayNG / NekoBox / Streisand):" "QR Code (VLESS WS direct — pindai dengan v2rayNG / NekoBox / Streisand):" "二维码（VLESS WS 直连——请用 v2rayNG / NekoBox / Streisand 扫描）：")"
      qrencode -t ansiutf8 "$vless_ws_link" || true
    else
      echo "$(T "QR code (VLESS REALITY XHTTP — scan with v2rayNG / NekoBox / Streisand):" "QR Code (VLESS REALITY XHTTP — pindai dengan v2rayNG / NekoBox / Streisand):" "二维码（VLESS REALITY XHTTP——请用 v2rayNG / NekoBox / Streisand 扫描）：")"
      qrencode -t ansiutf8 "$vless_reality_xhttp_link" || true
    fi
  fi

  XRAY_LAST_VMESS="$vmess_link"
  XRAY_LAST_REALITY="$vless_reality_link"
  XRAY_LAST_REALITY_GRPC="$vless_reality_grpc_link"
  XRAY_LAST_REALITY_XHTTP="$vless_reality_xhttp_link"
  export XRAY_LAST_VMESS XRAY_LAST_REALITY XRAY_LAST_REALITY_GRPC XRAY_LAST_REALITY_XHTTP

  # v4.9: save the same block to the re-readable summary file (default ON;
  # pass SAVE=0 as $3 for display-only, e.g. from show-account.sh).
  # v2ray engine: only 7 inbounds exist — save matching links, never REALITY/XHTTP.
  if [[ "$save" == "1" ]]; then
    if [[ "$engine" == "v2ray" ]]; then
      summary_block "Xray user: $name" <<EOF
Xray user : $name (v2ray engine: 7 inbounds, no REALITY/XHTTP/XTLS-Vision)
UUID      : $uuid
Server IP : $ip
[1] VLESS WS direct: $vless_ws_link
[2] VLESS gRPC: $vless_grpc_link
[3] VLESS TCP plain: $vless_xtls_link
[8] VMess WS direct: $vmess_link
[10] Trojan WS direct: $trojan_link
[G1] VMess WS gw $gw_plain: $vmess_gw80_link
[G2] VLESS WS gw $gw_plain: $vless_gw80_link
[G3] Trojan WS gw $gw_plain: $trojan_gw80_link
[G4] VLESS WS-TLS gw $gw_tls ($tls_note): $vless_ws_tls_link
[G5] VLESS WS-TLS port 443 optional ($tls_note): $vless_ws443_link
[11] VMess gRPC: $vmess_grpc_link
[12] VLESS gRPC: $vless_grpc_link
[13] Trojan gRPC: $trojan_grpc_link
SSH-WS : ws://$ip:$gw_plain/ssh-ws and wss://$ip:$gw_tls/ssh-ws (user/pass auth, see SSH block)
WG-WS  : ws://$ip:$gw_plain/wg-ws and wss://$ip:$gw_tls/wg-ws (wstunnel -> local WG, see WG-WS block)
Re-show: sudo ./show-account.sh $name [--qr] | cat $VPN_SUMMARY_FILE
EOF
    else
      summary_block "Xray user: $name" <<EOF
Xray user : $name
UUID      : $uuid
Server IP : $ip
SNI       : $sni
[1 BEST] VLESS XHTTP REALITY ${XPORT_VLESS_REALITY_XHTTP}: $vless_reality_xhttp_link
[2] VLESS TCP REALITY ${XPORT_VLESS_REALITY}: $vless_reality_link
[3] VLESS gRPC REALITY: $vless_reality_grpc_link
[4] VLESS XTLS ${XPORT_VLESS_XTLS}: $vless_xtls_link
[5] VMess XHTTP gw $gw_plain: $vmess_xhttp_link
[6] VLESS XHTTP gw $gw_plain: $vless_xhttp_link
[7] Trojan XHTTP gw $gw_plain: $trojan_xhttp_link
[8] VMess WS direct: $vmess_link
[9] VLESS WS direct: $vless_ws_link
[10] Trojan WS direct: $trojan_link
[G1] VMess WS gw $gw_plain: $vmess_gw80_link
[G2] VLESS WS gw $gw_plain: $vless_gw80_link
[G3] Trojan WS gw $gw_plain: $trojan_gw80_link
[G4] VLESS WS-TLS gw $gw_tls ($tls_note): $vless_ws_tls_link
[G5] VLESS WS-TLS via 443 fallback ($tls_note): $vless_ws443_link
[G6] VLESS XHTTP gw $gw_alt: $vless_xhttp8080_link
[11] VMess gRPC: $vmess_grpc_link
[12] VLESS gRPC: $vless_grpc_link
[13] Trojan gRPC: $trojan_grpc_link
SSH-WS : ws://$ip:$gw_plain/ssh-ws and wss://$ip:$gw_tls/ssh-ws (user/pass auth, see SSH block)
WG-WS  : ws://$ip:$gw_plain/wg-ws and wss://$ip:$gw_tls/wg-ws (wstunnel -> local WG, see WG-WS block)
Re-show: sudo ./show-account.sh $name [--qr] | cat $VPN_SUMMARY_FILE
EOF
    fi
  fi
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
  # Engine-aware restart validator (v5: xray `run -test`, v2ray `test -c`)
  local _engine="${XRAY_ENGINE:-$XRAY_ENGINE_DEFAULT}"
  local -a _test_cmd=("$XRAY_BIN" run -test -config "$XRAY_CONFIG")
  [[ "$_engine" == "v2ray" ]] && _test_cmd=("$XRAY_BIN" test -c "$XRAY_CONFIG")

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
  track_temp "$tmp"
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

  # v4.9: validate BEFORE restart — broken config never touches the running service
  # v5: engine-aware (xray `run -test`, v2ray `test -c`).
  svc_restart_tested "xray" "${_test_cmd[@]}"

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
  # Engine-aware restart validator (v5: xray `run -test`, v2ray `test -c`)
  local _engine_rm="${XRAY_ENGINE:-$XRAY_ENGINE_DEFAULT}"
  local -a _test_cmd_rm=("$XRAY_BIN" run -test -config "$XRAY_CONFIG")
  [[ "$_engine_rm" == "v2ray" ]] && _test_cmd_rm=("$XRAY_BIN" test -c "$XRAY_CONFIG")

  # Look up the user UUID from the database
  local uuid=""
  if [[ -f "$XRAY_ACCOUNTS_DB" ]]; then
    uuid="$(awk -F: -v u="$name" '$1==u {print $2}' "$XRAY_ACCOUNTS_DB" | head -n1)"
  fi
  [[ -n "$uuid" ]] || die "$(T "Xray user '$name' was not found." "User Xray '$name' tidak ditemukan." "未找到 Xray 用户 '$name'。")"

  local tmp
  tmp="$(mktemp)"
  track_temp "$tmp"
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
  # v4.9: validate BEFORE restart — broken config never touches the running service
  # v5: engine-aware (xray `run -test`, v2ray `test -c`).
  svc_restart_tested "xray" "${_test_cmd_rm[@]}"

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
