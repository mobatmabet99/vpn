#!/bin/bash
#
# lib/lang.sh — Bilingual support: English (default) / Indonesia
# Made by wrwb Store — v1.3
#
# Design: single codebase, no script duplication.
#   - Language is selected once at install time (default: English).
#   - Stored in /etc/vpn/lang ("en" or "id"), override via env VPN_LANG
#     or CLI flag --lang en|id (install.sh).
#   - All scripts source this file FIRST (via lib/common.sh),
#     then call lang_load.
#   - Use T "English text" "Teks Indonesia" for user-visible strings.
#
# Usage in any script:
#   source "$SCRIPT_DIR/lib/common.sh"   # auto-loads lang.sh
#   echo "$(T 'Hello' 'Halo')"
#
# In install.sh (interactive):
#   lang_ask             # prompts: English or Indonesia, default English
#   lang_save            # persists to /etc/vpn/lang
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This file is a library. Do not run it directly." >&2
  exit 1
fi

# Canonical file holding the chosen language ("en" or "id")
VPN_LANG_FILE="${VPN_LANG_FILE:-/etc/vpn/lang}"
# CLI override set by --lang flag (install.sh / menu.sh)
VPN_LANG_CLI="${VPN_LANG_CLI:-}"

# Normalize any user input to "en" or "id". Unknown/empty -> "en" (default).
lang_normalize() {
  local v="${1:-}"
  v="$(echo "$v" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$v" in
    id|idn|ind|indonesia|indonesian|bahasa|bahasa-indonesia) echo "id" ;;
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

# Returns 0 when Indonesian is active, 1 otherwise (English).
lang_is_id() { [[ "${VPN_LANG:-en}" == "id" ]]; }

# T "English" "Indonesia" -> prints the active-language string (no newline).
T() {
  if lang_is_id; then
    printf '%s' "${2:-$1}"
  else
    printf '%s' "$1"
  fi
}

# TE "English" "Indonesia" -> echo with newline (convenience).
TE() { T "$1" "${2:-$1}"; echo; }

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
  echo "Choose installation language / Pilih bahasa instalasi:"
  echo "  1) English (default)"
  echo "  2) Indonesia"
  local choice=""
  read -rp "Select [1-2] / Pilih [1-2] (default 1 - English): " choice || true
  case "${choice:-1}" in
    2) VPN_LANG="id" ;;
    *) VPN_LANG="en" ;;
  esac
  export VPN_LANG
}

# One-line label of the active language (for banners / status).
lang_label() {
  if lang_is_id; then
    printf 'Bahasa: Indonesia'
  else
    printf 'Language: English'
  fi
}

# Ensure a sane default even if the caller forgot lang_load.
[[ -n "${VPN_LANG:-}" ]] || VPN_LANG="en"
export VPN_LANG
