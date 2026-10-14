#!/bin/bash
#
# lib/openvpn.sh — Optional OpenVPN module (trilingual EN/ID/ZH)
# Provides OpenVPN server setup and client profile (.ovpn) export
# Branding: wrwb Store
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This file is a library. Do not run it directly." >&2
  exit 1
fi

OVPN_DIR="/etc/openvpn"
OVPN_SERVER_DIR="$OVPN_DIR/server"
OVPN_CLIENTS_DIR="$OVPN_DIR/clients"
OVPN_PARAMS="/etc/openvpn/params"

install_openvpn_packages() {
  log_step "$(T "Installing OpenVPN & Easy-RSA dependencies..." "Menginstal dependensi OpenVPN & Easy-RSA..." "正在安装 OpenVPN 和 Easy-RSA 依赖...")"
  detect_os

  case "$PKG_MGR" in
    apt)
      apt-get update -y || true
      apt-get install -y openvpn easy-rsa openssl iptables curl qrencode
      ;;
    dnf|yum)
      $PKG_MGR install -y epel-release || true
      $PKG_MGR install -y openvpn easy-rsa openssl iptables curl qrencode
      ;;
    pacman)
      pacman -Sy --noconfirm openvpn easy-rsa openssl iptables curl qrencode
      ;;
    *)
      die "$(T "Package manager $PKG_MGR is not supported for automatic OpenVPN install." "Package manager $PKG_MGR belum didukung untuk instalasi OpenVPN otomatis." "软件包管理器 $PKG_MGR 不支持自动安装 OpenVPN。")"
      ;;
  esac

  log_success "$(T "OpenVPN packages installed." "Paket OpenVPN terinstal." "OpenVPN 软件包已安装。")"
}

ovpn_setup_server() {
  local port="${1:-1194}"
  local proto="${2:-udp}"
  local iface="${3:-$(get_default_iface)}"
  local pub_ip="${4:-$(get_public_ip)}"

  mkdir -p "$OVPN_SERVER_DIR" "$OVPN_CLIENTS_DIR"
  chmod 700 "$OVPN_SERVER_DIR" "$OVPN_CLIENTS_DIR"

  log_step "$(T "Setting up the OpenVPN Public Key Infrastructure (PKI)..." "Menyiapkan Public Key Infrastructure (PKI) OpenVPN..." "正在搭建 OpenVPN 公钥基础设施（PKI）...")"
  local easyrsa_dir="/etc/openvpn/easy-rsa"
  rm -rf "$easyrsa_dir"
  mkdir -p "$easyrsa_dir"

  # Locate the easy-rsa template
  local src_easyrsa=""
  for p in /usr/share/easy-rsa /usr/share/easy-rsa/3* /usr/share/doc/easy-rsa; do
    if [[ -d "$p" && -f "$p/easyrsa" ]]; then
      src_easyrsa="$p"
      break
    fi
  done

  if [[ -z "$src_easyrsa" ]]; then
    # Fall back to find when the location varies between distros
    src_easyrsa="$(find /usr -type f -name easyrsa 2>/dev/null | head -n1 | xargs -r dirname)"
  fi

  if [[ -z "$src_easyrsa" || ! -f "$src_easyrsa/easyrsa" ]]; then
    die "$(T "The easy-rsa binary was not found. Make sure the easy-rsa package is installed." "Biner easy-rsa tidak ditemukan. Pastikan paket easy-rsa sudah terpasang." "未找到 easy-rsa 可执行文件。请确保已安装 easy-rsa 软件包。")"
  fi

  cp -r "$src_easyrsa"/* "$easyrsa_dir/"
  cd "$easyrsa_dir" || die "$(T "Cannot enter $easyrsa_dir" "Gagal masuk $easyrsa_dir" "无法进入 $easyrsa_dir")"

  # Non-interactive PKI init
  export EASYRSA_BATCH=1
  export EASYRSA_CERT_EXPIRE=3650
  ./easyrsa init-pki
  ./easyrsa build-ca nopass
  ./easyrsa gen-dh
  ./easyrsa build-server-full server nopass
  openvpn --genkey secret "$OVPN_SERVER_DIR/tc.key"

  # Copy certs into the server dir
  cp pki/ca.crt "$OVPN_SERVER_DIR/"
  cp pki/dh.pem "$OVPN_SERVER_DIR/"
  cp pki/issued/server.crt "$OVPN_SERVER_DIR/"
  cp pki/private/server.key "$OVPN_SERVER_DIR/"
  chmod 600 "$OVPN_SERVER_DIR/server.key" "$OVPN_SERVER_DIR/tc.key"

  # Write the server config
  cat > "$OVPN_SERVER_DIR/server.conf" <<EOF
port $port
proto $proto
dev tun
ca $OVPN_SERVER_DIR/ca.crt
cert $OVPN_SERVER_DIR/server.crt
key $OVPN_SERVER_DIR/server.key
dh $OVPN_SERVER_DIR/dh.pem
tls-crypt $OVPN_SERVER_DIR/tc.key
topology subnet
server 10.8.0.0 255.255.255.0
server-ipv6 fd42:42:43::/112
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 1.0.0.1"
push "route-ipv6 2000::/3"
keepalive 10 120
# Cipher modern & efisien (urutan prioritas: ChaCha20 untuk CPU tanpa AES-NI,
# AES-GCM untuk CPU dengan akselerasi hardware). TLS minimal 1.3 + SHA-512.
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
data-ciphers-fallback AES-256-GCM
auth SHA512
tls-version-min 1.3
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384:TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384:TLS-ECDHE-ECDSA-WITH-CHACHA20-POLY1305:TLS-ECDHE-RSA-WITH-CHACHA20-POLY1305
user nobody
group nogroup
persist-key
persist-tun
status /var/log/openvpn-status.log
verb 3
explicit-exit-notify 1
EOF
  # explicit-exit-notify is only valid for UDP — remove it for TCP
  if [[ "$proto" != "udp" ]]; then
    sed -i '/^explicit-exit-notify/d' "$OVPN_SERVER_DIR/server.conf"
  fi

  # Fix group for RHEL (nobody group is usually nobody)
  if [[ "$OS_FAMILY" == "rhel" ]]; then
    sed -i 's/group nogroup/group nobody/' "$OVPN_SERVER_DIR/server.conf"
  fi

  # Save OpenVPN params
  cat > "$OVPN_PARAMS" <<EOF
OVPN_PUB_IP="$pub_ip"
OVPN_PORT="$port"
OVPN_PROTO="$proto"
OVPN_IFACE="$iface"
EOF
  chmod 600 "$OVPN_PARAMS"

  # Enable the service
  log_step "$(T "Enabling the OpenVPN service..." "Mengaktifkan service OpenVPN..." "正在启用 OpenVPN 服务...")"
  if systemctl list-unit-files | grep -q "openvpn-server@"; then
    systemctl daemon-reload
    systemctl enable openvpn-server@server.service
    systemctl restart openvpn-server@server.service
  else
    systemctl daemon-reload
    systemctl enable openvpn@server.service
    systemctl restart openvpn@server.service
  fi

  # Open the firewall
  open_firewall_port "$port" "$proto" "OpenVPN"

  # NAT rules for OpenVPN
  iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$iface" -j MASQUERADE 2>/dev/null || true
  iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT 2>/dev/null || true
  iptables -I FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

  log_success "$(T "OpenVPN server is ready on port $port/$proto." "OpenVPN server berhasil disiapkan pada port $port/$proto." "OpenVPN 服务器已在端口 $port/$proto 就绪。")"
}

ovpn_create_client() {
  local name="$1"
  validate_client_name "$name"
  [[ -f "$OVPN_PARAMS" ]] || die "$(T "OpenVPN is not installed yet. Run the server setup first." "OpenVPN belum terpasang. Jalankan setup server dulu." "OpenVPN 尚未安装。请先运行服务器设置。")"
  # shellcheck disable=SC1090
  source "$OVPN_PARAMS"

  local easyrsa_dir="/etc/openvpn/easy-rsa"
  cd "$easyrsa_dir" || die "$(T "Directory $easyrsa_dir was not found." "Direktori $easyrsa_dir tidak ditemukan." "未找到目录 $easyrsa_dir。")"

  export EASYRSA_BATCH=1
  export EASYRSA_CERT_EXPIRE=3650
  ./easyrsa build-client-full "$name" nopass

  local client_conf="$OVPN_CLIENTS_DIR/${name}.ovpn"

  cat > "$client_conf" <<EOF
client
dev tun
proto $OVPN_PROTO
remote $OVPN_PUB_IP $OVPN_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
# Wajib selaras dengan server: cipher modern + auth SHA-512 + TLS 1.3
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
data-ciphers-fallback AES-256-GCM
auth SHA512
tls-version-min 1.3
verb 3

<ca>
$(cat "$OVPN_SERVER_DIR/ca.crt")
</ca>
<cert>
$(awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' "$easyrsa_dir/pki/issued/${name}.crt")
</cert>
<key>
$(cat "$easyrsa_dir/pki/private/${name}.key")
</key>
<tls-crypt>
$(cat "$OVPN_SERVER_DIR/tc.key")
</tls-crypt>
EOF
  chmod 600 "$client_conf"

  log_success "$(T "OpenVPN client '$name' created at: $client_conf" "Client OpenVPN '$name' berhasil dibuat di: $client_conf" "OpenVPN 客户端 '$name' 已创建于：$client_conf")"
  LAST_OVPN_CONF="$client_conf"
}

ovpn_remove_client() {
  local name="$1"
  validate_client_name "$name"
  local easyrsa_dir="/etc/openvpn/easy-rsa"

  if [[ -d "$easyrsa_dir" ]]; then
    cd "$easyrsa_dir" || return 1
    export EASYRSA_BATCH=1
    ./easyrsa revoke "$name" || true
    ./easyrsa gen-crl || true
    cp pki/crl.pem "$OVPN_SERVER_DIR/" 2>/dev/null || true
    chmod 644 "$OVPN_SERVER_DIR/crl.pem" 2>/dev/null || true
  fi

  rm -f "$OVPN_CLIENTS_DIR/${name}.ovpn"
  log_success "$(T "OpenVPN client '$name' revoked and its file removed." "Client OpenVPN '$name' dicabut dan filenya dihapus." "OpenVPN 客户端 '$name' 已吊销，文件已删除。")"
}
