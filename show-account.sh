#!/bin/bash
# ==============================================================================
#  show-account.sh — Re-display saved account summary (v4.9, trilingual EN/ID/ZH)
#  Usage:
#    sudo ./show-account.sh [username] [--qr]
#  Without args: shows the full saved summary (/etc/vpn-script/client-config.txt)
#  With username: shows that user's saved block (WireGuard .conf / Xray links /
#    SSH details) + optional --qr to render the QR code again.
#  Branding: wrwb Store
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/wireguard.sh
source "$SCRIPT_DIR/lib/wireguard.sh"
# shellcheck source=lib/xray.sh
source "$SCRIPT_DIR/lib/xray.sh"
# shellcheck source=lib/ssh.sh
source "$SCRIPT_DIR/lib/ssh.sh"
# shellcheck source=lib/openvpn.sh
source "$SCRIPT_DIR/lib/openvpn.sh"
# shellcheck source=lib/shadowsocks.sh
source "$SCRIPT_DIR/lib/shadowsocks.sh"

install_cleanup_trap
need_root

USERNAME="${1:-}"
WANT_QR=0
[[ "${2:-}${1:-}" == *"--qr"* ]] && WANT_QR=1

SUMMARY="$VPN_SUMMARY_FILE"

if [[ -z "$USERNAME" || "$USERNAME" == "--qr" ]]; then
  # Full summary view
  if [[ -f "$SUMMARY" ]]; then
    echo "================================================================================"
    echo -e "${_C_BOLD}$(T "SAVED ACCOUNT SUMMARY (wrwb Store)" "RINGKASAN AKUN TERSIMPAN (wrwb Store)" "已保存账户摘要 (wrwb Store)")${_C_RESET}"
    echo "================================================================================"
    echo "$(T "File: $SUMMARY" "File: $SUMMARY" "文件：$SUMMARY")"
    echo "--------------------------------------------------------------------------------"
    cat "$SUMMARY"
    echo "================================================================================"
  else
    log_warn "$(T "No saved summary yet at $SUMMARY" "Belum ada ringkasan tersimpan di $SUMMARY" "尚未在 $SUMMARY 保存摘要")"
    log_warn "$(T "New accounts are saved automatically from now on." "Akun baru otomatis tersimpan mulai sekarang." "从现在起新账户将自动保存。")"
  fi
  echo ""
  echo "$(T "Tip: sudo ./show-account.sh <username> [--qr] to re-show one user." "Tips: sudo ./show-account.sh <username> [--qr] untuk tampilkan ulang satu user." "提示：sudo ./show-account.sh <username> [--qr] 可重新显示单个用户。")"
  exit 0
fi

validate_client_name "$USERNAME"
echo "================================================================================"
echo -e "${_C_BOLD}$(T "ACCOUNT: $USERNAME" "AKUN: $USERNAME" "账户：$USERNAME")${_C_RESET}"
echo "================================================================================"

FOUND=0

# --- WireGuard ---
if [[ -f "$CLIENTS_DIR/$USERNAME/${USERNAME}.conf" ]]; then
  FOUND=1
  echo ""
  echo "--- WireGuard ---"
  cat "$CLIENTS_DIR/$USERNAME/${USERNAME}.conf"
  if [[ "$WANT_QR" -eq 1 ]]; then
    wg_show_client_qr "$CLIENTS_DIR/$USERNAME/${USERNAME}.conf" || true
  else
    echo "$(T "(add --qr to render the QR code)" "(tambah --qr untuk tampilkan QR code)" "（加 --qr 以显示二维码）")"
    [[ -f "$CLIENTS_DIR/$USERNAME/${USERNAME}.png" ]] && echo "$(T "PNG: $CLIENTS_DIR/$USERNAME/${USERNAME}.png" "PNG: $CLIENTS_DIR/$USERNAME/${USERNAME}.png" "PNG：$CLIENTS_DIR/$USERNAME/${USERNAME}.png")"
  fi
fi

# --- Xray ---
if [[ -f "$XRAY_ACCOUNTS_DB" ]] && grep -q "^${USERNAME}:" "$XRAY_ACCOUNTS_DB" 2>/dev/null; then
  FOUND=1
  echo ""
  echo "--- Xray/V2Ray ---"
  _uuid="$(awk -F: -v u="$USERNAME" '$1==u {print $2}' "$XRAY_ACCOUNTS_DB" | head -n1)"
  if [[ -n "$_uuid" ]]; then
    xray_print_links "$USERNAME" "$_uuid" 0
  fi
fi

# --- SSH ---
if [[ -f "$SSH_ACCOUNTS_DB" ]] && grep -q "^${USERNAME}:" "$SSH_ACCOUNTS_DB" 2>/dev/null; then
  FOUND=1
  echo ""
  echo "--- SSH ---"
  grep "^${USERNAME}:" "$SSH_ACCOUNTS_DB"
  # shellcheck disable=SC1090
  [[ -f "$SSH_PARAMS" ]] && source "$SSH_PARAMS"
  echo "$(T "Host: ${SSH_PUB_IP:-?} | SSH:${SSH_PORT:-22} Dropbear:${DROPBEAR_PORT:-143} TLS:${SSL_PORT:-444} WS:${WS_PORT:-8080}" "Host: ${SSH_PUB_IP:-?} | SSH:${SSH_PORT:-22} Dropbear:${DROPBEAR_PORT:-143} TLS:${SSL_PORT:-444} WS:${WS_PORT:-8080}" "主机：${SSH_PUB_IP:-?} | SSH:${SSH_PORT:-22} Dropbear:${DROPBEAR_PORT:-143} TLS:${SSL_PORT:-444} WS:${WS_PORT:-8080}")"
  if [[ -f "$SSH_DIR/.last-pass-$USERNAME" ]]; then
    echo "$(T "Password (saved at creation): $(cat "$SSH_DIR/.last-pass-$USERNAME")" "Password (tersimpan saat dibuat): $(cat "$SSH_DIR/.last-pass-$USERNAME")" "密码（创建时保存）：$(cat "$SSH_DIR/.last-pass-$USERNAME")")"
  else
    echo "$(T "Password: (not stored — reset with: passwd $USERNAME)" "Password: (tidak tersimpan — reset dengan: passwd $USERNAME)" "密码：（未保存 — 请用 passwd $USERNAME 重置）")"
  fi
fi

# --- OpenVPN ---
if [[ -f "$OVPN_CLIENTS_DIR/${USERNAME}.ovpn" ]]; then
  FOUND=1
  echo ""
  echo "--- OpenVPN ---"
  echo "$(T "Profile: $OVPN_CLIENTS_DIR/${USERNAME}.ovpn" "Profil: $OVPN_CLIENTS_DIR/${USERNAME}.ovpn" "配置文件：$OVPN_CLIENTS_DIR/${USERNAME}.ovpn")"
fi

# --- Shadowsocks ---
if [[ -f "$SS_PARAMS" ]]; then
  FOUND=1
  echo ""
  echo "--- Shadowsocks ---"
  # shellcheck disable=SC1090
  source "$SS_PARAMS"
  _ss_userinfo="$(echo -n "${SS_METHOD:-}:${SS_PASSWORD:-}" | base64 -w 0 2>/dev/null || echo -n "${SS_METHOD:-}:${SS_PASSWORD:-}" | base64 | tr -d '\n')"
  echo "$(T "URI: ss://${_ss_userinfo}@${SS_PUB_IP:-?}:${SS_PORT:-8388}#VPN-Shadowsocks" "URI: ss://${_ss_userinfo}@${SS_PUB_IP:-?}:${SS_PORT:-8388}#VPN-Shadowsocks" "URI：ss://${_ss_userinfo}@${SS_PUB_IP:-?}:${SS_PORT:-8388}#VPN-Shadowsocks")"
  echo "$(T "Method: ${SS_METHOD:-?} | Port: ${SS_PORT:-8388}" "Metode: ${SS_METHOD:-?} | Port: ${SS_PORT:-8388}" "加密方式：${SS_METHOD:-?} | 端口：${SS_PORT:-8388}")"
fi

if [[ "$FOUND" -eq 0 ]]; then
  log_warn "$(T "No account named '$USERNAME' found (checked WireGuard/Xray/SSH/OpenVPN/Shadowsocks)." "Tidak ada akun '$USERNAME' (sudah cek WireGuard/Xray/SSH/OpenVPN/Shadowsocks)." "未找到账户 '$USERNAME'（已检查 WireGuard/Xray/SSH/OpenVPN/Shadowsocks）。")"
  echo ""
  echo "$(T "Full saved summary:" "Ringkasan tersimpan penuh:" "完整已保存摘要：") $SUMMARY"
fi
echo "================================================================================"
