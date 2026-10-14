#!/bin/bash
#
# lib/system.sh — Package management, kernel sysctl & firewall (trilingual EN/ID/ZH)
# Branding: wrwb Store
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This file is a library. Do not run it directly." >&2
  exit 1
fi

# ----------------------------------------------------------- IP Forwarding
enable_ip_forwarding() {
  log_step "$(T "Enabling IP forwarding (IPv4 & IPv6)..." "Mengaktifkan IP Forwarding (IPv4 & IPv6)..." "正在启用 IP 转发（IPv4 和 IPv6）...")"

  local conf_file="/etc/sysctl.d/99-vpn-forward.conf"

  cat > "$conf_file" <<'EOF'
# Auto-enabled for VPN (wrwb Store)
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
# Optimasi throughput VPN (BBR-friendly, aman untuk semua kernel modern)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400
net.ipv4.tcp_rmem = 4096 87380 26214400
net.ipv4.tcp_wmem = 4096 65536 26214400
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
EOF

  # Terapkan langsung ke kernel yang berjalan
  sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1 || true

  # Terapkan konfigurasi sysctl agar persisten
  if sysctl --system >/dev/null 2>&1; then
    :
  elif [[ -f /etc/sysctl.conf ]]; then
    sysctl -p "$conf_file" >/dev/null 2>&1 || true
  fi

  local cur_v4 cur_v6
  cur_v4="$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo 0)"
  cur_v6="$(cat /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null || echo 0)"

  if [[ "$cur_v4" == "1" ]]; then
    log_success "$(T "IPv4 forwarding active (value: 1)" "IPv4 Forwarding aktif (nilai: 1)" "IPv4 转发已启用（值：1）")"
  else
    die "$(T "Failed to enable net.ipv4.ip_forward=1. Check kernel/virtualization permissions." "Gagal mengaktifkan net.ipv4.ip_forward=1. Periksa izin kernel/virtualisasi." "启用 net.ipv4.ip_forward=1 失败。请检查内核/虚拟化权限。")"
  fi

  if [[ "$cur_v6" == "1" ]]; then
    log_info "$(T "IPv6 forwarding active (value: 1)" "IPv6 Forwarding aktif (nilai: 1)" "IPv6 转发已启用（值：1）")"
  else
    log_warn "$(T "IPv6 forwarding is inactive (may be disabled by the VPS provider)." "IPv6 Forwarding tidak aktif (mungkin dinonaktifkan di level VPS provider)." "IPv6 转发未运行（可能被 VPS 服务商禁用）。")"
  fi
}

# ----------------------------------------------------------- Paket & Dependensi
install_wireguard_packages() {
  log_step "$(T "Updating repositories and installing WireGuard dependencies..." "Memperbarui repositori dan menginstal dependensi WireGuard..." "正在更新软件源并安装 WireGuard 依赖...")"

  detect_os

  case "$PKG_MGR" in
    apt)
      export DEBIAN_FRONTEND=noninteractive

      # Special handling for Debian 10 (Buster): needs backports for WireGuard
      if [[ "$OS_ID" == "debian" && "$OS_MAJOR" == "10" ]]; then
        log_info "$(T "Debian 10 detected: adding buster-backports for WireGuard..." "Debian 10 terdeteksi: menambahkan buster-backports untuk WireGuard..." "检测到 Debian 10：正在为 WireGuard 添加 buster-backports...")"
        if ! grep -q "buster-backports" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
          echo "deb http://deb.debian.org/debian buster-backports main" > /etc/apt/sources.list.d/buster-backports.list
        fi
      fi

      apt-get update -y || {
        log_warn "$(T "apt-get update returned a non-zero code, trying to continue..." "apt-get update mengembalikan non-zero code, mencoba melanjutkan..." "apt-get update 返回非零代码，尝试继续...")"
      }

      local pkgs=(
        wireguard
        wireguard-tools
        iptables
        qrencode
        curl
        iproute2
        ca-certificates
        openssl
        resolvconf
      )

      apt-get install -y "${pkgs[@]}" || {
        # Fallback without the wireguard meta-package when old kernels need dkms
        log_warn "$(T "Standard install failed, retrying with wireguard-dkms..." "Instalasi standard gagal, mencoba dengan wireguard-dkms..." "标准安装失败，正尝试使用 wireguard-dkms 重试...")"
        apt-get install -y wireguard-tools wireguard-dkms iptables qrencode curl iproute2
      }
      ;;

    dnf|yum)
      local mgr="$PKG_MGR"

      # On RHEL/CentOS/Rocky/Alma, EPEL is needed for qrencode & wireguard-tools (v8)
      if [[ "$OS_FAMILY" == "rhel" ]]; then
        log_info "$(T "Ensuring the EPEL repository is enabled..." "Memastikan EPEL repository aktif..." "正在确保 EPEL 软件源已启用...")"
        $mgr install -y epel-release || true
        # Di RHEL/Rocky 8+ aktifkan CRB / PowerTools jika perlu
        if command -v crb &>/dev/null; then
          crb enable || true
        elif command -v dnf &>/dev/null; then
          dnf config-manager --set-enabled powertools 2>/dev/null || \
          dnf config-manager --set-enabled crb 2>/dev/null || true
        fi
      fi

      $mgr update -y --exclude="kernel*" || true

      local pkgs=(
        wireguard-tools
        iptables
        iptables-services
        qrencode
        curl
        iproute
        ca-certificates
        openssl
      )

      $mgr install -y "${pkgs[@]}" || {
        # RHEL 8 butuh kmod-wireguard
        if [[ "$OS_MAJOR" == "8" ]]; then
          $mgr install -y kmod-wireguard wireguard-tools qrencode curl || true
        fi
      }
      ;;

    pacman)
      pacman -Sy --noconfirm wireguard-tools iptables qrencode curl iproute2 ca-certificates openssl
      ;;

    apk)
      apk add --no-cache wireguard-tools iptables ip6tables qrencode curl iproute2 openssl ca-certificates
      ;;

    zypper)
      zypper refresh
      zypper install -y wireguard-tools iptables qrencode curl iproute2 openssl ca-certificates
      ;;

    emerge)
      # Gentoo
      log_info "$(T "Gentoo detected: syncing portage..." "Gentoo terdeteksi: sync portage..." "检测到 Gentoo：正在同步 portage...")"
      emerge --sync || true
      emerge -q net-vpn/wireguard-tools net-firewall/iptables media-gfx/qrencode net-misc/curl sys-apps/iproute2 dev-libs/openssl
      ;;

    xbps-install)
      # Void Linux
      log_info "$(T "Void Linux detected: updating xbps..." "Void Linux terdeteksi: update xbps..." "检测到 Void Linux：正在更新 xbps...")"
      xbps-install -Syu || true
      xbps-install -y wireguard-tools iptables qrencode curl iproute2 openssl ca-certificates
      ;;

    nix-env)
      # NixOS
      log_warn "$(T "NixOS requires declarative configuration. Add wireguard-tools to systemPackages in configuration.nix" "NixOS butuh konfigurasi deklaratif. Tambahkan wireguard-tools ke systemPackages di configuration.nix" "NixOS 需要声明式配置。请将 wireguard-tools 添加到 configuration.nix 的 systemPackages")"
      nix-env -iA nixos.wireguard-tools nixos.iptables nixos.qrencode nixos.curl nixos.iproute2 nixos.openssl || true
      ;;

    *)
      die "$(T "Package manager '$PKG_MGR' is not supported for automatic install. Install wireguard-tools, iptables, qrencode manually." "Package manager '$PKG_MGR' tidak didukung untuk instalasi otomatis. Pasang wireguard-tools, iptables, qrencode secara manual." "软件包管理器 '$PKG_MGR' 不支持自动安装。请手动安装 wireguard-tools、iptables、qrencode。")"
      ;;
  esac

  # Verify critical commands are available
  local needed=(wg wg-quick iptables qrencode curl ip)
  for c in "${needed[@]}"; do
    if ! command -v "$c" &>/dev/null; then
      die "$(T "Required command '$c' is missing after package install." "Perintah wajib '$c' tidak ditemukan setelah instalasi paket." "安装软件包后仍缺少必需命令 '$c'。")"
    fi
  done

  # Load the wireguard kernel module when not loaded yet
  if ! lsmod | grep -q "^wireguard"; then
    modprobe wireguard 2>/dev/null || {
      log_warn "$(T "modprobe wireguard failed. WireGuard may be built into the kernel or use wireguard-go." "modprobe wireguard gagal. WireGuard mungkin dibangun built-in ke kernel atau menggunakan wireguard-go." "modprobe wireguard 失败。WireGuard 可能已内置于内核或使用 wireguard-go。")"
    }
  fi

  log_success "$(T "WireGuard dependencies installed." "Dependensi WireGuard berhasil diinstal." "WireGuard 依赖安装成功。")"
}

# ----------------------------------------------------------- Firewall (dynamic, v4.6)
# Auto-detect the active packet-filtering backend (UFW / firewalld / nftables
# / iptables) and only add rules where filtering is actually enforced.
# All helpers are idempotent: re-running never creates duplicate rules.

# Detect the best backend. Sets FW_BACKEND to: ufw | firewalld | iptables | nft | none
fw_detect_backend() {
  if [[ "${FW_DETECTED:-0}" == "1" && -n "${FW_BACKEND:-}" ]]; then
    return 0
  fi
  FW_BACKEND="none"
  FW_UFW_ACTIVE=0
  FW_FIREWALLD_ACTIVE=0

  if command -v ufw &>/dev/null; then
    if ufw status 2>/dev/null | grep -qi "status:[[:space:]]*active"; then
      FW_UFW_ACTIVE=1
      FW_BACKEND="ufw"
    fi
  fi

  if [[ "$FW_BACKEND" == "none" ]]; then
    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
      FW_FIREWALLD_ACTIVE=1
      FW_BACKEND="firewalld"
    fi
  fi

  if [[ "$FW_BACKEND" == "none" ]]; then
    if command -v iptables &>/dev/null; then
      FW_BACKEND="iptables"
    elif command -v nft &>/dev/null; then
      FW_BACKEND="nft"
    fi
  fi

  FW_DETECTED=1
  export FW_BACKEND FW_UFW_ACTIVE FW_FIREWALLD_ACTIVE FW_DETECTED
}

# Returns 0 when packet filtering is actually enforced on this host.
fw_is_filtering_active() {
  fw_detect_backend
  case "$FW_BACKEND" in
    ufw|firewalld)
      return 0
      ;;
    iptables)
      local first
      first="$(iptables -S INPUT 2>/dev/null | head -n1 || true)"
      case "$first" in
        "-P INPUT DROP"|"-P INPUT REJECT")
          return 0
          ;;
      esac
      if iptables -S INPUT 2>/dev/null | grep -Eq "^-[AI] INPUT "; then
        return 0
      fi
      return 1
      ;;
    nft)
      if nft list chain inet filter input 2>/dev/null | grep -Eq "dport|drop|reject"; then
        return 0
      fi
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

# Ensure an ACCEPT rule exists (idempotent). Uses iptables first
# (works on top of nftables via iptables-nft), then native nft.
_fw_ensure_accept_rule() {
  local port="${1:?port required}" proto="${2:-tcp}"
  if command -v iptables &>/dev/null; then
    iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || \
      iptables -I INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || \
      log_warn "$(T "Could not add iptables rule for port $port/$proto (continuing)." "Gagal menambah aturan iptables untuk port $port/$proto (lanjut)." "无法为端口 $port/$proto 添加 iptables 规则（继续）。")"
    if command -v ip6tables &>/dev/null; then
      ip6tables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || \
        ip6tables -I INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || true
    fi
  elif command -v nft &>/dev/null; then
    _fw_nft_ensure_accept "$port" "$proto"
  fi
}

_fw_nft_ensure_accept() {
  local port="${1:?port required}" proto="${2:-tcp}"
  # Only manage the standard inet filter input chain; never create tables.
  if ! nft list chain inet filter input >/dev/null 2>&1; then
    log_warn "$(T "nft chain 'inet filter input' not found — skipped nft rule for port $port/$proto." "Chain nft 'inet filter input' tidak ditemukan — aturan nft port $port/$proto dilewati." "未找到 nft 链 'inet filter input' — 已跳过端口 $port/$proto 的 nft 规则。")"
    return 0
  fi
  if nft list chain inet filter input 2>/dev/null | grep -Eq "${proto}[[:space:]]+dport[[:space:]]+${port}([^0-9]|$)"; then
    return 0
  fi
  nft add rule inet filter input "$proto" dport "$port" accept comment "vpn" 2>/dev/null || \
    log_warn "$(T "Could not add nft rule for port $port/$proto (continuing)." "Gagal menambah aturan nft untuk port $port/$proto (lanjut)." "无法为端口 $port/$proto 添加 nft 规则（继续）。")"
}

# Remove ACCEPT rules added by this installer (idempotent, removes duplicates).
_fw_remove_accept_rule() {
  local port="${1:?port required}" proto="${2:-tcp}"
  if command -v iptables &>/dev/null; then
    while iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null; do
      iptables -D INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || break
    done
    if command -v ip6tables &>/dev/null; then
      while ip6tables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null; do
        ip6tables -D INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || break
      done
    fi
  fi
  if command -v nft &>/dev/null; then
    _fw_nft_remove_accept "$port" "$proto"
  fi
}

_fw_nft_remove_accept() {
  local port="${1:?port required}" proto="${2:-tcp}"
  if ! nft list chain inet filter input >/dev/null 2>&1; then
    return 0
  fi
  local handles h
  handles="$(nft --handle --numeric list chain inet filter input 2>/dev/null | grep -E "${proto}[[:space:]]+dport[[:space:]]+${port}([^0-9]|$)" | grep -oE "handle [0-9]+" | awk '{print $2}' || true)"
  # shellcheck disable=SC2086
  for h in $handles; do
    nft delete rule inet filter input handle "$h" 2>/dev/null || true
  done
}

# Low-level worker (no banner logging — used by single & batch open).
_fw_allow_port() {
  local port="${1:?port required}" proto="${2:-tcp}" label="${3:-VPN}"
  fw_detect_backend
  case "$FW_BACKEND" in
    ufw)
      ufw allow "$port/$proto" comment "$label" >/dev/null 2>&1 || ufw allow "$port/$proto" >/dev/null 2>&1 || true
      # Ensure UFW DEFAULT_FORWARD_POLICY is ACCEPT
      if [[ -f /etc/default/ufw ]] && grep -q '^DEFAULT_FORWARD_POLICY="DROP"' /etc/default/ufw; then
        sed -i 's/^DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
      fi
      if [[ "${FW_BATCH:-0}" != "1" ]]; then
        ufw reload >/dev/null 2>&1 || true
      fi
      ;;
    firewalld)
      local zone
      zone="$(firewall-cmd --get-default-zone 2>/dev/null || echo "public")"
      firewall-cmd --zone="$zone" --add-port="$port/$proto" --permanent >/dev/null 2>&1 || true
      firewall-cmd --zone="$zone" --add-masquerade --permanent >/dev/null 2>&1 || true
      if [[ "${FW_BATCH:-0}" != "1" ]]; then
        firewall-cmd --reload >/dev/null 2>&1 || true
      fi
      ;;
    iptables|nft)
      if fw_is_filtering_active; then
        _fw_ensure_accept_rule "$port" "$proto"
      else
        log_info "$(T "No active packet filtering detected — port $port/$proto is already reachable, no rule added." "Tidak ada packet filtering aktif — port $port/$proto sudah bisa dijangkau, tidak ada aturan ditambahkan." "未检测到活动包过滤 — 端口 $port/$proto 已可访问，未添加规则。")"
      fi
      ;;
    *)
      log_warn "$(T "No firewall tool found (ufw/firewalld/iptables/nft) — skipped port $port/$proto." "Tidak ada firewall tool (ufw/firewalld/iptables/nft) — port $port/$proto dilewati." "未找到防火墙工具 (ufw/firewalld/iptables/nft) — 已跳过端口 $port/$proto。")"
      ;;
  esac
}

open_firewall_port() {
  local port="${1:?port required}" proto="${2:-udp}" label="${3:-VPN}"
  log_step "$(T "Configuring firewall for port $port/$proto..." "Mengonfigurasi firewall untuk port $port/$proto..." "正在为端口 $port/$proto 配置防火墙...")"
  _fw_allow_port "$port" "$proto" "$label"
  # The wg-quick NAT/Masquerade rules are handled automatically via PostUp/PostDown in wg0.conf
  log_success "$(T "Firewall rule for port $port/$proto is ready." "Aturan firewall port $port/$proto siap." "端口 $port/$proto 的防火墙规则已就绪。")"
}

# Open many ports with a single banner (v4.6). Usage:
#   open_firewall_ports "Label" "tcp" 80 443 10001 10002
open_firewall_ports() {
  local label="${1:-VPN}" proto="${2:-tcp}"
  if [[ $# -lt 3 ]]; then
    log_warn "$(T "open_firewall_ports needs a label, proto and at least one port." "open_firewall_ports butuh label, proto, dan minimal satu port." "open_firewall_ports 需要标签、协议和至少一个端口。")"
    return 0
  fi
  shift 2
  log_step "$(T "Configuring firewall for $label ports ($proto): $*..." "Mengonfigurasi firewall untuk port-port $label ($proto): $*..." "正在为 $label 防火墙端口 ($proto) 配置防火墙：$*...")"
  FW_BATCH=1
  local p seen=" "
  for p in "$@"; do
    case "$seen" in
      *" $p "*) continue ;;
    esac
    seen="$seen$p "
    _fw_allow_port "$p" "$proto" "$label"
  done
  FW_BATCH=0
  fw_detect_backend
  case "$FW_BACKEND" in
    ufw) ufw reload >/dev/null 2>&1 || true ;;
    firewalld) firewall-cmd --reload >/dev/null 2>&1 || true ;;
  esac
  log_success "$(T "All $label firewall ports ($proto) are ready." "Semua port firewall $label ($proto) siap." "$label 防火墙端口 ($proto) 已全部就绪。")"
}

close_firewall_port() {
  local port="${1:?port required}" proto="${2:-udp}"
  log_info "$(T "Removing firewall rule for port $port/$proto..." "Menghapus aturan firewall untuk port $port/$proto..." "正在删除端口 $port/$proto 的防火墙规则...")"

  if command -v ufw &>/dev/null; then
    ufw --force delete allow "$port/$proto" >/dev/null 2>&1 || true
  fi

  if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
    local zone
    zone="$(firewall-cmd --get-default-zone 2>/dev/null || echo "public")"
    firewall-cmd --zone="$zone" --remove-port="$port/$proto" --permanent >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
  fi

  _fw_remove_accept_rule "$port" "$proto"
}

# Close many ports with a single banner (v4.6). Usage:
#   close_firewall_ports "tcp" 80 443 10001 10002
close_firewall_ports() {
  local proto="${1:-tcp}"
  shift || true
  if [[ $# -lt 1 ]]; then
    log_warn "$(T "close_firewall_ports needs a proto and at least one port." "close_firewall_ports butuh proto dan minimal satu port." "close_firewall_ports 需要协议和至少一个端口。")"
    return 0
  fi
  local p seen=" "
  for p in "$@"; do
    case "$seen" in
      *" $p "*) continue ;;
    esac
    seen="$seen$p "
    close_firewall_port "$p" "$proto"
  done
}

# One-line summary of the firewall state (used by status.sh).
fw_status_summary() {
  fw_detect_backend
  echo "$(T "Firewall backend       : " "Backend Firewall       : " "防火墙后端            : ")$FW_BACKEND"
  if fw_is_filtering_active; then
    echo "$(T "Packet filtering      : " "Packet Filtering      : " "包过滤               : ")$(T "ACTIVE (rules enforced)" "AKTIF (aturan ditegakkan)" "运行中（规则生效）")"
  else
    echo "$(T "Packet filtering      : " "Packet Filtering      : " "包过滤               : ")$(T "INACTIVE (all ports reachable)" "NONAKTIF (semua port terbuka)" "未运行（所有端口可访问）")"
  fi
}
