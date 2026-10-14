#!/bin/bash
#
# lib/edge.sh — Nginx WS gateway for v5 (80/8080 plain + 8443 TLS + 443 fallback)
# Branding: wrwb Store
#
# Architecture v5:
#   Port 80  (non-TLS) + 8080 (alt non-TLS): Nginx plain gateway
#   Port 8443 (TLS alt)                    : Nginx TLS gateway (acme.sh or self-signed)
#   Port 443 (REALITY foundation)          : Xray VLESS TCP REALITY with fallback -> 127.0.0.1:8443
#                                            so WS-TLS via 443 works through fallback (standard TLS).
#   Backends (plain HTTP/WS, Nginx proxies with Upgrade headers):
#     /vmess, /vless, /trojan             -> 127.0.0.1:10001/10002/10003 (Xray WS)
#     /vmess-xhttp, /vless-xhttp, /trojan-xhttp -> 127.0.0.1:10009/10010/10011 (Xray XHTTP)
#     /ssh-ws, /ssh                        -> 127.0.0.1:10080 (SSH-WS bridge)
#     /wg-ws, /wireguard-ws                -> 127.0.0.1:10081 (wstunnel server -> WG)
#   NOTE: Xray WS/XHTTP backends speak REAL WebSocket/XHTTP (RFC6455).
#         SSH-WS bridge is a raw-payload bridge (HTTP Custom style); Nginx only
#         tunnels bytes after 101 so both raw and real-WS clients pass through.
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This file is a library. Do not run it directly." >&2
  exit 1
fi

EDGE_NGINX_CONF_DEFAULT="/etc/nginx/conf.d/vpn-ws-gateway.conf"
EDGE_NGINX_CONF_ALPINE="/etc/nginx/http.d/vpn-ws-gateway.conf"
# Resolved lazily (install.sh sources libs on dev machines where /etc/nginx
# may not exist yet — never freeze the path at source time).
EDGE_NGINX_CONF="${EDGE_NGINX_CONF:-$EDGE_NGINX_CONF_DEFAULT}"
edge_nginx_conf() {
  if [[ -n "${EDGE_NGINX_CONF_OVERRIDE:-}" ]]; then
    echo "$EDGE_NGINX_CONF_OVERRIDE"
  elif [[ -d /etc/nginx/http.d && ! -d /etc/nginx/conf.d ]]; then
    echo "$EDGE_NGINX_CONF_ALPINE"
  else
    echo "$EDGE_NGINX_CONF_DEFAULT"
  fi
}
EDGE_SELF_DIR="/etc/nginx/vpn-selfsigned"
EDGE_SELF_CRT="$EDGE_SELF_DIR/fullchain.pem"
EDGE_SELF_KEY="$EDGE_SELF_DIR/key.pem"

# Public gateway ports (v5)
EDGE_PORT_PLAIN="${EDGE_PORT_PLAIN:-80}"
EDGE_PORT_ALT="${EDGE_PORT_ALT:-8080}"
EDGE_PORT_TLS="${EDGE_PORT_TLS:-8443}"

# Internal backends (must match lib/xray.sh v5 + lib/ssh.sh v5 + lib/wstunnel.sh)
EDGE_BE_VMESS_WS="${EDGE_BE_VMESS_WS:-10001}"
EDGE_BE_VLESS_WS="${EDGE_BE_VLESS_WS:-10002}"
EDGE_BE_TROJAN_WS="${EDGE_BE_TROJAN_WS:-10003}"
EDGE_BE_VMESS_XHTTP="${EDGE_BE_VMESS_XHTTP:-10009}"
EDGE_BE_VLESS_XHTTP="${EDGE_BE_VLESS_XHTTP:-10010}"
EDGE_BE_TROJAN_XHTTP="${EDGE_BE_TROJAN_XHTTP:-10011}"
EDGE_BE_SSH_WS="${EDGE_BE_SSH_WS:-10080}"
EDGE_BE_WG_WS="${EDGE_BE_WG_WS:-10081}"

edge_install_nginx() {
  log_step "$(T "Installing Nginx edge gateway (80/8080/8443)..." "Menginstal Nginx edge gateway (80/8080/8443)..." "正在安装 Nginx 边缘网关 (80/8080/8443)...")"
  detect_os
  case "$PKG_MGR" in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y || true
      apt-get install -y nginx openssl || die "$(T "Failed to install nginx." "Gagal memasang nginx." "安装 nginx 失败。")"
      ;;
    dnf|yum)
      $PKG_MGR install -y epel-release || true
      $PKG_MGR install -y nginx openssl || die "$(T "Failed to install nginx." "Gagal memasang nginx." "安装 nginx 失败。")"
      ;;
    pacman)
      pacman -Sy --noconfirm nginx openssl || die "$(T "Failed to install nginx." "Gagal memasang nginx." "安装 nginx 失败。")"
      ;;
    apk)
      apk add --no-cache nginx openssl || die "$(T "Failed to install nginx." "Gagal memasang nginx." "安装 nginx 失败。")"
      ;;
    zypper)
      zypper install -y nginx openssl || die "$(T "Failed to install nginx." "Gagal memasang nginx." "安装 nginx 失败。")"
      ;;
    *)
      die "$(T "Package manager $PKG_MGR is not supported for automatic Nginx install." "Package manager $PKG_MGR belum didukung untuk instalasi Nginx otomatis." "软件包管理器 $PKG_MGR 不支持自动安装 Nginx。")"
      ;;
  esac
  log_success "$(T "Nginx installed." "Nginx terinstal." "Nginx 已安装。")"
}

# Pick TLS cert for 8443: acme.sh cert when present, else self-signed (generated).
# Prints "<crt> <key>" paths.
edge_pick_tls_cert() {
  local crt="" key=""
  # shellcheck disable=SC1090
  if [[ -f /etc/vpn-ssl/params ]]; then
    source /etc/vpn-ssl/params 2>/dev/null || true
    if [[ -n "${SSL_DOMAIN:-}" && -f "/etc/vpn-ssl/${SSL_DOMAIN}/fullchain.pem" && -f "/etc/vpn-ssl/${SSL_DOMAIN}/key.pem" ]]; then
      crt="/etc/vpn-ssl/${SSL_DOMAIN}/fullchain.pem"
      key="/etc/vpn-ssl/${SSL_DOMAIN}/key.pem"
      echo "$crt $key"
      return 0
    fi
  fi
  # Self-signed fallback (CN = server IP, 10 years)
  mkdir -p "$EDGE_SELF_DIR"
  if [[ ! -f "$EDGE_SELF_CRT" || ! -f "$EDGE_SELF_KEY" ]]; then
    local cn
    cn="$(get_public_ip 2>/dev/null || echo "vpn.local")"
    openssl req -new -x509 -days 3650 -nodes \
      -subj "/C=ID/ST=Jakarta/L=Jakarta/O=wrwb-Store/CN=${cn}" \
      -out "$EDGE_SELF_CRT" -keyout "$EDGE_SELF_KEY" 2>/dev/null || true
    chmod 600 "$EDGE_SELF_KEY" 2>/dev/null || true
    chmod 644 "$EDGE_SELF_CRT" 2>/dev/null || true
  fi
  echo "$EDGE_SELF_CRT $EDGE_SELF_KEY"
}

edge_write_config() {
  local crt key conf
  read -r crt key <<<"$(edge_pick_tls_cert)"
  conf="$(edge_nginx_conf)"
  # Keep the legacy var in sync for callers/status that still read it.
  EDGE_NGINX_CONF="$conf"
  log_step "$(T "Writing Nginx WS gateway config (80/$EDGE_PORT_ALT plain + $EDGE_PORT_TLS TLS)..." "Menulis konfigurasi Nginx WS gateway (80/$EDGE_PORT_ALT plain + $EDGE_PORT_TLS TLS)..." "正在写入 Nginx WS 网关配置 (80/$EDGE_PORT_ALT 明文 + $EDGE_PORT_TLS TLS)...")"

  # v5: port-conflict check (soft, gateway owns these ports)
  check_port_free "$EDGE_PORT_PLAIN" "tcp" "Nginx-plain" --soft || true
  check_port_free "$EDGE_PORT_ALT" "tcp" "Nginx-alt" --soft || true
  check_port_free "$EDGE_PORT_TLS" "tcp" "Nginx-TLS" --soft || true

  mkdir -p "$(dirname "$conf")"

  # v5: disable distro default site on :80 (Debian/Ubuntu default + RHEL default.conf
  # also listen on 80 and would steal SNI-less traffic / cause duplicate default_server).
  for _def in /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf /etc/nginx/http.d/default.conf; do
    if [[ -f "$_def" ]]; then
      mv -f "$_def" "${_def}.disabled-by-vpn-gateway" 2>/dev/null || true
      log_info "$(T "Disabled distro default Nginx site: $_def" "Menonaktifkan site default Nginx distro: $_def" "已禁用发行版默认 Nginx 站点：$_def")"
    fi
  done
  unset _def

  cat > "$conf" <<EOF
# Auto-generated by vpn installer v5 (wrwb Store) — Nginx WS gateway.
# Plain: 80 + 8080 | TLS: 8443 | 443 REALITY falls back to 8443 (see lib/xray.sh).
# Backends: Xray WS (10001-10003), Xray XHTTP (10009-10011), SSH-WS (10080), WG-WS (10081).

# NOTE: unique map var (vpn_ws_upgrade) — other confs commonly define
# $connection_upgrade too; duplicate map names would fail "nginx -t".
map \$http_upgrade \$vpn_ws_upgrade {
  default upgrade;
  ''      close;
}

# ---- Plain gateway: port 80 (non-TLS, all protocols) ----
server {
  listen $EDGE_PORT_PLAIN;
  server_name _;

  # Xray WebSocket (REAL WS, paths must match Xray wsSettings)
  location = /vmess  { proxy_pass http://127.0.0.1:$EDGE_BE_VMESS_WS;  proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }
  location = /vless  { proxy_pass http://127.0.0.1:$EDGE_BE_VLESS_WS;  proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }
  location = /trojan { proxy_pass http://127.0.0.1:$EDGE_BE_TROJAN_WS; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }

  # Xray XHTTP (newest transport, most HTTP-like)
  location = /vmess-xhttp  { proxy_pass http://127.0.0.1:$EDGE_BE_VMESS_XHTTP;  proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }
  location = /vless-xhttp  { proxy_pass http://127.0.0.1:$EDGE_BE_VLESS_XHTTP;  proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }
  location = /trojan-xhttp { proxy_pass http://127.0.0.1:$EDGE_BE_TROJAN_XHTTP; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }

  # SSH over WebSocket (raw-payload bridge, HTTP Custom style)
  location = /ssh-ws { proxy_pass http://127.0.0.1:$EDGE_BE_SSH_WS; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }
  location = /ssh    { proxy_pass http://127.0.0.1:$EDGE_BE_SSH_WS; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }

  # WireGuard over WebSocket (wstunnel server)
  location = /wg-ws        { proxy_pass http://127.0.0.1:$EDGE_BE_WG_WS; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }
  location = /wireguard-ws { proxy_pass http://127.0.0.1:$EDGE_BE_WG_WS; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }

  location / { return 404 'vpn-ws-gateway v5 (use /vmess /vless /trojan /vmess-xhttp /vless-xhttp /trojan-xhttp /ssh-ws /wg-ws)'; }
}

# ---- Alt plain gateway: port 8080 (same routing; "/" kept for old SSH-WS clients) ----
server {
  listen $EDGE_PORT_ALT;
  server_name _;

  location = /vmess  { proxy_pass http://127.0.0.1:$EDGE_BE_VMESS_WS;  proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }
  location = /vless  { proxy_pass http://127.0.0.1:$EDGE_BE_VLESS_WS;  proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }
  location = /trojan { proxy_pass http://127.0.0.1:$EDGE_BE_TROJAN_WS; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }

  location = /vmess-xhttp  { proxy_pass http://127.0.0.1:$EDGE_BE_VMESS_XHTTP;  proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }
  location = /vless-xhttp  { proxy_pass http://127.0.0.1:$EDGE_BE_VLESS_XHTTP;  proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }
  location = /trojan-xhttp { proxy_pass http://127.0.0.1:$EDGE_BE_TROJAN_XHTTP; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }

  location = /ssh-ws { proxy_pass http://127.0.0.1:$EDGE_BE_SSH_WS; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }
  location = /ssh    { proxy_pass http://127.0.0.1:$EDGE_BE_SSH_WS; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }
  # Backward compat: old clients used ws://IP:8080/ (root) for SSH-WS
  location = /       { proxy_pass http://127.0.0.1:$EDGE_BE_SSH_WS; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }

  location = /wg-ws        { proxy_pass http://127.0.0.1:$EDGE_BE_WG_WS; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }
  location = /wireguard-ws { proxy_pass http://127.0.0.1:$EDGE_BE_WG_WS; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_read_timeout 86400; }
}

# ---- TLS gateway: port 8443 (all protocols over TLS; 443 REALITY falls back here) ----
server {
  listen $EDGE_PORT_TLS ssl;
  server_name _;

  ssl_certificate     $crt;
  ssl_certificate_key $key;
  ssl_protocols       TLSv1.2 TLSv1.3;
  ssl_prefer_server_ciphers on;

  location = /vmess  { proxy_pass http://127.0.0.1:$EDGE_BE_VMESS_WS;  proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_set_header X-Forwarded-Proto https; proxy_read_timeout 86400; }
  location = /vless  { proxy_pass http://127.0.0.1:$EDGE_BE_VLESS_WS;  proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_set_header X-Forwarded-Proto https; proxy_read_timeout 86400; }
  location = /trojan { proxy_pass http://127.0.0.1:$EDGE_BE_TROJAN_WS; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_set_header X-Forwarded-Proto https; proxy_read_timeout 86400; }

  location = /vmess-xhttp  { proxy_pass http://127.0.0.1:$EDGE_BE_VMESS_XHTTP;  proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_set_header X-Forwarded-Proto https; proxy_read_timeout 86400; }
  location = /vless-xhttp  { proxy_pass http://127.0.0.1:$EDGE_BE_VLESS_XHTTP;  proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_set_header X-Forwarded-Proto https; proxy_read_timeout 86400; }
  location = /trojan-xhttp { proxy_pass http://127.0.0.1:$EDGE_BE_TROJAN_XHTTP; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_set_header X-Forwarded-Proto https; proxy_read_timeout 86400; }

  location = /ssh-ws { proxy_pass http://127.0.0.1:$EDGE_BE_SSH_WS; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_set_header X-Forwarded-Proto https; proxy_read_timeout 86400; }
  location = /ssh    { proxy_pass http://127.0.0.1:$EDGE_BE_SSH_WS; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_set_header X-Forwarded-Proto https; proxy_read_timeout 86400; }

  location = /wg-ws        { proxy_pass http://127.0.0.1:$EDGE_BE_WG_WS; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_set_header X-Forwarded-Proto https; proxy_read_timeout 86400; }
  location = /wireguard-ws { proxy_pass http://127.0.0.1:$EDGE_BE_WG_WS; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$vpn_ws_upgrade; proxy_set_header Host \$host; proxy_set_header X-Forwarded-Proto https; proxy_read_timeout 86400; }

  location / { return 404 'vpn-ws-gateway v5 TLS (use /vmess /vless /trojan /ssh-ws /wg-ws)'; }
}
EOF

  # v5: validate BEFORE restart (never restart on broken config).
  # NOTE: no `| tail` here — under `set -euo pipefail` a masked pipeline would
  # abort install.sh on a BROKEN nginx config. Keep the raw exit code.
  nginx -t >/dev/null 2>&1 || die "$(T "Nginx config test FAILED — aborting before restart." "Tes konfigurasi Nginx GAGAL — dibatalkan sebelum restart." "Nginx 配置测试失败 — 已在重启前中止。")"
  nginx -t 2>&1 | tail -n3 || true

  svc_restart "nginx"
  open_firewall_ports "WS-Gateway" "tcp" "$EDGE_PORT_PLAIN" "$EDGE_PORT_ALT" "$EDGE_PORT_TLS"
  log_success "$(T "Nginx WS gateway active (80/$EDGE_PORT_ALT plain + $EDGE_PORT_TLS TLS)." "Nginx WS gateway aktif (80/$EDGE_PORT_ALT plain + $EDGE_PORT_TLS TLS)." "Nginx WS 网关运行中 (80/$EDGE_PORT_ALT 明文 + $EDGE_PORT_TLS TLS)。")"
}

edge_setup_server() {
  local pub_ip="${1:-$(get_public_ip)}"
  edge_install_nginx
  edge_write_config
  # Save params for status/uninstall
  mkdir -p /etc/vpn-script 2>/dev/null || true
  cat > /etc/vpn-script/edge-params <<EOF
EDGE_PUB_IP="$pub_ip"
EDGE_PORT_PLAIN="$EDGE_PORT_PLAIN"
EDGE_PORT_ALT="$EDGE_PORT_ALT"
EDGE_PORT_TLS="$EDGE_PORT_TLS"
EOF
  chmod 600 /etc/vpn-script/edge-params 2>/dev/null || true
  summary_block "WS Gateway (v5)" <<EOF
WS Gateway (Nginx edge v5)
Plain      : http://$pub_ip:$EDGE_PORT_PLAIN/<path> and http://$pub_ip:$EDGE_PORT_ALT/<path>
TLS        : https://$pub_ip:$EDGE_PORT_TLS/<path> (443 via REALITY fallback when domain SNI)
Paths      : /vmess /vless /trojan (WS) | /vmess-xhttp /vless-xhttp /trojan-xhttp (XHTTP) | /ssh-ws (SSH) | /wg-ws (WireGuard)
Re-show    : cat /etc/vpn-script/client-config.txt
EOF
}

# Re-apply gateway cert after acme.sh issuance/renew (called by lib/ssl.sh hook, best-effort).
# Safe under `set -e`: never dies (callers use `|| true` anyway); missing nginx is skipped.
edge_refresh_tls() {
  local conf
  conf="$(edge_nginx_conf)"
  if [[ ! -f "$conf" ]]; then
    return 0
  fi
  if ! command -v nginx &>/dev/null; then
    return 0
  fi
  if edge_write_config; then
    return 0
  fi
  log_warn "$(T "Gateway TLS refresh failed — kept previous Nginx config." "Refresh TLS gateway gagal — konfigurasi Nginx lama dipertahankan." "网关 TLS 刷新失败 — 已保留旧 Nginx 配置。")"
  return 0
}

edge_remove() {
  log_info "$(T "Removing Nginx WS gateway..." "Menghapus Nginx WS gateway..." "正在删除 Nginx WS 网关...")"
  systemctl stop nginx 2>/dev/null || true
  rm -f "$EDGE_NGINX_CONF_DEFAULT" "$EDGE_NGINX_CONF_ALPINE" "${EDGE_NGINX_CONF:-}"
  # Restore distro default site if we disabled it (best-effort)
  for _def in /etc/nginx/sites-enabled/default.disabled-by-vpn-gateway /etc/nginx/conf.d/default.conf.disabled-by-vpn-gateway /etc/nginx/http.d/default.conf.disabled-by-vpn-gateway; do
    if [[ -f "$_def" ]]; then
      mv -f "$_def" "${_def%.disabled-by-vpn-gateway}" 2>/dev/null || true
    fi
  done
  unset _def
  # Keep nginx package (may be used by user); only remove our conf + self-signed dir
  rm -rf "$EDGE_SELF_DIR"
  rm -f /etc/vpn-script/edge-params
  if command -v nginx &>/dev/null; then
    nginx -t 2>/dev/null || true
    systemctl restart nginx 2>/dev/null || true
  fi
  close_firewall_ports "tcp" "${EDGE_PORT_ALT:-8080}" "${EDGE_PORT_TLS:-8443}"
  # NOTE: port 80 close is handled by Xray/SSL cleanup when needed; keep 80 open if other services use it.
  log_success "$(T "Nginx WS gateway removed." "Nginx WS gateway dihapus." "Nginx WS 网关已删除。")"
}
