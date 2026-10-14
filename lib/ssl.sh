#!/bin/bash
#
# lib/ssl.sh — Otomatisasi SSL/TLS Certificate via acme.sh (trilingual EN/ID/ZH)
# Branding: wrwb Store
#
# Kenapa acme.sh (bukan Certbot)?
#   - Ringan: murni shell script, tanpa dependensi Python berat
#   - Auto-renew built-in via cron (tanpa systemd timer tambahan)
#   - Mendukung DNS API (Cloudflare, dll) — handal di balik firewall/CDN
#   - Cocok untuk VPS kecil (512 MB RAM)
#
# Mode yang didukung:
#   1. Standalone (port 80 sementara) — butuh port 80 bebas saat issuance
#   2. DNS API Cloudflare — tanpa buka port, handal di balik CDN/firewall
#
# Sertifikat disimpan di /etc/vpn-ssl/<domain>/ (fullchain.pem + key.pem)
# dan bisa dipakai Xray (VLESS/VLESS-gRPC/Trojan TLS), Stunnel, Nginx, dll.
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This file is a library. Do not run it directly." >&2
  exit 1
fi

SSL_DIR="/etc/vpn-ssl"
SSL_PARAMS="$SSL_DIR/params"
ACME_HOME="/root/.acme.sh"
ACME_BIN="$ACME_HOME/acme.sh"
# ZeroSSL adalah CA default acme.sh sejak v3; paksa Let's Encrypt agar
# tidak perlu registrasi email (lebih cocok untuk otomasi non-interaktif).
ACME_SERVER_DEFAULT="letsencrypt"

ssl_detect_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64|aarch64|arm64|armv7l|armhf|armv6l) return 0 ;;
    *) return 1 ;;
  esac
}

# Pastikan dependensi minimal acme.sh tersedia (curl + openssl + cron + socat u/ standalone)
ssl_install_deps() {
  detect_os
  log_step "$(T "Installing acme.sh dependencies (curl, openssl, cron, socat)..." "Menginstal dependensi acme.sh (curl, openssl, cron, socat)..." "正在安装 acme.sh 依赖（curl、openssl、cron、socat）...")"
  case "$PKG_MGR" in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y || true
      apt-get install -y curl openssl ca-certificates cron socat || \
        apt-get install -y curl openssl ca-certificates cron-daemon socat || \
        apt-get install -y curl openssl ca-certificates socat
      ;;
    dnf|yum)
      $PKG_MGR install -y curl openssl ca-certificates cronie socat || \
        $PKG_MGR install -y curl openssl socat || true
      systemctl enable crond >/dev/null 2>&1 || systemctl enable cron >/dev/null 2>&1 || true
      systemctl start crond >/dev/null 2>&1 || systemctl start cron >/dev/null 2>&1 || true
      ;;
    pacman)
      pacman -Sy --noconfirm curl openssl ca-certificates cronie socat
      systemctl enable cronie >/dev/null 2>&1 || true
      systemctl start cronie >/dev/null 2>&1 || true
      ;;
    apk)
      apk add --no-cache curl openssl ca-certificates dcron socat
      rc-update add dcron default 2>/dev/null || true
      rc-service dcron start 2>/dev/null || true
      ;;
    zypper)
      zypper install -y curl openssl ca-certificates cron socat
      systemctl enable cron >/dev/null 2>&1 || true
      systemctl start cron >/dev/null 2>&1 || true
      ;;
    *)
      log_warn "$(T "Package manager '$PKG_MGR' unknown — ensure curl, openssl, cron, socat manually." "Package manager '$PKG_MGR' tidak dikenal — pastikan curl, openssl, cron, socat manual." "软件包管理器 '$PKG_MGR' 未知 — 请手动确保 curl、openssl、cron、socat 已安装。")"
      ;;
  esac
}

# Install acme.sh bila belum ada (idempotent)
# Argumen opsional: --soft (atau 1) => bila gagal hanya warning + return 1.
# Dipakai install.sh default agar instalasi VPN tetap lanjut bila download gagal.
ssl_install_acme() {
  local soft=0
  if [[ "${1:-}" == "--soft" || "${1:-}" == "1" || "${1:-}" == "soft" ]]; then
    soft=1
  fi
  if [[ -x "$ACME_BIN" ]]; then
    log_info "$(T "acme.sh already installed at $ACME_BIN" "acme.sh sudah terinstal di $ACME_BIN" "acme.sh 已安装于 $ACME_BIN")"
    return 0
  fi
  ssl_install_deps
  log_step "$(T "Installing acme.sh (lightweight ACME client)..." "Menginstal acme.sh (ACME client ringan)..." "正在安装 acme.sh（轻量 ACME 客户端）...")"
  track_temp "/tmp/get-acme.sh"
  if ! curl -fsSL --retry 2 --connect-timeout 15 https://get.acme.sh -o /tmp/get-acme.sh; then
    rm -f /tmp/get-acme.sh
    if [[ "$soft" -eq 1 ]]; then
      log_warn "$(T "Could not download acme.sh installer — skipping pre-install (run menu 24 / setup-ssl.sh later)." "Gagal mengunduh installer acme.sh — pre-instal dilewati (jalankan menu 24 / setup-ssl.sh nanti)." "下载 acme.sh 安装程序失败 — 已跳过预安装（稍后请运行菜单 24 / setup-ssl.sh）。")"
      return 1
    fi
    die "$(T "Failed to download acme.sh installer. Check internet connection." "Gagal mengunduh installer acme.sh. Periksa koneksi internet." "下载 acme.sh 安装程序失败。请检查网络连接。")"
  fi
  if ! sh /tmp/get-acme.sh --nocron && ! sh /tmp/get-acme.sh; then
    rm -f /tmp/get-acme.sh
    if [[ "$soft" -eq 1 ]]; then
      log_warn "$(T "acme.sh pre-install failed — skipping (run menu 24 / setup-ssl.sh later)." "Pre-instal acme.sh gagal — dilewati (jalankan menu 24 / setup-ssl.sh nanti)." "acme.sh 预安装失败 — 已跳过（稍后请运行菜单 24 / setup-ssl.sh）。")"
      return 1
    fi
    die "$(T "acme.sh installation failed." "Instalasi acme.sh gagal." "acme.sh 安装失败。")"
  fi
  rm -f /tmp/get-acme.sh
  if [[ ! -x "$ACME_BIN" ]]; then
    if [[ "$soft" -eq 1 ]]; then
      log_warn "$(T "acme.sh binary missing after pre-install — skipping." "Binary acme.sh tidak ada setelah pre-instal — dilewati." "预安装后未找到 acme.sh — 已跳过。")"
      return 1
    fi
    die "$(T "acme.sh binary not found after install at $ACME_BIN" "Binary acme.sh tidak ditemukan setelah instalasi di $ACME_BIN" "安装后未在 $ACME_BIN 找到 acme.sh")"
  fi
  # Paksa CA ke Lets Encrypt (tanpa registrasi email)
  "$ACME_BIN" --set-default-ca --server "$ACME_SERVER_DEFAULT" >/dev/null 2>&1 || true
  log_success "$(T "acme.sh installed ($("$ACME_BIN" --version 2>/dev/null | head -n1))." "acme.sh terinstal ($("$ACME_BIN" --version 2>/dev/null | head -n1))." "acme.sh 已安装（$("$ACME_BIN" --version 2>/dev/null | head -n1)）。")"
}

# Simpan parameter SSL (domain, mode, email, dns provider)
ssl_save_params() {
  local domain="$1" mode="$2" email="${3:-}" dns_provider="${4:-}"
  mkdir -p "$SSL_DIR"
  chmod 700 "$SSL_DIR"
  cat > "$SSL_PARAMS" <<EOF
SSL_DOMAIN="$domain"
SSL_MODE="$mode"
SSL_EMAIL="$email"
SSL_DNS_PROVIDER="$dns_provider"
SSL_ISSUED_AT="$(date +%Y-%m-%d)"
SSL_CERT_DIR="$SSL_DIR/$domain"
EOF
  chmod 600 "$SSL_PARAMS"
}

ssl_load_params() {
  [[ -f "$SSL_PARAMS" ]] || return 1
  # shellcheck disable=SC1090
  source "$SSL_PARAMS"
  return 0
}

# Cek apakah sertifikat masih valid (tidak kedaluwarsa). Return 0 bila valid.
ssl_cert_valid() {
  local cert_file="${1:-$SSL_DIR/${SSL_DOMAIN:-}/fullchain.pem}"
  [[ -f "$cert_file" ]] || return 1
  if openssl x509 -in "$cert_file" -noout -checkend 0 >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Tampilkan sisa masa berlaku sertifikat (hari)
ssl_cert_days_left() {
  local cert_file="${1:-$SSL_DIR/${SSL_DOMAIN:-}/fullchain.pem}"
  [[ -f "$cert_file" ]] || { echo "?"; return 1; }
  local end_epoch now_epoch
  end_epoch="$(date -d "$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)" +%s 2>/dev/null || echo 0)"
  now_epoch="$(date +%s)"
  if [[ "$end_epoch" -gt 0 ]]; then
    echo $(( (end_epoch - now_epoch) / 86400 ))
  else
    echo "?"
  fi
}

# Bebaskan port 80 sementara untuk standalone: hentikan service yang memakai :80
# Mengembalikan daftar service yang dihentikan via SSL_STOPPED_SVCS (dipakai ssl_restore_port80)
ssl_free_port80() {
  SSL_STOPPED_SVCS=""
  # v4.8: hard conflict check on :80 (ss/netstat//proc fallback + owner name)
  if is_port_in_use "80" "tcp"; then
    log_warn "$(T "Port 80/tcp is occupied (owner: $(port_owner 80 tcp))." "Port 80/tcp ditempati (pemilik: $(port_owner 80 tcp))." "端口 80/tcp 被占用（占用者：$(port_owner 80 tcp)）。")"
  fi
  if command -v ss &>/dev/null && ss -lnt 2>/dev/null | grep -Eq ":(80)[[:space:]]"; then
    log_warn "$(T "Port 80 is in use — stopping conflicting services temporarily..." "Port 80 sedang dipakai — menghentikan service yang konflik sementara..." "端口 80 被占用 — 正在临时停止冲突服务...")"
    for svc in ssh-ws nginx apache2 httpd caddy trojan-go; do
      if systemctl is-active --quiet "$svc" 2>/dev/null; then
        systemctl stop "$svc" 2>/dev/null || true
        SSL_STOPPED_SVCS="$SSL_STOPPED_SVCS $svc"
        log_info "$(T "Stopped $svc (will be restored after issuance)." "Menghentikan $svc (akan dikembalikan setelah issuance)." "已停止 $svc（签发后将恢复）。")"
      fi
    done
    # Verifikasi port 80 benar-benar bebas
    if ss -lnt 2>/dev/null | grep -Eq ":(80)[[:space:]]"; then
      log_error "$(T "Port 80 is still in use after stopping known services." "Port 80 masih dipakai setelah menghentikan service yang dikenal." "停止已知服务后端口 80 仍被占用。")"
      log_error "$(T "Find the owner: ss -lntp | grep ':80 '" "Cari pemiliknya: ss -lntp | grep ':80 '" "查找占用者：ss -lntp | grep ':80 '")"
      return 1
    fi
  fi
  open_firewall_port "80" "tcp" "SSL-Standalone"
  return 0
}

# Kembalikan service yang dihentikan ssl_free_port80
ssl_restore_port80() {
  local svc
  for svc in ${SSL_STOPPED_SVCS:-}; do
    systemctl start "$svc" 2>/dev/null || true
    log_info "$(T "Restored $svc." "Mengembalikan $svc." "已恢复 $svc。")"
  done
  SSL_STOPPED_SVCS=""
}

# Terbitkan sertifikat via standalone (butuh domain mengarah ke IP server ini)
ssl_issue_standalone() {
  local domain="$1" email="${2:-}"
  ssl_install_acme
  log_step "$(T "Issuing certificate for $domain via standalone (port 80)..." "Menerbitkan sertifikat untuk $domain via standalone (port 80)..." "正在通过 standalone（端口 80）为 $domain 签发证书...")"
  ssl_free_port80 || return 1
  local issue_rc=0
  if [[ -n "$email" ]]; then
    "$ACME_BIN" --issue --standalone ${ACME_STANDALONE_PORT:+-httpport "$ACME_STANDALONE_PORT"} -d "$domain" --accountemail "$email" --server "$ACME_SERVER_DEFAULT" || issue_rc=$?
  else
    "$ACME_BIN" --issue --standalone ${ACME_STANDALONE_PORT:+-httpport "$ACME_STANDALONE_PORT"} -d "$domain" --server "$ACME_SERVER_DEFAULT" || issue_rc=$?
  fi
  ssl_restore_port80
  if [[ "$issue_rc" -ne 0 ]]; then
    log_error "$(T "Standalone issuance failed. Ensure DNS A record of $domain points to this server IP ($(get_public_ip)) and port 80 is reachable from the internet." "Issuance standalone gagal. Pastikan DNS A record $domain mengarah ke IP server ini ($(get_public_ip)) dan port 80 bisa dijangkau dari internet." "standalone 签发失败。请确保 $domain 的 DNS A 记录指向本机 IP ($(get_public_ip))，且端口 80 可从公网访问。")"
    return 1
  fi
  ssl_install_cert "$domain" || return 1
  ssl_save_params "$domain" "standalone" "$email" ""
  ssl_enable_autorenew
  return 0
}

# Terbitkan sertifikat via DNS API (Cloudflare) — tanpa buka port, handal di balik CDN/firewall
# Membutuhkan CF_Token (disarankan, scoped) atau CF_Key+CF_Email (global key, legacy)
ssl_issue_dns() {
  local domain="$1" provider="${2:-cloudflare}" email="${3:-}"
  ssl_install_acme
  local dns_arg="dns_cf"
  case "$provider" in
    cloudflare|cf) dns_arg="dns_cf" ;;
    *) die "$(T "DNS provider '$provider' is not supported yet. Supported: cloudflare." "DNS provider '$provider' belum didukung. Didukung: cloudflare." "尚不支持 DNS 提供商 '$provider'。支持：cloudflare。")" ;;
  esac
  if [[ -z "${CF_Token:-}" && (-z "${CF_Key:-}" || -z "${CF_Email:-}") ]]; then
    log_error "$(T "Cloudflare API credentials missing." "Kredensial API Cloudflare belum diisi." "缺少 Cloudflare API 凭证。")"
    log_error "$(T "Set env first, e.g.: export CF_Token='your-api-token' (recommended)" "Isi env dulu, mis.: export CF_Token='token-api-anda' (disarankan)" "请先设置环境变量，例如：export CF_Token='your-api-token'（推荐）")"
    log_error "$(T "Or legacy: export CF_Key='global-key' CF_Email='you@example.com'" "Atau legacy: export CF_Key='global-key' CF_Email='you@example.com'" "或传统方式：export CF_Key='global-key' CF_Email='you@example.com'")"
    return 1
  fi
  log_step "$(T "Issuing certificate for $domain via DNS API ($provider)..." "Menerbitkan sertifikat untuk $domain via DNS API ($provider)..." "正在通过 DNS API ($provider) 为 $domain 签发证书...")"
  local issue_rc=0
  if [[ -n "$email" ]]; then
    "$ACME_BIN" --issue --dns "$dns_arg" -d "$domain" --accountemail "$email" --server "$ACME_SERVER_DEFAULT" || issue_rc=$?
  else
    "$ACME_BIN" --issue --dns "$dns_arg" -d "$domain" --server "$ACME_SERVER_DEFAULT" || issue_rc=$?
  fi
  if [[ "$issue_rc" -ne 0 ]]; then
    log_error "$(T "DNS API issuance failed. Verify the API token (Zone:DNS:Edit permission) and that $domain is in your Cloudflare account." "Issuance DNS API gagal. Verifikasi token API (izin Zone:DNS:Edit) dan $domain ada di akun Cloudflare Anda." "DNS API 签发失败。请验证 API 令牌（Zone:DNS:Edit 权限）且 $domain 在您的 Cloudflare 账户中。")"
    return 1
  fi
  ssl_install_cert "$domain" || return 1
  ssl_save_params "$domain" "dns" "$email" "$provider"
  ssl_enable_autorenew
  return 0
}

# Install sertifikat ke $SSL_DIR/<domain>/ + set reload hook (restart xray bila ada)
ssl_install_cert() {
  local domain="$1"
  local dest="$SSL_DIR/$domain"
  mkdir -p "$dest"
  chmod 700 "$SSL_DIR" "$dest"
  log_step "$(T "Installing certificate to $dest ..." "Menginstal sertifikat ke $dest ..." "正在安装证书到 $dest ...")"
  local reload_cmd="true"
  if systemctl list-unit-files 2>/dev/null | grep -q "^xray\\.service"; then
    reload_cmd="systemctl reload-or-restart xray"
  fi
  "$ACME_BIN" --install-cert -d "$domain" \
    --key-file "$dest/key.pem" \
    --fullchain-file "$dest/fullchain.pem" \
    --reloadcmd "$reload_cmd" || return 1
  chmod 600 "$dest/key.pem"
  chmod 644 "$dest/fullchain.pem"
  log_success "$(T "Certificate installed: $dest/fullchain.pem (+ key.pem)" "Sertifikat terinstal: $dest/fullchain.pem (+ key.pem)" "证书已安装：$dest/fullchain.pem（+ key.pem）")"
  # Tajamkan keamanan: pastikan private key hanya root
  chown root:root "$dest/key.pem" 2>/dev/null || true
  return 0
}

# Aktifkan auto-renew via cron bawaan acme.sh (cek tiap hari, renew bila < 30 hari)
ssl_enable_autorenew() {
  log_step "$(T "Enabling certificate auto-renew (cron)..." "Mengaktifkan auto-renew sertifikat (cron)..." "正在启用证书自动续期（cron）...")"
  "$ACME_BIN" --install-cronjob >/dev/null 2>&1 || true
  if crontab -l 2>/dev/null | grep -q "acme.sh.*--cron"; then
    log_success "$(T "Auto-renew enabled: acme.sh cron checks daily, renews when < 30 days left." "Auto-renew aktif: cron acme.sh cek harian, renew bila sisa < 30 hari." "自动续期已启用：acme.sh cron 每日检查，剩余 < 30 天时续期。")"
  else
    log_warn "$(T "acme.sh cron entry not detected — run '$ACME_BIN --install-cronjob' manually if needed." "Entri cron acme.sh tidak terdeteksi — jalankan '$ACME_BIN --install-cronjob' manual bila perlu." "未检测到 acme.sh cron 条目 — 需要时请手动运行 '$ACME_BIN --install-cronjob'。")"
  fi
}

# Renew manual (paksa bila --force)
ssl_renew() {
  local force="${1:-0}"
  ssl_install_acme
  if [[ "$force" == "1" || "$force" == "--force" ]]; then
    "$ACME_BIN" --renew --force --server "$ACME_SERVER_DEFAULT"
  else
    "$ACME_BIN" --renew --server "$ACME_SERVER_DEFAULT"
  fi
}

# Tampilkan status sertifikat (domain, mode, sisa hari, cron)
ssl_status() {
  echo "================================================================================"
  echo -e "${_C_BOLD}$(T "SSL CERTIFICATE STATUS (acme.sh)" "STATUS SERTIFIKAT SSL (acme.sh)" "SSL 证书状态 (acme.sh)")${_C_RESET}"
  echo "================================================================================"
  if [[ -x "$ACME_BIN" ]]; then
    echo "$(T "acme.sh version       : $("$ACME_BIN" --version 2>/dev/null | head -n1)" "Versi acme.sh          : $("$ACME_BIN" --version 2>/dev/null | head -n1)" "acme.sh 版本           : $("$ACME_BIN" --version 2>/dev/null | head -n1)")"
  else
    echo -e "$(T "acme.sh               : " "acme.sh               : " "acme.sh               : ")${_C_YELLOW}[NOT INSTALLED]${_C_RESET}"
    return 0
  fi
  if ssl_load_params; then
    local cert_file="$SSL_DIR/$SSL_DOMAIN/fullchain.pem"
    echo "$(T "Domain                : $SSL_DOMAIN" "Domain                : $SSL_DOMAIN" "域名                  : $SSL_DOMAIN")"
    echo "$(T "Mode                  : $SSL_MODE" "Mode                  : $SSL_MODE" "模式                  : $SSL_MODE")"
    if [[ -f "$cert_file" ]]; then
      local days_left expiry
      days_left="$(ssl_cert_days_left "$cert_file")"
      expiry="$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)"
      if ssl_cert_valid "$cert_file"; then
        echo -e "$(T "Certificate           : " "Sertifikat            : " "证书                  : ")${_C_GREEN}[VALID]${_C_RESET} ($(T "$days_left days left, expires: $expiry" "sisa $days_left hari, kedaluwarsa: $expiry" "剩余 $days_left 天，到期：$expiry"))"
      else
        echo -e "$(T "Certificate           : " "Sertifikat            : " "证书                  : ")${_C_RED}[EXPIRED / INVALID]${_C_RESET}"
      fi
      echo "$(T "Fullchain             : $cert_file" "Fullchain             : $cert_file" "证书链                : $cert_file")"
      echo "$(T "Private key           : $SSL_DIR/$SSL_DOMAIN/key.pem" "Private key           : $SSL_DIR/$SSL_DOMAIN/key.pem" "私钥                  : $SSL_DIR/$SSL_DOMAIN/key.pem")"
    else
      echo -e "$(T "Certificate file      : " "File sertifikat       : " "证书文件              : ")${_C_RED}[MISSING]${_C_RESET} ($cert_file)"
    fi
  else
    echo "$(T "No certificate issued via this installer yet." "Belum ada sertifikat yang diterbitkan via installer ini." "尚未通过此安装程序签发任何证书。")"
  fi
  if crontab -l 2>/dev/null | grep -q "acme.sh.*--cron"; then
    echo -e "$(T "Auto-renew (cron)     : " "Auto-renew (cron)     : " "自动续期 (cron)        : ")${_C_GREEN}[ENABLED]${_C_RESET} ($(crontab -l 2>/dev/null | grep "acme.sh.*--cron" | head -n1 | xargs))"
  else
    echo -e "$(T "Auto-renew (cron)     : " "Auto-renew (cron)     : " "自动续期 (cron)        : ")${_C_YELLOW}[NOT SET]${_C_RESET}"
  fi
  echo "================================================================================"
}

# Hapus sertifikat + cron (dipakai uninstall.sh)
ssl_remove() {
  local domain="${1:-}"
  if [[ -z "$domain" ]] && ssl_load_params; then
    domain="$SSL_DOMAIN"
  fi
  if [[ -n "$domain" && -x "$ACME_BIN" ]]; then
    log_info "$(T "Removing certificate for $domain from acme.sh..." "Menghapus sertifikat $domain dari acme.sh..." "正在从 acme.sh 删除 $domain 的证书...")"
    "$ACME_BIN" --remove -d "$domain" >/dev/null 2>&1 || true
  fi
  if [[ -n "$domain" ]]; then
    rm -rf "$SSL_DIR/$domain"
  fi
  if [[ ! -x "$ACME_BIN" ]]; then
    rm -rf "$SSL_DIR"
  fi
  log_success "$(T "SSL certificate data cleaned up." "Data sertifikat SSL dibersihkan." "SSL 证书数据已清理。")"
}
