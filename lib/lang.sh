#!/bin/bash
#
# lib/lang.sh — Trilingual support: English (default) / Indonesia / 中文
# Made by wrwb Store — v1.4
#
# Design: single codebase, no script duplication.
#   - Language is selected once at install time (default: English).
#   - Stored in /etc/vpn/lang ("en", "id" or "zh"), override via env VPN_LANG
#     or CLI flag --lang en|id|zh (install.sh).
#   - All scripts source this file FIRST (via lib/common.sh),
#     then call lang_load.
#   - Use T "English text" "Teks Indonesia" "中文文本" for user-visible strings.
#     Old 2-arg calls still work: Chinese falls back to English.
#
# Usage in any script:
#   source "$SCRIPT_DIR/lib/common.sh"   # auto-loads lang.sh
#   echo "$(T 'Hello' 'Halo' '你好')"
#
# In install.sh (interactive):
#   lang_ask             # prompts: English / Indonesia / 中文, default English
#   lang_save            # persists to /etc/vpn/lang
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This file is a library. Do not run it directly." >&2
  exit 1
fi

# Canonical file holding the chosen language ("en", "id" or "zh")
VPN_LANG_FILE="${VPN_LANG_FILE:-/etc/vpn/lang}"
# CLI override set by --lang en|id|zh flag (install.sh / menu.sh)
VPN_LANG_CLI="${VPN_LANG_CLI:-}"

# Normalize any user input to "en", "id" or "zh". Unknown/empty -> "en" (default).
lang_normalize() {
  local v="${1:-}"
  v="$(echo "$v" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$v" in
    id|idn|ind|indonesia|indonesian|bahasa|bahasa-indonesia) echo "id" ;;
    zh|cn|chi|chinese|mandarin|china|zh-cn|zh_cn|zhhans|zh-hans|zhhans-cn) echo "zh" ;;
    en|eng|english|inggris) echo "en" ;;
    *) echo "en" ;;
  esac
}

# Load effective language: CLI > env > file > default(en).
lang_load() {
  if [[ -n "${VPN_LANG_CLI:-}" ]]; then
    VPN_LANG="$(lang_normalize "$VPN_LANG_CLI")"
  elif [[ -n "${VPN_LANG:-}" ]]; then
    VPN_LANG="$(lang_normalize "$VPN_LANG")"
  elif [[ -f "$VPN_LANG_FILE" ]]; then
    VPN_LANG="$(lang_normalize "$(cat "$VPN_LANG_FILE" 2>/dev/null || echo en)")"
  else
    VPN_LANG="en"
  fi
  export VPN_LANG
}

# Persist current language for all other scripts.
lang_save() {
  lang_load
  mkdir -p "$(dirname "$VPN_LANG_FILE")" 2>/dev/null || true
  echo "$VPN_LANG" > "$VPN_LANG_FILE" 2>/dev/null || true
  chmod 644 "$VPN_LANG_FILE" 2>/dev/null || true
}

# Returns 0 when Indonesian is active, 1 otherwise.
lang_is_id() { [[ "${VPN_LANG:-en}" == "id" ]]; }

# Returns 0 when Chinese is active, 1 otherwise.
lang_is_zh() { [[ "${VPN_LANG:-en}" == "zh" ]]; }

# T "English" "Indonesia" "中文" -> prints the active-language string (no newline).
# A missing/empty 3rd argument falls back to English.
T() {
  case "${VPN_LANG:-en}" in
    id) printf '%s' "${2:-$1}" ;;
    zh) printf '%s' "${3:-$1}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# TE "English" "Indonesia" "中文" -> echo with newline (convenience).
TE() { T "$1" "${2:-$1}" "${3:-$1}"; echo; }

# Interactive language chooser. Default = English (just press Enter).
# Respects AUTO_YES (keeps current/default en) and VPN_LANG_CLI.
lang_ask() {
  if [[ "${AUTO_YES:-0}" == "1" ]]; then
    lang_load
    [[ -z "${VPN_LANG:-}" ]] && VPN_LANG="en"
    export VPN_LANG
    return 0
  fi
  if [[ -n "${VPN_LANG_CLI:-}" ]]; then
    VPN_LANG="$(lang_normalize "$VPN_LANG_CLI")"
    export VPN_LANG
    return 0
  fi
  lang_load
  # If a language was already persisted (re-install), keep it silently.
  if [[ -f "$VPN_LANG_FILE" ]]; then
    return 0
  fi
  echo ""
  echo "Choose installation language / Pilih bahasa instalasi / 选择安装语言："
  echo "  1) English (default)"
  echo "  2) Indonesia"
  echo "  3) 中文 (简体)"
  local choice=""
  read -rp "Select [1-3] / Pilih [1-3] / 选择 [1-3] (default 1 - English): " choice || true
  case "${choice:-1}" in
    2) VPN_LANG="id" ;;
    3) VPN_LANG="zh" ;;
    *) VPN_LANG="en" ;;
  esac
  export VPN_LANG
}

# One-line label of the active language (for banners / status).
lang_label() {
  case "${VPN_LANG:-en}" in
    id) printf 'Bahasa: Indonesia' ;;
    zh) printf '语言：简体中文' ;;
    *) printf 'Language: English' ;;
  esac
}

# Ensure a sane default even if the caller forgot lang_load.
[[ -n "${VPN_LANG:-}" ]] || VPN_LANG="en"
export VPN_LANG
