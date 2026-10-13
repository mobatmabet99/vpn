#!/bin/bash
#
# lib/ssh.sh — SSH VPN module (Dropbear/OpenSSH + WebSocket tunneling, trilingual EN/ID/ZH)
# Branding: wrwb Store
#
# SSH is the second default tunneling protocol after WireGuard:
#   - Easy with any client (OpenSSH client, Termius, etc.)
#   - Supports direct SSH (port 22/tcp) and SSH over WebSocket (port 80/443)
#   - User management via add-ssh-user.sh / remove-ssh-user.sh
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This file is a library. Do not run it directly." >&2
  exit 1
fi

SSH_DIR="/etc/ssh-vpn"
SSH_PARAMS="$SSH_DIR/params"
SSH_ACCOUNTS_DB="$SSH_DIR/accounts.db"
STUNNEL_CONF="/etc/stunnel/stunnel.conf"
WS_SERVICE="ssh-ws"

install_ssh_packages() {
  log_step "$(T "Installing SSH VPN components (OpenSSH, Dropbear, Stunnel, WebSocket)..." "Menginstal komponen SSH VPN (OpenSSH, Dropbear, Stunnel, WebSocket)..." "正在安装 SSH VPN 组件（OpenSSH、Dropbear、Stunnel、WebSocket）...")"
  detect_os

  case "$PKG_MGR" in
    apt)
      apt-get update -y || true
      # Debian 13 (trixie) & Ubuntu 26.04: dropbear + stunnel4 masih tersedia di repo main.
      # unzip ditambah untuk ekstraksi Xray yang andal (fallback python3-zip tetap ada).
      apt-get install -y openssh-server dropbear stunnel4 python3 curl qrencode iptables unzip || \
        apt-get install -y openssh-server stunnel4 python3 curl qrencode iptables unzip
      ;;
    dnf|yum)
      $PKG_MGR install -y epel-release || true
      $PKG_MGR install -y openssh-server stunnel python3 curl qrencode iptables
      ;;
    pacman)
      pacman -Sy --noconfirm openssh dropbear stunnel python3 curl qrencode iptables
      ;;
    *)
      die "$(T "Package manager $PKG_MGR is not supported for automatic SSH install." "Package manager $PKG_MGR belum didukung untuk instalasi SSH otomatis." "软件包管理器 $PKG_MGR 不支持自动安装 SSH。")"
      ;;
  esac

  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"
  touch "$SSH_ACCOUNTS_DB"
  chmod 600 "$SSH_ACCOUNTS_DB"

  log_success "$(T "SSH VPN packages installed." "Paket SSH VPN terinstal." "SSH VPN 软件包已安装。")"
}

ssh_harden_config() {
  log_step "$(T "Hardening the OpenSSH server config..." "Mengeraskan konfigurasi OpenSSH server..." "正在加固 OpenSSH 服务器配置...")"

  local sshd_conf="/etc/ssh/sshd_config"
  [[ -f "$sshd_conf" ]] || die "$(T "File $sshd_conf was not found after installing openssh-server." "File $sshd_conf tidak ditemukan setelah instalasi openssh-server." "安装 openssh-server 后未找到文件 $sshd_conf。")"

  cp "$sshd_conf" "$sshd_conf.bak.$(date +%Y%m%d%H%M%S)"

  # Terapkan pengaturan aman modern (idempotent: hapus duplikat dulu)
  for key in "PasswordAuthentication" "PermitRootLogin" "X11Forwarding" \
             "MaxAuthTries" "LoginGraceTime" "ClientAliveInterval" \
             "ClientAliveCountMax" "AllowTcpForwarding"; do
    sed -i "/^#*${key}/d" "$sshd_conf"
  done

  cat >> "$sshd_conf" <<'EOF'

# === Dikelola oleh ssh-vpn installer (aman & modern) ===
PasswordAuthentication yes
PermitRootLogin no
X11Forwarding no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 240
ClientAliveCountMax 2
AllowTcpForwarding yes
EOF

  sshd -t || die "$(T "sshd config is invalid after hardening. Check $sshd_conf." "Konfigurasi sshd tidak valid setelah hardening. Cek $sshd_conf." "加固后 sshd 配置无效。请检查 $sshd_conf。")"

  if systemctl list-unit-files | grep -q "^sshd\.service"; then
    systemctl enable sshd >/dev/null 2>&1 || true
    systemctl restart sshd
  else
    systemctl enable ssh >/dev/null 2>&1 || true
    systemctl restart ssh
  fi

  log_success "$(T "OpenSSH server hardened & restarted." "OpenSSH server dikeraskan & dijalankan ulang." "OpenSSH 服务器已加固并重启。")"
}

ssh_setup_dropbear() {
  local port="${1:-143}"
  log_step "$(T "Configuring Dropbear on port $port..." "Mengonfigurasi Dropbear di port $port..." "正在配置 Dropbear，端口 $port...")"

  if ! command -v dropbear &>/dev/null; then
    log_warn "$(T "Dropbear is not available on this system, skipping Dropbear setup." "Dropbear tidak tersedia di sistem ini, melewati setup Dropbear." "此系统没有 Dropbear，跳过 Dropbear 设置。")"
    return 0
  fi

  if [[ -f /etc/default/dropbear ]]; then
    sed -i 's/^NO_START=.*/NO_START=0/' /etc/default/dropbear
    if grep -q "^DROPBEAR_PORT=" /etc/default/dropbear; then
      sed -i "s/^DROPBEAR_PORT=.*/DROPBEAR_PORT=$port/" /etc/default/dropbear
    else
      echo "DROPBEAR_PORT=$port" >> /etc/default/dropbear
    fi
    if grep -q "^DROPBEAR_EXTRA_ARGS=" /etc/default/dropbear; then
      sed -i 's/^DROPBEAR_EXTRA_ARGS=.*/DROPBEAR_EXTRA_ARGS="-w -s"/' /etc/default/dropbear
    else
      echo 'DROPBEAR_EXTRA_ARGS="-w -s"' >> /etc/default/dropbear
    fi
    systemctl enable dropbear >/dev/null 2>&1 || true
    systemctl restart dropbear || true
  elif systemctl list-unit-files | grep -q "dropbear"; then
    mkdir -p /etc/systemd/system/dropbear.service.d
    cat > /etc/systemd/system/dropbear.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/sbin/dropbear -F -E -p $port -w -s
EOF
    systemctl daemon-reload
    systemctl enable dropbear >/dev/null 2>&1 || true
    systemctl restart dropbear || true
  fi

  open_firewall_port "$port" "tcp"
  log_success "$(T "Dropbear configured on port $port." "Dropbear dikonfigurasi di port $port." "Dropbear 已配置在端口 $port。")"
}

ssh_setup_stunnel() {
  local ssl_port="${1:-444}"
  local ssh_port="${2:-22}"
  log_step "$(T "Configuring Stunnel (SSH over TLS) $ssl_port -> 127.0.0.1:$ssh_port..." "Mengonfigurasi Stunnel (SSH over TLS) $ssl_port -> 127.0.0.1:$ssh_port..." "正在配置 Stunnel（SSH over TLS）$ssl_port -> 127.0.0.1:$ssh_port...")"

  if ! command -v stunnel4 &>/dev/null && ! command -v stunnel &>/dev/null; then
    log_warn "$(T "Stunnel is not available on this system, skipping Stunnel setup." "Stunnel tidak tersedia di sistem ini, melewati setup Stunnel." "此系统没有 Stunnel，跳过 Stunnel 设置。")"
    return 0
  fi

  local stunnel_bin="stunnel4"
  command -v stunnel4 &>/dev/null || stunnel_bin="stunnel"

  mkdir -p /etc/stunnel
  local cert_file="/etc/stunnel/stunnel.pem"

  if [[ ! -f "$cert_file" ]]; then
    openssl req -new -x509 -days 3650 -nodes \
      -subj "/C=ID/ST=Jakarta/L=Jakarta/O=VPN/CN=vpn-server" \
      -out "$cert_file" -keyout "$cert_file" 2>/dev/null
    chmod 600 "$cert_file"
  fi

  cat > "$STUNNEL_CONF" <<EOF
cert = $cert_file
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[dropbear-ssh]
accept = $ssl_port
connect = 127.0.0.1:$ssh_port
EOF
  chmod 600 "$STUNNEL_CONF"

  if [[ -f /etc/default/stunnel4 ]]; then
    sed -i 's/^ENABLED=.*/ENABLED=1/' /etc/default/stunnel4
  fi

  cat > /etc/systemd/system/stunnel4.service <<EOF
[Unit]
Description=Stunnel TLS Wrapper for SSH
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/$stunnel_bin $STUNNEL_CONF
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable stunnel4 >/dev/null 2>&1 || true
  systemctl restart stunnel4

  open_firewall_port "$ssl_port" "tcp"
  log_success "$(T "Stunnel active: port $ssl_port (TLS) -> SSH $ssh_port." "Stunnel aktif: port $ssl_port (TLS) -> SSH $ssh_port." "Stunnel 运行中：端口 $ssl_port（TLS）-> SSH $ssh_port。")"
}

# WebSocket bridge: forwards WS (port 80) to local SSH (port 22).
# Used by tunneling apps (HTTP Custom, etc.) with a standard WS payload.
ssh_setup_websocket() {
  local ws_port="${1:-80}"
  local ssh_port="${2:-22}"
  log_step "$(T "Installing the SSH WebSocket bridge (port $ws_port -> 127.0.0.1:$ssh_port)..." "Memasang SSH WebSocket bridge (port $ws_port -> 127.0.0.1:$ssh_port)..." "正在安装 SSH WebSocket 桥接（端口 $ws_port -> 127.0.0.1:$ssh_port）...")"

  local ws_script="/usr/local/bin/ssh-ws.py"
  cat > "$ws_script" <<EOF
#!/usr/bin/env python3
"""SSH over WebSocket bridge (dibuat otomatis oleh ssh-vpn installer)."""
import socket
import threading

LISTEN_PORT = int("$ws_port")
SSH_TARGET = ("127.0.0.1", int("$ssh_port"))

def relay(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        try:
            src.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        try:
            dst.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass

def handle(client):
    try:
        req = b""
        while b"\\r\\n\\r\\n" not in req:
            chunk = client.recv(4096)
            if not chunk:
                client.close()
                return
            req += chunk
            if len(req) > 65536:
                client.close()
                return
        ssh = socket.create_connection(SSH_TARGET, timeout=10)
        client.sendall(
            b"HTTP/1.1 101 Switching Protocols\\r\\n"
            b"Upgrade: websocket\\r\\n"
            b"Connection: Upgrade\\r\\n"
            b"Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\\r\\n\\r\\n"
        )
        t1 = threading.Thread(target=relay, args=(client, ssh), daemon=True)
        t2 = threading.Thread(target=relay, args=(ssh, client), daemon=True)
        t1.start()
        t2.start()
        t1.join()
        t2.join()
    except OSError:
        pass
    finally:
        try:
            client.close()
        except OSError:
            pass

def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", LISTEN_PORT))
    srv.listen(128)
    while True:
        client, _ = srv.accept()
        threading.Thread(target=handle, args=(client,), daemon=True).start()

if __name__ == "__main__":
    main()
EOF
  chmod 755 "$ws_script"

  cat > /etc/systemd/system/ssh-ws.service <<EOF
[Unit]
Description=SSH over WebSocket Bridge
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $ws_script
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable ssh-ws >/dev/null 2>&1 || true
  systemctl restart ssh-ws

  open_firewall_port "$ws_port" "tcp"
  log_success "$(T "SSH WebSocket bridge is active on port $ws_port." "SSH WebSocket bridge aktif di port $ws_port." "SSH WebSocket 桥接已在端口 $ws_port 运行。")"
}

ssh_setup_server() {
  local pub_ip="${1:-$(get_public_ip)}"
  local ssh_port="${2:-22}"
  local dropbear_port="${3:-143}"
  local ssl_port="${4:-444}"
  local ws_port="${5:-80}"

  install_ssh_packages
  ssh_harden_config
  ssh_setup_dropbear "$dropbear_port"
  ssh_setup_stunnel "$ssl_port" "$ssh_port"
  ssh_setup_websocket "$ws_port" "$ssh_port"

  open_firewall_port "$ssh_port" "tcp"

  cat > "$SSH_PARAMS" <<EOF
SSH_PUB_IP="$pub_ip"
SSH_PORT="$ssh_port"
DROPBEAR_PORT="$dropbear_port"
SSL_PORT="$ssl_port"
WS_PORT="$ws_port"
EOF
  chmod 600 "$SSH_PARAMS"

  log_success "$(T "SSH VPN active — SSH:$ssh_port Dropbear:$dropbear_port TLS:$ssl_port WS:$ws_port" "SSH VPN aktif — SSH:$ssh_port Dropbear:$dropbear_port TLS:$ssl_port WS:$ws_port" "SSH VPN 运行中 — SSH:$ssh_port Dropbear:$dropbear_port TLS:$ssl_port WS:$ws_port")"

  echo ""
  echo "==================== $(T "SSH ACCOUNT INFO" "INFORMASI AKUN SSH" "SSH 账户信息") ===================="
  echo " $(T "Host / IP        : $pub_ip" "Host / IP        : $pub_ip" "主机 / IP      ：$pub_ip")"
  echo " $(T "OpenSSH port     : $ssh_port (direct)" "Port OpenSSH     : $ssh_port (direct)" "OpenSSH 端口    ：$ssh_port（直连）")"
  echo " $(T "Dropbear port    : $dropbear_port" "Port Dropbear    : $dropbear_port" "Dropbear 端口   ：$dropbear_port")"
  echo " $(T "SSH over TLS port: $ssl_port (Stunnel)" "Port SSH over TLS: $ssl_port (Stunnel)" "SSH over TLS 端口：$ssl_port（Stunnel）")"
  echo " $(T "SSH over WS port : $ws_port (WebSocket payload)" "Port SSH over WS : $ws_port (payload WebSocket)" "SSH over WS 端口 ：$ws_port（WebSocket 负载）")"
  echo " $(T "Create new account: sudo ./add-ssh-user.sh <username>" "Buat akun baru   : sudo ./add-ssh-user.sh <username>" "创建新账户    ：sudo ./add-ssh-user.sh <用户名>")"
  echo "============================================================"
}

# ------------------------------------------------------- manajemen akun
ssh_user_exists() {
  local user="$1"
  id "$user" &>/dev/null
}

ssh_create_user() {
  local user="$1"
  local password="${2:-}"
  local days="${3:-30}"

  validate_client_name "$user"

  if ssh_user_exists "$user"; then
    die "$(T "System user '$user' already exists. Pick another name." "User sistem '$user' sudah ada. Pilih nama lain." "系统用户 '$user' 已存在。请选择其他名称。")"
  fi

  if [[ -z "$password" ]]; then
    password="$(gen_password 12)"
    echo "$password" > "$SSH_DIR/.last-pass-$user"
    chmod 600 "$SSH_DIR/.last-pass-$user"
  fi

  local expire_date
  expire_date="$(date -d "+${days} days" +%Y-%m-%d 2>/dev/null || date -v+${days}d +%Y-%m-%d 2>/dev/null || echo "")"
  if [[ -z "$expire_date" ]]; then
    die "$(T "Failed to compute the expiry date." "Gagal menghitung tanggal kedaluwarsa." "计算到期日期失败。")"
  fi

  # Create the user without full interactive shell access (nologin) but allow port-forwarding
  useradd -e "$expire_date" -s /usr/sbin/nologin -M "$user" || \
    useradd -e "$expire_date" -s /bin/false -M "$user"
  echo "${user}:${password}" | chpasswd

  # Record in the account database (for list & bulk removal)
  local created
  created="$(date +%Y-%m-%d)"
  if grep -q "^${user}:" "$SSH_ACCOUNTS_DB" 2>/dev/null; then
    sed -i "/^${user}:/d" "$SSH_ACCOUNTS_DB"
  fi
  echo "${user}:${created}:${expire_date}" >> "$SSH_ACCOUNTS_DB"

  SSH_LAST_USER="$user"
  SSH_LAST_PASS="$password"
  SSH_LAST_EXPIRE="$expire_date"
  export SSH_LAST_USER SSH_LAST_PASS SSH_LAST_EXPIRE

  log_success "$(T "SSH account '$user' created (valid until $expire_date)." "Akun SSH '$user' dibuat (berlaku s/d $expire_date)." "SSH 账户 '$user' 已创建（有效期至 $expire_date）。")"
}

ssh_remove_user() {
  local user="$1"
  validate_client_name "$user"

  if ! ssh_user_exists "$user"; then
    die "$(T "User '$user' was not found on the system." "User '$user' tidak ditemukan di sistem." "系统中未找到用户 '$user'。")"
  fi

  # Kill the user's active sessions
  pkill -u "$user" 2>/dev/null || true
  userdel -r "$user" 2>/dev/null || userdel "$user"
  sed -i "/^${user}:/d" "$SSH_ACCOUNTS_DB" 2>/dev/null || true
  rm -f "$SSH_DIR/.last-pass-$user"

  log_success "$(T "SSH account '$user' removed." "Akun SSH '$user' berhasil dihapus." "SSH 账户 '$user' 已删除。")"
}

ssh_list_users() {
  echo "======================================================================"
  echo -e "${_C_BOLD}$(T "SSH VPN ACCOUNT LIST" "DAFTAR AKUN SSH VPN" "SSH VPN 账户列表")${_C_RESET}"
  echo "======================================================================"
  printf "%-18s %-14s %-14s %-12s\n" "USERNAME" "$(T "CREATED" "DIBUAT" "创建时间")" "$(T "EXPIRES" "KEDALUWARSA" "到期时间")" "STATUS"
  echo "----------------------------------------------------------------------"

  local count=0 expired=0
  local today
  today="$(date +%Y-%m-%d)"

  if [[ -s "$SSH_ACCOUNTS_DB" ]]; then
    while IFS=: read -r user created expire _rest; do
      [[ -z "$user" ]] && continue
      local status="$(T "ACTIVE" "AKTIF" "运行中")"
      if [[ "$expire" < "$today" ]]; then
        status="$(T "EXPIRED" "KEDALUWARSA" "已过期")"
        ((expired++)) || true
      elif ! id "$user" &>/dev/null; then
        status="$(T "MISSING" "HILANG" "缺失")"
      fi
      printf "%-18s %-14s %-14s %-12s\n" "$user" "$created" "$expire" "$status"
      ((count++)) || true
    done < "$SSH_ACCOUNTS_DB"
  fi

  if [[ "$count" -eq 0 ]]; then
    echo " ($(T "No SSH accounts registered yet" "Belum ada akun SSH yang terdaftar" "暂无已注册的 SSH 账户"))"
  fi
  echo "----------------------------------------------------------------------"
  echo "$(T "Total accounts: $count (expired: $expired)" "Total akun: $count (kedaluwarsa: $expired)" "账户总数：$count（已过期：$expired）")"
  echo "======================================================================"
}
