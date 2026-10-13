#!/bin/bash
#
# lib/openvpn.sh — Modul opsional OpenVPN
# Menyediakan setup server OpenVPN dan export profil client (.ovpn)
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "File ini adalah library. Jangan dijalankan langsung." >&2
  exit 1
fi

OVPN_DIR="/etc/openvpn"
OVPN_SERVER_DIR="$OVPN_DIR/server"
OVPN_CLIENTS_DIR="$OVPN_DIR/clients"
OVPN_PARAMS="/etc/openvpn/params"

install_openvpn_packages() {
  log_step "Menginstal dependensi OpenVPN & Easy-RSA..."
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
      die "Package manager $PKG_MGR belum didukung untuk instalasi OpenVPN otomatis."
      ;;
  esac

  log_success "Paket OpenVPN terinstal."
}

ovpn_setup_server() {
  local port="${1:-1194}"
  local proto="${2:-udp}"
  local iface="${3:-$(get_default_iface)}"
  local pub_ip="${4:-$(get_public_ip)}"

  mkdir -p "$OVPN_SERVER_DIR" "$OVPN_CLIENTS_DIR"
  chmod 700 "$OVPN_SERVER_DIR" "$OVPN_CLIENTS_DIR"

  log_step "Menyiapkan Public Key Infrastructure (PKI) OpenVPN..."
  local easyrsa_dir="/etc/openvpn/easy-rsa"
  rm -rf "$easyrsa_dir"
  mkdir -p "$easyrsa_dir"

  # Cari template easy-rsa
  local src_easyrsa=""
  for p in /usr/share/easy-rsa /usr/share/easy-rsa/3* /usr/share/doc/easy-rsa; do
    if [[ -d "$p" && -f "$p/easyrsa" ]]; then
      src_easyrsa="$p"
      break
    fi
  done

  if [[ -z "$src_easyrsa" ]]; then
    # Cari dengan find jika lokasi bervariasi antar distro
    src_easyrsa="$(find /usr -type f -name easyrsa 2>/dev/null | head -n1 | xargs -r dirname)"
  fi

  if [[ -z "$src_easyrsa" || ! -f "$src_easyrsa/easyrsa" ]]; then
    die "Biner easy-rsa tidak ditemukan. Pastikan paket easy-rsa sudah terpasang."
  fi

  cp -r "$src_easyrsa"/* "$easyrsa_dir/"
  cd "$easyrsa_dir" || die "Gagal masuk $easyrsa_dir"

  # Inisialisasi PKI non-interaktif
  export EASYRSA_BATCH=1
  export EASYRSA_CERT_EXPIRE=3650
  ./easyrsa init-pki
  ./easyrsa build-ca nopass
  ./easyrsa gen-dh
  ./easyrsa build-server-full server nopass
  openvpn --genkey secret "$OVPN_SERVER_DIR/tc.key"

  # Salin certs ke server dir
  cp pki/ca.crt "$OVPN_SERVER_DIR/"
  cp pki/dh.pem "$OVPN_SERVER_DIR/"
  cp pki/issued/server.crt "$OVPN_SERVER_DIR/"
  cp pki/private/server.key "$OVPN_SERVER_DIR/"
  chmod 600 "$OVPN_SERVER_DIR/server.key" "$OVPN_SERVER_DIR/tc.key"

  # Tulis konfigurasi server
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
  # explicit-exit-notify hanya valid untuk UDP — hapus bila protokol TCP
  if [[ "$proto" != "udp" ]]; then
    sed -i '/^explicit-exit-notify/d' "$OVPN_SERVER_DIR/server.conf"
  fi

  # Fix group for RHEL (nobody group is usually nobody)
  if [[ "$OS_FAMILY" == "rhel" ]]; then
    sed -i 's/group nogroup/group nobody/' "$OVPN_SERVER_DIR/server.conf"
  fi

  # Simpan params OpenVPN
  cat > "$OVPN_PARAMS" <<EOF
OVPN_PUB_IP="$pub_ip"
OVPN_PORT="$port"
OVPN_PROTO="$proto"
OVPN_IFACE="$iface"
EOF
  chmod 600 "$OVPN_PARAMS"

  # Aktifkan service
  log_step "Mengaktifkan service OpenVPN..."
  if systemctl list-unit-files | grep -q "openvpn-server@"; then
    systemctl daemon-reload
    systemctl enable openvpn-server@server.service
    systemctl restart openvpn-server@server.service
  else
    systemctl daemon-reload
    systemctl enable openvpn@server.service
    systemctl restart openvpn@server.service
  fi

  # Buka firewall
  open_firewall_port "$port" "$proto"

  # Aturan NAT untuk OpenVPN
  iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$iface" -j MASQUERADE 2>/dev/null || true
  iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT 2>/dev/null || true
  iptables -I FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

  log_success "OpenVPN server berhasil disiapkan pada port $port/$proto."
}

ovpn_create_client() {
  local name="$1"
  validate_client_name "$name"
  [[ -f "$OVPN_PARAMS" ]] || die "OpenVPN belum terpasang. Jalankan setup server dulu."
  # shellcheck disable=SC1090
  source "$OVPN_PARAMS"

  local easyrsa_dir="/etc/openvpn/easy-rsa"
  cd "$easyrsa_dir" || die "Direktori $easyrsa_dir tidak ditemukan."

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

  log_success "Client OpenVPN '$name' berhasil dibuat di: $client_conf"
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
  log_success "Client OpenVPN '$name' dicabut dan filenya dihapus."
}
