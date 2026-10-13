#!/bin/bash
#
# lib/common.sh — Fungsi bersama untuk semua skrip VPN
# Didukung: Ubuntu 20.04/22.04/24.04/26.04, Debian 10/11/12/13,
#           CentOS / Rocky / AlmaLinux 8/9, RHEL 8/9
#
# Cara pakai di skrip lain:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib/common.sh"

# Jangan dieksekusi langsung
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "File ini adalah library. Jangan dijalankan langsung." >&2
  echo "Source dari skrip lain: source \"\$(dirname \"\$0\")/lib/common.sh\"" >&2
  exit 1
fi

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

# ------------------------------------------------------------ root & dasar
need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Skrip ini harus dijalankan sebagai root. Coba: sudo $0 $*"
  fi
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" &>/dev/null || die "Perintah '$cmd' tidak ditemukan. Jalankan install.sh dulu."
}

confirm() {
  local prompt="${1:-Lanjutkan? [y/N]} "
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
  log_info "OS terdeteksi : $OS_NAME (id=$OS_ID ver=$OS_VERSION_ID family=$OS_FAMILY)"
  log_info "Package mgr   : $PKG_MGR | Firewall tool: $FIREWALL_TOOL"
}

# Kembalikan 0 jika OS didukung resmi, 1 jika belum teruji (tapi keluarga dikenal)
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
    log_success "Distro didukung resmi."
  else
    log_warn "Distro $OS_ID $OS_VERSION_ID belum masuk daftar teruji."
    log_warn "Keluarga $OS_FAMILY tetap dicoba. Lanjutkan dengan risiko sendiri."
    if [[ "${FORCE_OS:-0}" != "1" && "${AUTO_YES:-0}" != "1" ]]; then
      confirm "Tetap lanjutkan instalasi? [y/N] " || die "Instalasi dibatalkan oleh pengguna."
    fi
  fi
}

check_tun() {
  if [[ ! -c /dev/net/tun ]]; then
    die "/dev/net/tun tidak tersedia. Aktifkan TUN di VPS panel (umumnya di OpenVZ/LXC) lalu coba lagi."
  fi
}

check_virt() {
  if command -v systemd-detect-virt &>/dev/null; then
    local v
    v="$(systemd-detect-virt 2>/dev/null || true)"
    [[ -n "$v" && "$v" != "none" ]] && log_info "Virtualisasi terdeteksi: $v"
  fi
}

# ------------------------------------------------------------------ network
get_default_iface() {
  local iface=""
  # Pakai awk (portabel) — grep -P tidak tersedia di semua distro (Alpine, RHEL minimal, dsb.)
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
  # fallback: IP dari route (bisa IP privat/NAT)
  ip="$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP '(?<=src )(\S+)' | head -n1 || true)"
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
  [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || die "Nama client tidak valid '$name'. Gunakan huruf/angka/dash/underscore saja."
  [[ "${#name}" -le 32 ]] || die "Nama client maksimal 32 karakter."
}

# ------------------------------------------------------- params file helper
# Format file params: KEY="value" per baris, disource oleh add/remove client.
PARAMS_FILE_DEFAULT="/etc/wireguard/params"

save_params() {
  local file="${1:-$PARAMS_FILE_DEFAULT}"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<EOF
# Dibuat otomatis oleh install.sh — jangan edit manual kecuali paham risikonya
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
  log_success "Parameter server disimpan di $file"
}

load_params() {
  local file="${1:-$PARAMS_FILE_DEFAULT}"
  [[ -f "$file" ]] || die "File params $file tidak ditemukan. Jalankan ./install.sh dulu."
  # shellcheck disable=SC1090
  source "$file"
  [[ -n "${SERVER_PUB_KEY:-}" ]] || die "Params rusak: SERVER_PUB_KEY kosong."
  [[ -n "${WG_CONF:-}" ]] || WG_CONF="/etc/wireguard/wg0.conf"
}
