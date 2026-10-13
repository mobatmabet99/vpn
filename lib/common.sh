#!/bin/bash
#
# lib/common.sh — Shared functions for all VPN scripts (English default, Indonesian/Chinese optional)
# Supported: Ubuntu 20.04/22.04/24.04/26.04, Debian 10/11/12/13,
#            CentOS / Rocky / AlmaLinux 8/9, RHEL 8/9
# Branding: wrwb Store
#
# Usage in other scripts:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib/common.sh"
#
# Language: common.sh auto-loads lib/lang.sh, so every script that sources
# this file gets trilingual EN/ID/ZH support (default: English). See lib/lang.sh.

# Do not execute directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This file is a library. Do not run it directly." >&2
  echo "Source it from another script: source \"\$(dirname \"\$0\")/lib/common.sh\"" >&2
  exit 1
fi

# Load language framework first (English default, persists in /etc/vpn/lang)
_COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lang.sh
source "$_COMMON_LIB_DIR/lang.sh"
lang_load

# ---------------------------------------------------------------- colors/log
if [[ -t 1 ]] && command -v tput &>/dev/null; then
  _C_RESET="$(tput sgr0 2>/dev/null || true)"
  _C_RED="$(tput setaf 1 2>/dev/null || true)"
  _C_GREEN="$(tput setaf 2 2>/dev/null || true)"
  _C_YELLOW="$(tput setaf 3 2>/dev/null || true)"
  _C_BLUE="$(tput setaf 4 2>/dev/null || true)"
  _C_BOLD="$(tput bold 2>/dev/null || true)"
else
  _C_RESET=""; _C_RED=""; _C_GREEN=""; _C_YELLOW=""; _C_BLUE=""; _C_BOLD=""
fi

log_info()    { echo -e "${_C_BLUE}[INFO]${_C_RESET}    $*"; }
log_success() { echo -e "${_C_GREEN}[OK]${_C_RESET}      $*"; }
log_warn()    { echo -e "${_C_YELLOW}[WARN]${_C_RESET}    $*"; }
log_error()   { echo -e "${_C_RED}[ERROR]${_C_RESET}   $*" >&2; }
log_step()    { echo -e "\n${_C_BOLD}${_C_GREEN}==>${_C_RESET}${_C_BOLD} $*${_C_RESET}"; }

die() { log_error "$*"; exit 1; }

# ------------------------------------------------------------ root & basics
need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "$(T "This script must be run as root. Try: sudo $0 $*" "Skrip ini harus dijalankan sebagai root. Coba: sudo $0 $*" "此脚本必须以 root 身份运行。请尝试：sudo $0 $*")"
  fi
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" &>/dev/null || die "$(T "Command '$cmd' not found. Run install.sh first." "Perintah '$cmd' tidak ditemukan. Jalankan install.sh dulu." "未找到命令 '$cmd'。请先运行 install.sh。")"
}

confirm() {
  local prompt="${1:-$(T "Continue? [y/N] " "Lanjutkan? [y/N] " "继续吗？[y/N] ")}"
  local ans
  if [[ "${AUTO_YES:-0}" == "1" ]]; then
    return 0
  fi
  read -rp "$prompt" ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

# ------------------------------------------------------------------ OS detect
# Export: OS_ID, OS_VERSION_ID, OS_MAJOR, OS_NAME, PKG_MGR, FIREWALL_TOOL, OS_FAMILY
detect_os() {
  OS_ID="unknown"
  OS_VERSION_ID="unknown"
  OS_MAJOR="0"
  OS_NAME="$(uname -s)"
  PKG_MGR="unknown"
  FIREWALL_TOOL="iptables"
  OS_FAMILY="unknown"

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    OS_ID="${ID,,}"
    OS_VERSION_ID="${VERSION_ID//\"/}"
    OS_NAME="${PRETTY_NAME:-$OS_ID}"
    OS_MAJOR="$(echo "$OS_VERSION_ID" | cut -d. -f1)"
  fi

  case "$OS_ID" in
    ubuntu|debian|linuxmint|pop|elementary|zorin|kali|raspbian|armbian)
      OS_FAMILY="debian"
      PKG_MGR="apt"
      FIREWALL_TOOL="ufw"
      ;;
    centos|rocky|almalinux|rhel|redhat|fedora|ol|amzn)
      OS_FAMILY="rhel"
      PKG_MGR="dnf"
      FIREWALL_TOOL="firewalld"
      command -v dnf &>/dev/null || PKG_MGR="yum"
      ;;
    arch|manjaro|endeavouros)
      OS_FAMILY="arch"
      PKG_MGR="pacman"
      FIREWALL_TOOL="iptables"
      ;;
    opensuse*|sles)
      OS_FAMILY="suse"
      PKG_MGR="zypper"
      FIREWALL_TOOL="firewalld"
      ;;
    alpine)
      OS_FAMILY="alpine"
      PKG_MGR="apk"
      FIREWALL_TOOL="iptables"
      ;;
  esac

  export OS_ID OS_VERSION_ID OS_MAJOR OS_NAME PKG_MGR FIREWALL_TOOL OS_FAMILY
}

print_os_info() {
  log_info "$(T "Detected OS : $OS_NAME (id=$OS_ID ver=$OS_VERSION_ID family=$OS_FAMILY)" "OS terdeteksi : $OS_NAME (id=$OS_ID ver=$OS_VERSION_ID family=$OS_FAMILY)" "检测到系统：$OS_NAME（id=$OS_ID 版本=$OS_VERSION_ID 系列=$OS_FAMILY）")"
  log_info "$(T "Package mgr : $PKG_MGR | Firewall tool: $FIREWALL_TOOL" "Package mgr   : $PKG_MGR | Firewall tool: $FIREWALL_TOOL" "软件包管理器：$PKG_MGR | 防火墙工具：$FIREWALL_TOOL")"
}

# Returns 0 when the OS is officially supported, 1 when untested (but known family)
is_supported_os() {
  case "$OS_ID" in
    ubuntu)
      case "$OS_VERSION_ID" in
        20.04|22.04|24.04|26.04|26.*|25.*) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    debian)
      case "$OS_MAJOR" in
        10|11|12|13) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    rocky|almalinux|centos|rhel)
      case "$OS_MAJOR" in
        8|9) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    fedora)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

check_os_supported() {
  detect_os
  print_os_info
  if is_supported_os; then
    log_success "$(T "Distro is officially supported." "Distro didukung resmi." "该发行版为官方支持。")"
  else
    log_warn "$(T "Distro $OS_ID $OS_VERSION_ID is not on the tested list." "Distro $OS_ID $OS_VERSION_ID belum masuk daftar teruji." "发行版 $OS_ID $OS_VERSION_ID 不在已测试列表中。")"
    log_warn "$(T "Family $OS_FAMILY will still be attempted. Continue at your own risk." "Keluarga $OS_FAMILY tetap dicoba. Lanjutkan dengan risiko sendiri." "仍将尝试 $OS_FAMILY 系列。请自行承担风险继续。")"
    if [[ "${FORCE_OS:-0}" != "1" && "${AUTO_YES:-0}" != "1" ]]; then
      confirm "$(T "Continue installation anyway? [y/N] " "Tetap lanjutkan instalasi? [y/N] " "仍要继续安装吗？[y/N] ")" || die "$(T "Installation cancelled by user." "Instalasi dibatalkan oleh pengguna." "安装已被用户取消。")"
    fi
  fi
}

check_tun() {
  if [[ ! -c /dev/net/tun ]]; then
    die "$(T "/dev/net/tun is not available. Enable TUN in your VPS panel (usually OpenVZ/LXC), then try again." "/dev/net/tun tidak tersedia. Aktifkan TUN di VPS panel (umumnya di OpenVZ/LXC) lalu coba lagi." "/dev/net/tun 不可用。请在 VPS 面板中启用 TUN（通常为 OpenVZ/LXC），然后重试。")"
  fi
}

check_virt() {
  if command -v systemd-detect-virt &>/dev/null; then
    local v
    v="$(systemd-detect-virt 2>/dev/null || true)"
    [[ -n "$v" && "$v" != "none" ]] && log_info "$(T "Virtualization detected: $v" "Virtualisasi terdeteksi: $v" "检测到虚拟化：$v")"
  fi
}

# ------------------------------------------------------------------ network
get_default_iface() {
  local iface=""
  # awk (portable) — grep -P is missing on some distros (Alpine, minimal RHEL, etc.)
  iface="$(ip -4 route ls 2>/dev/null | awk '/^default/ {for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')"
  if [[ -z "$iface" ]]; then
    iface="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')"
  fi
  echo "${iface:-eth0}"
}

get_public_ip() {
  local ip=""
  for url in "https://ifconfig.me" "https://api.ipify.org" "https://ipv4.icanhazip.com"; do
    ip="$(curl -fsS --max-time 8 "$url" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "$ip"
      return 0
    fi
  done
  # fallback: IP from route table (may be a private/NAT address)
  # Portable awk instead of grep -oP (unavailable on Alpine/minimal RHEL)
  ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}' | head -n1 || true)"
  echo "${ip:-127.0.0.1}"
}

is_port_in_use() {
  local port="$1" proto="${2:-udp}"
  if command -v ss &>/dev/null; then
    if [[ "$proto" == "udp" ]]; then
      ss -lnu 2>/dev/null | grep -q ":${port} "
    else
      ss -lnt 2>/dev/null | grep -q ":${port} "
    fi
  else
    return 1
  fi
}

gen_password() {
  local len="${1:-16}"
  if command -v openssl &>/dev/null; then
    openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$len"; echo
  else
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$len"; echo
  fi
}

validate_client_name() {
  local name="$1"
  [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || die "$(T "Invalid client name '$name'. Use letters/numbers/dash/underscore only." "Nama client tidak valid '$name'. Gunakan huruf/angka/dash/underscore saja." "客户端名称 '$name' 无效。仅可使用字母/数字/横线/下划线。")"
  [[ "${#name}" -le 32 ]] || die "$(T "Client name must be 32 characters or fewer." "Nama client maksimal 32 karakter." "客户端名称最多 32 个字符。")"
}

# ------------------------------------------------------- params file helper
# Params file format: KEY="value" per line, sourced by add/remove clients.
PARAMS_FILE_DEFAULT="/etc/wireguard/params"

save_params() {
  local file="${1:-$PARAMS_FILE_DEFAULT}"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<EOF
# Auto-generated by install.sh (wrwb Store) — do not edit manually unless you know the risks
SERVER_PUB_IP="$SERVER_PUB_IP"
SERVER_PORT="$SERVER_PORT"
SERVER_PUB_KEY="$SERVER_PUB_KEY"
SERVER_SUBNET="$SERVER_SUBNET"
SERVER_IP="$SERVER_IP"
SERVER_DNS="$SERVER_DNS"
SERVER_IFACE="$NET_IFACE"
WG_CONF="$WG_CONF"
CLIENT_DIR="$CLIENT_DIR"
EOF
  chmod 600 "$file"
  log_success "$(T "Server parameters saved to $file" "Parameter server disimpan di $file" "服务器参数已保存到 $file")"
}

load_params() {
  local file="${1:-$PARAMS_FILE_DEFAULT}"
  [[ -f "$file" ]] || die "$(T "Params file $file not found. Run ./install.sh first." "File params $file tidak ditemukan. Jalankan ./install.sh dulu." "未找到参数文件 $file。请先运行 ./install.sh。")"
  # shellcheck disable=SC1090
  source "$file"
  [[ -n "${SERVER_PUB_KEY:-}" ]] || die "$(T "Params are corrupt: SERVER_PUB_KEY is empty." "Params rusak: SERVER_PUB_KEY kosong." "参数已损坏：SERVER_PUB_KEY 为空。")"
  [[ -n "${WG_CONF:-}" ]] || WG_CONF="/etc/wireguard/wg0.conf"
}
