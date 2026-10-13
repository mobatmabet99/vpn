#!/bin/bash
#
# lib/shadowsocks.sh — Modul opsional Shadowsocks (ssservice / shadowsocks-rust)
# Auto-generate password, AEAD cipher, QR code & URI ss://
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "File ini adalah library. Jangan dijalankan langsung." >&2
  exit 1
fi

SS_CONFIG_DIR="/etc/shadowsocks"
SS_CONFIG_FILE="$SS_CONFIG_DIR/config.json"
SS_PARAMS="/etc/shadowsocks/params"

# Versi stabil shadowsocks-rust (cek terbaru di
# https://github.com/shadowsocks/shadowsocks-rust/releases).
# Diperbarui berkala agar koneksi memakai build paling efisien & aman.
SS_VERSION_DEFAULT="v1.25.0"

# Cipher AEAD default — paling efisien & didukung luas oleh semua client modern.
# Alternatif hemat CPU untuk perangkat/VM kecil: "2022-blake3-aes-128-gcm".
SS_METHOD_DEFAULT="2022-blake3-aes-256-gcm"

install_shadowsocks_binary() {
  log_step "Mengunduh dan menyiapkan Shadowsocks-rust server..."

  local arch
  arch="$(uname -m)"
  local target_arch=""
  case "$arch" in
    x86_64|amd64) target_arch="x86_64-unknown-linux-gnu" ;;
    aarch64|arm64) target_arch="aarch64-unknown-linux-gnu" ;;
    armv7l|armhf) target_arch="armv7-unknown-linux-gnueabihf" ;;
    *) die "Arsitektur CPU '$arch' belum didukung otomatis untuk Shadowsocks binary." ;;
  esac

  mkdir -p "$SS_CONFIG_DIR" /usr/local/bin
  chmod 700 "$SS_CONFIG_DIR"

  SS_VER_LABEL="${SS_VERSION:-$SS_VERSION_DEFAULT}"
  if ! command -v ssserver &>/dev/null; then
    local ss_ver="$SS_VER_LABEL"
    local ss_url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${ss_ver}/shadowsocks-${ss_ver}.${target_arch}.tar.xz"

    log_info "Mengunduh shadowsocks-rust ($ss_ver) dari GitHub..."
    local tmp_tar
    tmp_tar="$(mktemp --suffix=.tar.xz)"
    if curl -fsSL "$ss_url" -o "$tmp_tar"; then
      tar -xJf "$tmp_tar" -C /usr/local/bin ssserver 2>/dev/null || tar -xvf "$tmp_tar" -C /usr/local/bin ssserver
      chmod 755 /usr/local/bin/ssserver
      rm -f "$tmp_tar"
      log_success "ssserver berhasil dipasang di /usr/local/bin/ssserver"
    else
      rm -f "$tmp_tar"
      # Fallback ke apt/dnf package jika download gagal
      log_warn "Download binary gagal, mencoba package manager distro..."
      if command -v apt-get &>/dev/null; then
        apt-get install -y shadowsocks-libev || die "Gagal memasang Shadowsocks."
      elif command -v dnf &>/dev/null; then
        dnf install -y shadowsocks-libev || die "Gagal memasang Shadowsocks."
      fi
    fi
  else
    log_info "ssserver sudah terpasang di sistem."
  fi
}

ss_setup_server() {
  local port="${1:-8388}"
  local password="${2:-$(gen_password 20)}"
  local method="${3:-$SS_METHOD_DEFAULT}"
  local pub_ip="${4:-$(get_public_ip)}"

  install_shadowsocks_binary

  log_step "Membuat konfigurasi server Shadowsocks..."
  cat > "$SS_CONFIG_FILE" <<EOF
{
    "server": "::",
    "server_port": $port,
    "password": "$password",
    "method": "$method",
    "timeout": 300,
    "fast_open": false,
    "mode": "tcp_and_udp"
}
EOF
  chmod 600 "$SS_CONFIG_FILE"

  # Buat systemd service unit
  cat > /etc/systemd/system/shadowsocks-rust.service <<EOF
[Unit]
Description=Shadowsocks-rust Server Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/ssserver -c $SS_CONFIG_FILE
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable shadowsocks-rust.service
  systemctl restart shadowsocks-rust.service

  # Buka firewall TCP & UDP
  open_firewall_port "$port" "tcp"
  open_firewall_port "$port" "udp"

  # Simpan parameter
  cat > "$SS_PARAMS" <<EOF
SS_PUB_IP="$pub_ip"
SS_PORT="$port"
SS_PASSWORD="$password"
SS_METHOD="$method"
EOF
  chmod 600 "$SS_PARAMS"

  log_success "Shadowsocks aktif di port $port (metode: $method)"

  # Buat URI Shadowsocks format SIP002: ss://base64(method:password@host:port)#tag
  local userinfo
  userinfo="$(echo -n "${method}:${password}" | base64 -w 0 2>/dev/null || echo -n "${method}:${password}" | base64)"
  local ss_uri="ss://${userinfo}@${pub_ip}:${port}#VPN-Shadowsocks"

  echo ""
  echo "==================== SHADOWSOCKS CONNECTION ===================="
  echo "URI Client : $ss_uri"
  echo "Metode     : $method"
  echo "Port       : $port"
  echo "Password   : $password"
  echo "----------------------------------------------------------------"
  if command -v qrencode &>/dev/null; then
    echo "Scan QR Code Shadowsocks:"
    qrencode -t ansiutf8 "$ss_uri" || true
  fi
  echo "================================================================="
}
