#!/bin/bash
#
# lib/wstunnel.sh — WireGuard over WebSocket tunnel (wstunnel, erebe/wstunnel)
# Branding: wrwb Store
#
# Schema (user request v5):
#   Client WG (127.0.0.1:51820) -> wstunnel client -> WS/WSS (80/8080/443/8443)
#   -> Nginx gateway (/wg-ws) -> wstunnel server (127.0.0.1:10081)
#   -> local WireGuard (127.0.0.1:51820, pure UDP foundation, untouched)
#
# Server binary: erebe/wstunnel (static binary, ~5MB, no deps).
# Default: plain ws:// on 127.0.0.1:10081, restrict-to 127.0.0.1:<WG_PORT>,
#          path prefix "wg-ws" (must match Nginx location /wg-ws).
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This file is a library. Do not run it directly." >&2
  exit 1
fi

WSTUNNEL_BIN="/usr/local/bin/wstunnel"
WSTUNNEL_SERVICE="wstunnel"
WSTUNNEL_DIR="/etc/wstunnel"
WSTUNNEL_PARAMS="$WSTUNNEL_DIR/params"

# Stable wstunnel version (check https://github.com/erebe/wstunnel/releases)
WSTUNNEL_VERSION_DEFAULT="v11.0.0"

# Internal listen (localhost only; public via Nginx gateway 80/8080/443/8443)
WSTUNNEL_PORT="${WSTUNNEL_PORT:-10081}"
WSTUNNEL_PATH="${WSTUNNEL_PATH:-wg-ws}"

wstunnel_detect_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armhf|armv7*) echo "armv7" ;;
    armv6l|armv6*) echo "armv6" ;;
    i386|i686) echo "386" ;;
    *) die "$(T "CPU arch '$arch' not supported for wstunnel auto-install." "Arsitektur CPU '$arch' tidak didukung untuk wstunnel otomatis." "CPU 架构 '$arch' 不支持 wstunnel 自动安装。")" ;;
  esac
}

wstunnel_install_binary() {
  if [[ -x "$WSTUNNEL_BIN" ]]; then
    log_info "$(T "wstunnel already installed at $WSTUNNEL_BIN" "wstunnel sudah terinstal di $WSTUNNEL_BIN" "wstunnel 已安装于 $WSTUNNEL_BIN")"
    return 0
  fi
  local ver="${WSTUNNEL_VERSION:-$WSTUNNEL_VERSION_DEFAULT}"
  local arch goos
  arch="$(wstunnel_detect_arch)"
  goos="linux"
  # erebe/wstunnel asset names (v11.0.0): wstunnel_11.0.0_linux_amd64.tar.gz
  # (inside: binary "wstunnel"). Arch map: amd64/arm64/armv7/armv6/386.
  # NOTE: arm arch names differ from Xray (arm64-v8a/arm32-v7a) — don't reuse that helper.
  # NOTE: `find ... | head -n1` under `set -o pipefail` returns head's status;
  # with `|| true` on extraction above this block stays safe, and `found` empty
  # simply falls through to the warn+skip below (no broken binary installed).
  local tmp_dir tmp_tar url
  tmp_dir="$(mktemp -d)"
  track_temp "$tmp_dir"
  mkdir -p "$(dirname "$WSTUNNEL_BIN")"

  log_step "$(T "Downloading wstunnel $ver ($arch) from GitHub..." "Mengunduh wstunnel $ver ($arch) dari GitHub..." "正在从 GitHub 下载 wstunnel $ver ($arch)...")"
  for url in \
    "https://github.com/erebe/wstunnel/releases/download/${ver}/wstunnel_${ver#v}_${goos}_${arch}.tar.gz" \
  ; do
    tmp_tar="$tmp_dir/wstunnel-dl.tgz"
    if curl -fsSL --retry 2 --connect-timeout 20 "$url" -o "$tmp_tar" 2>/dev/null; then
      # Try tar.gz first, else treat as raw binary.
      # NOTE: `head -c4 ... | grep -q` under pipefail yields grep's code — used
      # in an `elif` condition so `set -e` never fires here; non-ELF falls to warn.
      if tar -tzf "$tmp_tar" >/dev/null 2>&1; then
        tar -xzf "$tmp_tar" -C "$tmp_dir" 2>/dev/null || true
        local found
        found="$(find "$tmp_dir" -type f -name "wstunnel*" | head -n1)"
        if [[ -n "$found" ]]; then
          cp -f "$found" "$WSTUNNEL_BIN"
          chmod 755 "$WSTUNNEL_BIN"
          rm -rf "$tmp_dir"
          log_success "$(T "wstunnel $ver installed." "wstunnel $ver terinstal." "wstunnel $ver 已安装。")"
          return 0
        fi
      elif head -c4 "$tmp_tar" 2>/dev/null | grep -q "ELF"; then
        cp -f "$tmp_tar" "$WSTUNNEL_BIN"
        chmod 755 "$WSTUNNEL_BIN"
        rm -rf "$tmp_dir"
        log_success "$(T "wstunnel $ver installed." "wstunnel $ver terinstal." "wstunnel $ver 已安装。")"
        return 0
      fi
    fi
  done
  rm -rf "$tmp_dir"
  log_warn "$(T "Could not download wstunnel $ver — WG-WS tunnel skipped (pure WireGuard still works)." "Gagal mengunduh wstunnel $ver — tunnel WG-WS dilewati (WireGuard murni tetap jalan)." "下载 wstunnel $ver 失败 — 已跳过 WG-WS 隧道（原生 WireGuard 仍可用）。")"
  return 1
}

# Setup wstunnel server (restrict-to local WG port, plain WS on localhost)
# Args: <wg_port> (default 51820)
wstunnel_setup_server() {
  local wg_port="${1:-51820}"
  local pub_ip="${2:-$(get_public_ip)}"

  check_port_free "$WSTUNNEL_PORT" "tcp" "WG-WS" --soft || true

  wstunnel_install_binary || return 0
  [[ -x "$WSTUNNEL_BIN" ]] || return 0

  mkdir -p "$WSTUNNEL_DIR"
  chmod 700 "$WSTUNNEL_DIR"

  log_step "$(T "Creating wstunnel server (127.0.0.1:$WSTUNNEL_PORT -> 127.0.0.1:$wg_port, path /$WSTUNNEL_PATH)..." "Membuat wstunnel server (127.0.0.1:$WSTUNNEL_PORT -> 127.0.0.1:$wg_port, path /$WSTUNNEL_PATH)..." "正在创建 wstunnel 服务端 (127.0.0.1:$WSTUNNEL_PORT -> 127.0.0.1:$wg_port, 路径 /$WSTUNNEL_PATH)...")"

  cat > /etc/systemd/system/wstunnel.service <<EOF
[Unit]
Description=WireGuard over WebSocket tunnel (wstunnel v5, auto-start on boot)
After=network.target wg-quick@wg0.service
Wants=wg-quick@wg0.service

[Service]
Type=simple
User=root
# v11 syntax: server ws://LISTEN [--restrict-to host:port]... (-r guards the WS upgrade path).
# Path prefixes WITHOUT leading slash (use both "wg-ws" + "wireguard-ws" so both Nginx aliases pass).
ExecStart=$WSTUNNEL_BIN server --restrict-to 127.0.0.1:$wg_port -r $WSTUNNEL_PATH -r wireguard-ws ws://127.0.0.1:$WSTUNNEL_PORT
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

  # v4.9 pattern: enable + restart via helper
  svc_restart "$WSTUNNEL_SERVICE"

  cat > "$WSTUNNEL_PARAMS" <<EOF
WSTUNNEL_PUB_IP="$pub_ip"
WSTUNNEL_PORT="$WSTUNNEL_PORT"
WSTUNNEL_PATH="$WSTUNNEL_PATH"
WSTUNNEL_WG_PORT="$wg_port"
EOF
  chmod 600 "$WSTUNNEL_PARAMS"

  # NOTE: 10081 is localhost-only (Nginx proxies to it) — do NOT open it
  # publicly. open_firewall_port would add useless ACCEPT rules on every
  # filtering VPS and mislead audits (same reason XHTTP 10009-10011 stay
  # closed; see lib/xray.sh). Public path is 80/8080/443/8443 via edge.sh.

  log_success "$(T "wstunnel server active (WG-WS via gateway 80/8080/443/8443 /$WSTUNNEL_PATH)." "wstunnel server aktif (WG-WS via gateway 80/8080/443/8443 /$WSTUNNEL_PATH)." "wstunnel 服务端运行中 (经网关 80/8080/443/8443 /$WSTUNNEL_PATH 的 WG-WS)。")"

  # Save client instructions (same text printed + saved)
  # Client syntax (v10/v11): -L 'udp://<listen>:<remote>?timeout_sec=0'
  # + --http-upgrade-path-prefix WITHOUT leading slash (matches server -r).
  show_and_save "WireGuard-WS tunnel (wstunnel v5)" <<EOF
WireGuard over WebSocket (wstunnel v5)
Server IP    : $pub_ip
WG pure      : $pub_ip:$wg_port/udp (foundation, fastest — keep this!)
WG-WS paths  : /$WSTUNNEL_PATH and /wireguard-ws (Nginx gateway, prefix WITHOUT leading slash)
Ports        : ws://$pub_ip:80/$WSTUNNEL_PATH | ws://$pub_ip:8080/$WSTUNNEL_PATH | wss://$pub_ip:443/$WSTUNNEL_PATH | wss://$pub_ip:8443/$WSTUNNEL_PATH
Backend      : 127.0.0.1:$WSTUNNEL_PORT -> 127.0.0.1:$wg_port (restrict-to, path prefixes $WSTUNNEL_PATH + wireguard-ws)
Client example (Linux):
  wstunnel client -L 'udp://127.0.0.1:$wg_port:127.0.0.1:$wg_port?timeout_sec=0' --http-upgrade-path-prefix $WSTUNNEL_PATH ws://$pub_ip:80 &
  # then set WireGuard [Peer] Endpoint = 127.0.0.1:$wg_port (instead of $pub_ip:$wg_port)
Client example (TLS, port 443/8443):
  wstunnel client -L 'udp://127.0.0.1:$wg_port:127.0.0.1:$wg_port?timeout_sec=0' --http-upgrade-path-prefix $WSTUNNEL_PATH wss://$pub_ip:443 &
Re-show: cat $VPN_SUMMARY_FILE
EOF
}

wstunnel_remove() {
  log_info "$(T "Removing wstunnel..." "Menghapus wstunnel..." "正在删除 wstunnel...")"
  systemctl stop "$WSTUNNEL_SERVICE" 2>/dev/null || true
  systemctl disable "$WSTUNNEL_SERVICE" 2>/dev/null || true
  rm -f /etc/systemd/system/wstunnel.service
  systemctl daemon-reload 2>/dev/null || true
  if [[ -f "$WSTUNNEL_PARAMS" ]]; then
    # shellcheck disable=SC1090
    source "$WSTUNNEL_PARAMS" 2>/dev/null || true
    # Localhost-only port: nothing was ever opened publicly (see setup note),
    # but close anyway to sweep STALE rules from v5-beta installs that did open it.
    close_firewall_port "${WSTUNNEL_PORT:-10081}" "tcp" || true
  fi
  rm -rf "$WSTUNNEL_DIR" "$WSTUNNEL_BIN"
  log_success "$(T "wstunnel removed." "wstunnel dihapus." "wstunnel 已删除。")"
}
