#!/bin/bash
# ==============================================================================
#  setup-ssl.sh — Otomatisasi SSL/TLS Certificate via acme.sh (EN/ID/ZH)
#  Usage:
#    sudo ./setup-ssl.sh [--domain example.com] [--mode standalone|dns]
#                        [--email you@example.com] [--dns-provider cloudflare]
#                        [--force] [--status] [--renew [--force]]
#    Env untuk DNS API Cloudflare:
#      CF_Token='...'  (disarankan)  atau  CF_Key='...' CF_Email='...'
#  Branding: wrwb Store
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/system.sh
source "$SCRIPT_DIR/lib/system.sh"
# shellcheck source=lib/ssl.sh
source "$SCRIPT_DIR/lib/ssl.sh"

need_root

DOMAIN="" MODE="" EMAIL="" DNS_PROVIDER="cloudflare" FORCE=0 SHOW_STATUS=0 DO_RENEW=0 RENEW_FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain=*) DOMAIN="${1#--domain=}" ;;
    --domain) DOMAIN="${2:-}"; shift ;;
    --mode=*) MODE="${1#--mode=}" ;;
    --mode) MODE="${2:-}"; shift ;;
    --email=*) EMAIL="${1#--email=}" ;;
    --email) EMAIL="${2:-}"; shift ;;
    --dns-provider=*) DNS_PROVIDER="${1#--dns-provider=}" ;;
    --dns-provider) DNS_PROVIDER="${2:-}"; shift ;;
    --force) FORCE=1 ;;
    --status) SHOW_STATUS=1 ;;
    --renew) DO_RENEW=1 ;;
    --lang=*) VPN_LANG_CLI="${1#--lang=}"; export VPN_LANG_CLI ;;
    --lang) VPN_LANG_CLI="${2:-}"; export VPN_LANG_CLI; shift ;;
    -h|--help)
      echo "$(T "Usage:" "Cara pakai:" "用法：") sudo ./setup-ssl.sh [--domain example.com] [--mode standalone|dns] [--email you@example.com] [--force] [--status] [--renew]"
      echo ""
      echo "$(T "Modes:" "Mode:" "模式：")"
      echo "  standalone  — $(T "HTTP-01 via port 80 (domain must point to this server)." "HTTP-01 via port 80 (domain harus mengarah ke server ini)." "经端口 80 的 HTTP-01（域名须指向本机）。")"
      echo "  dns         — $(T "DNS API Cloudflare (no open port, CDN/firewall-proof)." "DNS API Cloudflare (tanpa buka port, tahan CDN/firewall)." "Cloudflare DNS API（无需开放端口，不怕 CDN/防火墙）。")"
      exit 0
      ;;
    *) log_warn "$(T "Unknown option: $1" "Opsi tidak dikenal: $1" "未知选项：$1")";;
  esac
  shift
done

# --status: tampilkan status lalu keluar
if [[ "$SHOW_STATUS" -eq 1 ]]; then
  ssl_status
  exit 0
fi

# --renew: renew manual lalu keluar
if [[ "$DO_RENEW" -eq 1 ]]; then
  if [[ "$RENEW_FORCE" -eq 0 && "$FORCE" -eq 1 ]]; then
    RENEW_FORCE=1
  fi
  if [[ "$RENEW_FORCE" -eq 1 ]]; then
    ssl_renew --force
  else
    ssl_renew
  fi
  exit 0
fi

echo "================================================================================"
echo -e "${_C_BOLD}$(T "SSL CERTIFICATE SETUP via acme.sh (wrwb Store)" "SETUP SERTIFIKAT SSL via acme.sh (wrwb Store)" "经 acme.sh 设置 SSL 证书 (wrwb Store)")${_C_RESET}"
echo "================================================================================"

# Domain (argumen atau interaktif)
if [[ -z "$DOMAIN" ]]; then
  if ssl_load_params && [[ -n "${SSL_DOMAIN:-}" && "$FORCE" -eq 0 ]]; then
    DOMAIN="$SSL_DOMAIN"
    log_info "$(T "Using existing domain from params: $DOMAIN" "Memakai domain dari params: $DOMAIN" "使用 params 中的已有域名：$DOMAIN")"
  else
    read -rp "$(T "Domain name (e.g. vpn.example.com): " "Nama domain (mis. vpn.example.com): " "域名（例如 vpn.example.com）：")" DOMAIN
  fi
fi
[[ -n "$DOMAIN" ]] || die "$(T "Domain is required." "Domain wajib diisi." "域名为必需。")"
# Validasi format domain sederhana
if ! [[ "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}$ ]]; then
  die "$(T "Invalid domain format: $DOMAIN" "Format domain tidak valid: $DOMAIN" "域名格式无效：$DOMAIN")"
fi

# Mode (argumen atau interaktif)
if [[ -z "$MODE" ]]; then
  if ssl_load_params && [[ -n "${SSL_MODE:-}" && "$FORCE" -eq 0 ]]; then
    MODE="$SSL_MODE"
    log_info "$(T "Using existing mode from params: $MODE" "Memakai mode dari params: $MODE" "使用 params 中的已有模式：$MODE")"
  else
    echo "$(T "Choose issuance mode:" "Pilih mode issuance:" "选择签发模式：")"
    echo "  1) standalone  — $(T "port 80 (simple, needs port 80 free + DNS A to this server)" "port 80 (simpel, butuh port 80 bebas + DNS A ke server ini)" "端口 80（简单，需端口 80 空闲 + DNS A 指向本机）")"
    echo "  2) dns         — $(T "Cloudflare DNS API (no open port, works behind CDN/firewall)" "Cloudflare DNS API (tanpa buka port, tahan CDN/firewall)" "Cloudflare DNS API（无需开放端口，不怕 CDN/防火墙）")"
    local mode_choice=""
    read -rp "$(T "Mode [1-2] (default 1): " "Mode [1-2] (default 1): " "模式 [1-2]（默认 1）：")" mode_choice || true
    case "${mode_choice:-1}" in
      2) MODE="dns" ;;
      *) MODE="standalone" ;;
    esac
  fi
fi

# Email opsional (untuk notifikasi expiry Let's Encrypt)
if [[ -z "$EMAIL" ]]; then
  read -rp "$(T "Email for expiry notices (optional, Enter to skip): " "Email untuk notifikasi kedaluwarsa (opsional, Enter untuk lewati): " "用于到期通知的邮箱（可选，回车跳过）：")" EMAIL || true
fi

case "$MODE" in
  standalone)
    ssl_issue_standalone "$DOMAIN" "$EMAIL" || \
      die "$(T "SSL setup failed (standalone)." "Setup SSL gagal (standalone)." "SSL 设置失败（standalone）。")"
    ;;
  dns)
    ssl_issue_dns "$DOMAIN" "$DNS_PROVIDER" "$EMAIL" || \
      die "$(T "SSL setup failed (dns)." "Setup SSL gagal (dns)." "SSL 设置失败（dns）。")"
    ;;
  *)
    die "$(T "Unknown mode: $MODE (use standalone|dns)" "Mode tidak dikenal: $MODE (pakai standalone|dns)" "未知模式：$MODE（请用 standalone|dns）")"
    ;;
esac

echo ""
ssl_status
echo ""
log_success "$(T "SSL setup complete! Cert: $SSL_DIR/$DOMAIN/fullchain.pem | Key: $SSL_DIR/$DOMAIN/key.pem" "Setup SSL selesai! Cert: $SSL_DIR/$DOMAIN/fullchain.pem | Key: $SSL_DIR/$DOMAIN/key.pem" "SSL 设置完成！证书：$SSL_DIR/$DOMAIN/fullchain.pem | 私钥：$SSL_DIR/$DOMAIN/key.pem")"
echo "$(T "Use it for: Xray TLS inbounds, Stunnel, Nginx/Caddy, Web Dashboard (https)." "Gunakan untuk: Xray TLS inbound, Stunnel, Nginx/Caddy, Web Dashboard (https)." "可用于：Xray TLS 入站、Stunnel、Nginx/Caddy、Web 面板 (https)。")"
