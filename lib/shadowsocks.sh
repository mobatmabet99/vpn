#!/bin/bash
#
# lib/shadowsocks.sh — Optional Shadowsocks module (ssserver / shadowsocks-rust, trilingual EN/ID/ZH)
# Auto-generates password, AEAD cipher, QR code & ss:// URI
# Branding: wrwb Store
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This file is a library. Do not run it directly." >&2
  exit 1
fi

SS_CONFIG_DIR="/etc/shadowsocks"
SS_CONFIG_FILE="$SS_CONFIG_DIR/config.json"
SS_PARAMS="/etc/shadowsocks/params"

# Stable shadowsocks-rust version (check latest at
# https://github.com/shadowsocks/shadowsocks-rust/releases).
# Updated regularly so connections use the most efficient & secure build.
SS_VERSION_DEFAULT="v1.25.0"

# Default AEAD cipher — most efficient & widely supported by all modern clients.
# Low-CPU alternative for small devices/VMs: "2022-blake3-aes-128-gcm".
SS_METHOD_DEFAULT="2022-blake3-aes-256-gcm"

install_shadowsocks_binary() {
  log_step "$(T "Downloading and preparing the Shadowsocks-rust server..." "Mengunduh dan menyiapkan Shadowsocks-rust server..." "正在下载并准备 Shadowsocks-rust 服务器...")"

  local arch
  arch="$(uname -m)"
  local target_arch=""
  case "$arch" in
    x86_64|amd64) target_arch="x86_64-unknown-linux-gnu" ;;
    aarch64|arm64) target_arch="aarch64-unknown-linux-gnu" ;;
    armv7l|armhf) target_arch="armv7-unknown-linux-gnueabihf" ;;
    *) die "$(T "CPU architecture '$arch' is not supported automatically for the Shadowsocks binary." "Arsitektur CPU '$arch' belum didukung otomatis untuk Shadowsocks binary." "CPU 架构 '$arch' 不支持 Shadowsocks 可执行文件自动安装。")" ;;
  esac

  mkdir -p "$SS_CONFIG_DIR" /usr/local/bin
  chmod 700 "$SS_CONFIG_DIR"

  SS_VER_LABEL="${SS_VERSION:-$SS_VERSION_DEFAULT}"
  if ! command -v ssserver &>/dev/null; then
    local ss_ver="$SS_VER_LABEL"
    local ss_url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${ss_ver}/shadowsocks-${ss_ver}.${target_arch}.tar.xz"

    log_info "$(T "Downloading shadowsocks-rust ($ss_ver) from GitHub..." "Mengunduh shadowsocks-rust ($ss_ver) dari GitHub..." "正在从 GitHub 下载 shadowsocks-rust（$ss_ver）...")"
    local tmp_tar
    tmp_tar="$(mktemp --suffix=.tar.xz)"
    if curl -fsSL "$ss_url" -o "$tmp_tar"; then
      tar -xJf "$tmp_tar" -C /usr/local/bin ssserver 2>/dev/null || tar -xvf "$tmp_tar" -C /usr/local/bin ssserver
      chmod 755 /usr/local/bin/ssserver
      rm -f "$tmp_tar"
      log_success "$(T "ssserver installed at /usr/local/bin/ssserver" "ssserver berhasil dipasang di /usr/local/bin/ssserver" "ssserver 已安装到 /usr/local/bin/ssserver")"
    else
      rm -f "$tmp_tar"
      # Fall back to the distro package manager when the download fails
      log_warn "$(T "Binary download failed, trying the distro package manager..." "Download binary gagal, mencoba package manager distro..." "可执行文件下载失败，正尝试使用发行版软件包管理器...")"
      if command -v apt-get &>/dev/null; then
        apt-get install -y shadowsocks-libev || die "$(T "Failed to install Shadowsocks." "Gagal memasang Shadowsocks." "安装 Shadowsocks 失败。")"
      elif command -v dnf &>/dev/null; then
        dnf install -y shadowsocks-libev || die "$(T "Failed to install Shadowsocks." "Gagal memasang Shadowsocks." "安装 Shadowsocks 失败。")"
      fi
    fi
  else
    log_info "$(T "ssserver is already installed on the system." "ssserver sudah terpasang di sistem." "ssserver 已安装在系统中。")"
  fi
}

ss_setup_server() {
  local port="${1:-8388}"
  local password="${2:-$(gen_password 20)}"
  local method="${3:-$SS_METHOD_DEFAULT}"
  local pub_ip="${4:-$(get_public_ip)}"

  install_shadowsocks_binary

  log_step "$(T "Creating the Shadowsocks server config..." "Membuat konfigurasi server Shadowsocks..." "正在创建 Shadowsocks 服务器配置...")"
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

  # Open TCP & UDP in the firewall
  open_firewall_port "$port" "tcp" "Shadowsocks"
  open_firewall_port "$port" "udp" "Shadowsocks"

  # Save parameters
  cat > "$SS_PARAMS" <<EOF
SS_PUB_IP="$pub_ip"
SS_PORT="$port"
SS_PASSWORD="$password"
SS_METHOD="$method"
EOF
  chmod 600 "$SS_PARAMS"

  log_success "$(T "Shadowsocks is active on port $port (method: $method)" "Shadowsocks aktif di port $port (metode: $method)" "Shadowsocks 已在端口 $port 运行（加密方式：$method）")"

  # Build the SIP002 Shadowsocks URI: ss://base64(method:password@host:port)#tag
  local userinfo
  userinfo="$(echo -n "${method}:${password}" | base64 -w 0 2>/dev/null || echo -n "${method}:${password}" | base64)"
  local ss_uri="ss://${userinfo}@${pub_ip}:${port}#VPN-Shadowsocks"

  echo ""
  echo "==================== SHADOWSOCKS CONNECTION ===================="
  echo "$(T "Client URI : $ss_uri" "URI Client : $ss_uri" "客户端 URI：$ss_uri")"
  echo "$(T "Method     : $method" "Metode     : $method" "加密方式   ：$method")"
  echo "$(T "Port       : $port" "Port       : $port" "端口       ：$port")"
  echo "Password   : $password"
  echo "----------------------------------------------------------------"
  if command -v qrencode &>/dev/null; then
    echo "$(T "Scan the Shadowsocks QR code:" "Scan QR Code Shadowsocks:" "扫描 Shadowsocks 二维码：")"
    qrencode -t ansiutf8 "$ss_uri" || true
  fi
  echo "================================================================="
}
