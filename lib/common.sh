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

# ---------------------------------------------------------------- CPU Architecture
# Returns: amd64, arm64, arm32, or unknown
detect_cpu_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64)
      echo "amd64"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    armv7l|armhf|armv7*)
      echo "arm32"
      ;;
    i386|i686)
      echo "i386"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

check_cpu_arch() {
  local arch
  arch="$(detect_cpu_arch)"
  
  export CPU_ARCH="$arch"
  
  log_info "$(T "CPU Architecture: $arch ($(uname -m))" "Arsitektur CPU: $arch ($(uname -m))" "CPU 架构：$arch ($(uname -m))")"
  
  case "$arch" in
    amd64)
      log_success "$(T "x86_64/amd64 detected — fully supported" "x86_64/amd64 terdeteksi — didukung penuh" "检测到 x86_64/amd64 — 完全支持")"
      return 0
      ;;
    arm64)
      log_success "$(T "ARM64/aarch64 detected — fully supported (v4.5+)" "ARM64/aarch64 terdeteksi — didukung penuh (v4.5+)" "检测到 ARM64/aarch64 — 完全支持（v4.5+）")"
      return 0
      ;;
    arm32)
      log_warn "$(T "ARM32 detected — limited support (WireGuard OK, Xray may need manual binary)" "ARM32 terdeteksi — dukungan terbatas (WireGuard OK, Xray mungkin perlu binary manual)" "检测到 ARM32 — 支持有限（WireGuard 可用，Xray 可能需要手动二进制文件）")"
      return 1
      ;;
    i386)
      log_error "$(T "32-bit x86 is not supported. Use 64-bit OS (amd64 or arm64)." "x86 32-bit tidak didukung. Gunakan OS 64-bit (amd64 atau arm64)." "不支持 32 位 x86。请使用 64 位系统（amd64 或 arm64）。")"
      return 1
      ;;
    *)
      log_error "$(T "Unknown CPU architecture: $(uname -m). Supported: x86_64 (amd64), aarch64 (arm64)." "Arsitektur CPU tidak dikenal: $(uname -m). Didukung: x86_64 (amd64), aarch64 (arm64)." "未知 CPU 架构：$(uname -m)。支持：x86_64（amd64）、aarch64（arm64）。")"
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------- Virtualization Check
check_virtualization() {
  local virt_type="bare-metal"
  
  if command -v systemd-detect-virt &>/dev/null; then
    virt_type="$(systemd-detect-virt 2>/dev/null || echo "unknown")"
  elif [[ -f /proc/cpuinfo ]]; then
    if grep -q "hypervisor" /proc/cpuinfo 2>/dev/null; then
      virt_type="hypervisor"
    fi
  fi
  
  export VIRT_TYPE="$virt_type"
  
  case "$virt_type" in
    none|bare-metal)
      log_info "$(T "Virtualization: Bare metal (no virtualization detected)" "Virtualisasi: Bare metal (tidak ada virtualisasi)" "虚拟化：裸机（未检测到虚拟化）")"
      ;;
    kvm)
      log_info "$(T "Virtualization: KVM — fully supported" "Virtualisasi: KVM — didukung penuh" "虚拟化：KVM — 完全支持")"
      ;;
    qemu)
      log_info "$(T "Virtualization: QEMU — fully supported" "Virtualisasi: QEMU — didukung penuh" "虚拟化：QEMU — 完全支持")"
      ;;
    vmware)
      log_info "$(T "Virtualization: VMware — fully supported" "Virtualisasi: VMware — didukung penuh" "虚拟化：VMware — 完全支持")"
      ;;
    virtualbox)
      log_info "$(T "Virtualization: VirtualBox — supported" "Virtualisasi: VirtualBox — didukung" "虚拟化：VirtualBox — 支持")"
      ;;
    xen)
      log_info "$(T "Virtualization: Xen — supported" "Virtualisasi: Xen — didukung" "虚拟化：Xen — 支持")"
      ;;
    hyperv|microsoft)
      log_info "$(T "Virtualization: Hyper-V — supported" "Virtualisasi: Hyper-V — didukung" "虚拟化：Hyper-V — 支持")"
      ;;
    openvz)
      log_warn "$(T "Virtualization: OpenVZ — TUN/TAP may not be available (check with provider)" "Virtualisasi: OpenVZ — TUN/TAP mungkin tidak tersedia (cek dengan provider)" "虚拟化：OpenVZ — TUN/TAP 可能不可用（请与提供商确认）")"
      ;;
    lxc|lxc-libvirt)
      log_warn "$(T "Virtualization: LXC — TUN/TAP may need special configuration" "Virtualisasi: LXC — TUN/TAP mungkin perlu konfigurasi khusus" "虚拟化：LXC — TUN/TAP 可能需要特殊配置")"
      ;;
    docker|container*)
      log_error "$(T "Virtualization: Docker/Container — NOT SUPPORTED (requires privileged mode + TUN/TAP)" "Virtualisasi: Docker/Container — TIDAK DIDUKUNG (butuh privileged mode + TUN/TAP)" "虚拟化：Docker/容器 — 不支持（需要特权模式 + TUN/TAP）")"
      return 1
      ;;
    *)
      log_info "$(T "Virtualization: $virt_type (unknown type, may work)" "Virtualisasi: $virt_type (tipe tidak dikenal, mungkin bekerja)" "虚拟化：$virt_type（未知类型，可能有效）")"
      ;;
  esac
  
  return 0
}

# ---------------------------------------------------------------- TUN/TAP Check
check_tun_tap() {
  log_step "$(T "Checking TUN/TAP device availability..." "Memeriksa ketersediaan device TUN/TAP..." "正在检查 TUN/TAP 设备可用性...")"
  
  if [[ ! -c /dev/net/tun ]]; then
    log_error "$(T "/dev/net/tun is NOT available" "/dev/net/tun TIDAK tersedia" "/dev/net/tun 不可用")"
    log_error "$(T "WireGuard and OpenVPN require TUN/TAP device." "WireGuard dan OpenVPN membutuhkan device TUN/TAP." "WireGuard 和 OpenVPN 需要 TUN/TAP 设备。")"
    
    if [[ "$VIRT_TYPE" == "openvz" || "$VIRT_TYPE" == "lxc"* ]]; then
      log_error "$(T "OpenVZ/LXC detected: Enable TUN/TAP in your VPS control panel" "OpenVZ/LXC terdeteksi: Aktifkan TUN/TAP di panel kontrol VPS Anda" "检测到 OpenVZ/LXC：请在 VPS 控制面板中启用 TUN/TAP")"
      log_error "$(T "Or contact your VPS provider to enable TUN/TAP support." "Atau hubungi provider VPS Anda untuk mengaktifkan TUN/TAP." "或联系您的 VPS 提供商以启用 TUN/TAP 支持。")"
    else
      log_error "$(T "Try: sudo modprobe tun" "Coba: sudo modprobe tun" "请尝试：sudo modprobe tun")"
      log_error "$(T "Or check kernel config: CONFIG_TUN=m or CONFIG_TUN=y" "Atau cek konfigurasi kernel: CONFIG_TUN=m atau CONFIG_TUN=y" "或检查内核配置：CONFIG_TUN=m 或 CONFIG_TUN=y")"
    fi
    
    die "$(T "Cannot proceed without TUN/TAP. Fix the issue and try again." "Tidak bisa melanjutkan tanpa TUN/TAP. Perbaiki masalahnya lalu coba lagi." "没有 TUN/TAP 无法继续。请修复问题后重试。")"
  fi
  
  log_success "$(T "/dev/net/tun is available — WireGuard & OpenVPN can work" "/dev/net/tun tersedia — WireGuard & OpenVPN bisa berjalan" "/dev/net/tun 可用 — WireGuard 和 OpenVPN 可运行")"
  
  # Try to load tun module if not loaded
  if ! lsmod | grep -q "^tun"; then
    log_info "$(T "TUN module not loaded, attempting to load..." "Modul TUN belum dimuat, mencoba memuat..." "TUN 模块未加载，正在尝试加载...")"
    modprobe tun 2>/dev/null || log_warn "$(T "modprobe tun failed (may be built-in)" "modprobe tun gagal (mungkin built-in)" "modprobe tun 失败（可能内置）")"
  fi
  
  return 0
}

# ---------------------------------------------------------------- Comprehensive Environment Check
check_environment() {
  log_step "$(T "Performing comprehensive environment check..." "Melakukan pemeriksaan environment menyeluruh..." "正在执行全面的环境检查...")"
  
  # 1. Root access
  log_info "$(T "[1/5] Checking root access..." "[1/5] Memeriksa akses root..." "[1/5] 正在检查 root 访问权限...")"
  need_root
  log_success "$(T "Root access confirmed (UID: $EUID)" "Akses root terkonfirmasi (UID: $EUID)" "root 访问已确认（UID：$EUID）")"
  
  # 2. CPU architecture
  log_info "$(T "[2/5] Checking CPU architecture..." "[2/5] Memeriksa arsitektur CPU..." "[2/5] 正在检查 CPU 架构...")"
  if ! check_cpu_arch; then
    if [[ "${FORCE_ARCH:-0}" != "1" ]]; then
      die "$(T "Unsupported CPU architecture. Set FORCE_ARCH=1 to override (at your own risk)." "Arsitektur CPU tidak didukung. Set FORCE_ARCH=1 untuk override (risiko sendiri)." "不支持的 CPU 架构。设置 FORCE_ARCH=1 以覆盖（风险自负）。")"
    fi
    log_warn "$(T "FORCE_ARCH=1 detected — proceeding with unsupported architecture" "FORCE_ARCH=1 terdeteksi — melanjutkan dengan arsitektur yang tidak didukung" "检测到 FORCE_ARCH=1 — 继续使用不受支持的架构")"
  fi
  
  # 3. Virtualization type
  log_info "$(T "[3/5] Detecting virtualization type..." "[3/5] Mendeteksi tipe virtualisasi..." "[3/5] 正在检测虚拟化类型...")"
  check_virtualization || true  # Don't fail on unknown virt
  
  # 4. TUN/TAP device
  log_info "$(T "[4/5] Checking TUN/TAP device..." "[4/5] Memeriksa device TUN/TAP..." "[4/5] 正在检查 TUN/TAP 设备...")"
  check_tun_tap
  
  # 5. OS detection
  log_info "$(T "[5/5] Detecting operating system..." "[5/5] Mendeteksi sistem operasi..." "[5/5] 正在检测操作系统...")"
  detect_os
  print_os_info
  
  log_success "$(T "Environment check passed! ✓" "Pemeriksaan environment berhasil! ✓" "环境检查通过！✓")"
  echo ""
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

  # Enhanced distro detection with auto-adaptation (v4.4)
  case "$OS_ID" in
    # Debian family
    ubuntu|debian|linuxmint|pop|elementary|zorin|kali|raspbian|armbian|devuan|mx|deepin|parrot)
      OS_FAMILY="debian"
      PKG_MGR="apt"
      FIREWALL_TOOL="ufw"
      ;;
    # RHEL family
    centos|rocky|almalinux|rhel|redhat|fedora|ol|amzn|scientific|oracle|eurolinux|cloudlinux)
      OS_FAMILY="rhel"
      PKG_MGR="dnf"
      FIREWALL_TOOL="firewalld"
      # Auto-detect yum for older systems
      if ! command -v dnf &>/dev/null && command -v yum &>/dev/null; then
        PKG_MGR="yum"
      fi
      # Fedora 40+ check
      if [[ "$OS_ID" == "fedora" && "$OS_MAJOR" -ge 40 ]]; then
        log_info "$(T "Fedora $OS_MAJOR detected with DNF5" "Fedora $OS_MAJOR terdeteksi dengan DNF5" "检测到 Fedora $OS_MAJOR 使用 DNF5")"
      fi
      ;;
    # Arch family
    arch|manjaro|endeavouros|garuda|artix|cachyos)
      OS_FAMILY="arch"
      PKG_MGR="pacman"
      FIREWALL_TOOL="iptables"
      ;;
    # SUSE family
    opensuse*|sles|sled|opensuse-leap|opensuse-tumbleweed)
      OS_FAMILY="suse"
      PKG_MGR="zypper"
      FIREWALL_TOOL="firewalld"
      ;;
    # Alpine
    alpine)
      OS_FAMILY="alpine"
      PKG_MGR="apk"
      FIREWALL_TOOL="iptables"
      ;;
    # Gentoo
    gentoo)
      OS_FAMILY="gentoo"
      PKG_MGR="emerge"
      FIREWALL_TOOL="iptables"
      ;;
    # Void Linux
    void)
      OS_FAMILY="void"
      PKG_MGR="xbps-install"
      FIREWALL_TOOL="iptables"
      ;;
    # NixOS
    nixos)
      OS_FAMILY="nixos"
      PKG_MGR="nix-env"
      FIREWALL_TOOL="iptables"
      log_warn "$(T "NixOS detected: manual configuration may be needed." "NixOS terdeteksi: mungkin perlu konfigurasi manual." "检测到 NixOS：可能需要手动配置。")"
      ;;
    # Fallback: try to detect by available commands
    *)
      log_warn "$(T "OS ID '$OS_ID' not recognized, attempting auto-detection..." "OS ID '$OS_ID' tidak dikenali, mencoba auto-detect..." "OS ID '$OS_ID' 未识别，尝试自动检测...")"
      if command -v apt-get &>/dev/null; then
        OS_FAMILY="debian"
        PKG_MGR="apt"
        FIREWALL_TOOL="ufw"
        log_info "$(T "Auto-detected: Debian-based (apt)" "Auto-detect: Debian-based (apt)" "自动检测：基于 Debian（apt）")"
      elif command -v dnf &>/dev/null; then
        OS_FAMILY="rhel"
        PKG_MGR="dnf"
        FIREWALL_TOOL="firewalld"
        log_info "$(T "Auto-detected: RHEL-based (dnf)" "Auto-detect: RHEL-based (dnf)" "自动检测：基于 RHEL（dnf）")"
      elif command -v yum &>/dev/null; then
        OS_FAMILY="rhel"
        PKG_MGR="yum"
        FIREWALL_TOOL="firewalld"
        log_info "$(T "Auto-detected: RHEL-based (yum)" "Auto-detect: RHEL-based (yum)" "自动检测：基于 RHEL（yum）")"
      elif command -v pacman &>/dev/null; then
        OS_FAMILY="arch"
        PKG_MGR="pacman"
        FIREWALL_TOOL="iptables"
        log_info "$(T "Auto-detected: Arch-based (pacman)" "Auto-detect: Arch-based (pacman)" "自动检测：基于 Arch（pacman）")"
      elif command -v zypper &>/dev/null; then
        OS_FAMILY="suse"
        PKG_MGR="zypper"
        FIREWALL_TOOL="firewalld"
        log_info "$(T "Auto-detected: SUSE-based (zypper)" "Auto-detect: SUSE-based (zypper)" "自动检测：基于 SUSE（zypper）")"
      elif command -v apk &>/dev/null; then
        OS_FAMILY="alpine"
        PKG_MGR="apk"
        FIREWALL_TOOL="iptables"
        log_info "$(T "Auto-detected: Alpine (apk)" "Auto-detect: Alpine (apk)" "自动检测：Alpine（apk）")"
      else
        OS_FAMILY="unknown"
        PKG_MGR="unknown"
        log_error "$(T "Could not detect package manager. Supported: apt, dnf, yum, pacman, zypper, apk" "Tidak bisa mendeteksi package manager. Didukung: apt, dnf, yum, pacman, zypper, apk" "无法检测软件包管理器。支持：apt、dnf、yum、pacman、zypper、apk")"
      fi
      ;;
  esac

  export OS_ID OS_VERSION_ID OS_MAJOR OS_NAME PKG_MGR FIREWALL_TOOL OS_FAMILY
}

print_os_info() {
  log_info "$(T "Detected OS : $OS_NAME (id=$OS_ID ver=$OS_VERSION_ID family=$OS_FAMILY)" "OS terdeteksi : $OS_NAME (id=$OS_ID ver=$OS_VERSION_ID family=$OS_FAMILY)" "检测到系统：$OS_NAME（id=$OS_ID 版本=$OS_VERSION_ID 系列=$OS_FAMILY）")"
  log_info "$(T "Package mgr : $PKG_MGR | Firewall tool: $FIREWALL_TOOL" "Package mgr   : $PKG_MGR | Firewall tool: $FIREWALL_TOOL" "软件包管理器：$PKG_MGR | 防火墙工具：$FIREWALL_TOOL")"
  
  # Show kernel version for compatibility info
  local kernel_ver
  kernel_ver="$(uname -r 2>/dev/null || echo "unknown")"
  log_info "$(T "Kernel ver  : $kernel_ver" "Versi kernel  : $kernel_ver" "内核版本：$kernel_ver")"
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
        10|11|12|13|14) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    rocky|almalinux|centos|rhel)
      case "$OS_MAJOR" in
        8|9|10) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    fedora)
      case "$OS_MAJOR" in
        3[8-9]|4[0-9]|5[0-9]) return 0 ;;  # Fedora 38-59
        *) return 1 ;;
      esac
      ;;
    arch|manjaro|endeavouros|garuda)
      # Arch is rolling, always attempt
      return 0
      ;;
    alpine)
      case "$OS_MAJOR" in
        3) return 0 ;;  # Alpine 3.x
        *) return 1 ;;
      esac
      ;;
    linuxmint|pop|elementary|zorin|kali|raspbian|armbian)
      # Debian-derived, generally compatible
      return 0
      ;;
    opensuse-leap|opensuse-tumbleweed|sles)
      # SUSE family
      return 0
      ;;
    *)
      # Unknown distro, but if we detected a family, give it a chance
      if [[ "$OS_FAMILY" != "unknown" && "$PKG_MGR" != "unknown" ]]; then
        log_warn "$(T "Distro '$OS_ID' is untested but family '$OS_FAMILY' is recognized." "Distro '$OS_ID' belum diuji tapi keluarga '$OS_FAMILY' dikenali." "发行版 '$OS_ID' 未测试，但识别到系列 '$OS_FAMILY'。")"
        return 1
      fi
      return 1
      ;;
  esac
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
  # v4.8: robust listener check — ss (iproute2) > netstat > /proc fallback.
  # Matches ":port " at line end OR ":port" followed by whitespace (ss/netstat
  # column layout differs per distro: "0.0.0.0:port", "[::]:port").
  local pat=":${port}([[:space:]]|$)"
  if command -v ss &>/dev/null; then
    if [[ "$proto" == "udp" ]]; then
      ss -lnu 2>/dev/null | grep -Eq "$pat" && return 0 || return 1
    else
      ss -lnt 2>/dev/null | grep -Eq "$pat" && return 0 || return 1
    fi
  fi
  if command -v netstat &>/dev/null; then
    if [[ "$proto" == "udp" ]]; then
      netstat -lnu 2>/dev/null | grep -Eq "$pat" && return 0 || return 1
    else
      netstat -lnt 2>/dev/null | grep -Eq "$pat" && return 0 || return 1
    fi
  fi
  # Last resort: /proc/net/{tcp,tcp6,udp,udp6} (hex port, always available on Linux)
  local hexpat
  hexpat="$(printf ":%04X" "$port" 2>/dev/null || echo "")"
  if [[ -n "$hexpat" ]]; then
    local f
    for f in /proc/net/tcp /proc/net/tcp6; do
      [[ "$proto" == "tcp" && -r "$f" ]] || continue
      grep -qi " ${hexpat} " "$f" 2>/dev/null && return 0
    done
    for f in /proc/net/udp /proc/net/udp6; do
      [[ "$proto" == "udp" && -r "$f" ]] || continue
      grep -qi " ${hexpat} " "$f" 2>/dev/null && return 0
    done
  fi
  return 1
}

# v4.8: name the process(es) listening on a port (best effort).
# Prints e.g. "nginx(1234)" or "?" when the owner cannot be determined.
port_owner() {
  local port="$1" proto="${2:-tcp}"
  local owners=""
  if command -v ss &>/dev/null; then
    local flag="-lnt"
    [[ "$proto" == "udp" ]] && flag="-lnu"
    owners="$(ss $flag -p 2>/dev/null | grep -E ":${port}([[:space:]]|$)" | grep -oE '"[^"]+"' | tr "\n" " " || true)"
  fi
  if [[ -z "$owners" ]] && command -v lsof &>/dev/null; then
    local lp
    lp="$(lsof -i"${proto^^}":"$port" -s"${proto^^}":LISTEN -t 2>/dev/null | head -n3 | tr "\n" "," || true)"
    [[ -n "$lp" ]] && owners="pid($lp)"
  fi
  if [[ -z "$owners" ]] && command -v netstat &>/dev/null; then
    owners="$(netstat -lntp 2>/dev/null | grep -E ":${port}([[:space:]]|$)" | awk '{print $NF}' | head -n1 || true)"
  fi
  echo "${owners:-?}"
}

# v4.8: check a TCP/UDP port before binding; warn + ask unless --yes/soft.
# Usage: check_port_free <port> <proto> <label> [--soft]
#   --soft  => only warn + return 1 (caller decides; never prompts, never dies)
# Returns 0 when free, 1 when in use.
check_port_free() {
  local port="$1" proto="${2:-tcp}" label="${3:-service}" mode="${4:-}"
  if is_port_in_use "$port" "$proto"; then
    local owner
    owner="$(port_owner "$port" "$proto")"
    log_warn "$(T "Port $port/$proto for $label is already in use (owner: $owner)." "Port $port/$proto untuk $label sudah dipakai (pemilik: $owner)." "供 $label 使用的端口 $port/$proto 已被占用（占用者：$owner）。")"
    log_warn "$(T "Common culprits: nginx/apache2/httpd/caddy or a previous install. Hint: ss -lntp | grep ':$port '" "Penyebab umum: nginx/apache2/httpd/caddy atau instalasi sebelumnya. Petunjuk: ss -lntp | grep ':$port '" "常见占用者：nginx/apache2/httpd/caddy 或旧安装。提示：ss -lntp | grep ':$port '")"
    if [[ "$mode" == "--soft" ]]; then
      return 1
    fi
    if [[ "${CLI_YES:-0}" -eq 0 && "${AUTO_YES:-0}" -eq 0 ]]; then
      confirm "$(T "Continue with port $port/$proto anyway? [y/N] " "Tetap lanjutkan dengan port $port/$proto? [y/N] " "仍要继续使用端口 $port/$proto 吗？[y/N] ")" || \
        die "$(T "Aborted: port $port/$proto is occupied. Free it or pick another port." "Dibatalkan: port $port/$proto ditempati. Bebaskan atau pilih port lain." "已中止：端口 $port/$proto 被占用。请释放或换用其他端口。")"
      return 0
    fi
    log_warn "$(T "Continuing anyway (--yes mode)." "Tetap lanjut (--yes mode)." "仍继续（--yes 模式）。")"
    return 1
  fi
  return 0
}

# v4.8: register a temp file/dir for auto-cleanup via trap.
# Usage: track_temp <path>  — paths are removed on EXIT/INT/TERM.
VPN_TMP_TRACKED=""
track_temp() {
  VPN_TMP_TRACKED="$VPN_TMP_TRACKED $1"
}

# v4.8: install EXIT/INT/TERM trap that removes all tracked temp files.
# Safe to call multiple times (only the first call installs the trap).
VPN_TRAP_INSTALLED="${VPN_TRAP_INSTALLED:-0}"
install_cleanup_trap() {
  if [[ "${VPN_TRAP_INSTALLED:-0}" == "1" ]]; then
    return 0
  fi
  VPN_TRAP_INSTALLED=1
  trap vpn_cleanup_tracked EXIT INT TERM
}

vpn_cleanup_tracked() {
  local p
  # shellcheck disable=SC2086
  for p in $VPN_TMP_TRACKED; do
    [[ -n "$p" && -e "$p" ]] || continue
    rm -rf "$p" 2>/dev/null || true
  done
  VPN_TMP_TRACKED=""
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
