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

# ----------------------------------------------------------- Firewall
open_firewall_port() {
  local port="$1" proto="${2:-udp}"
  log_step "$(T "Configuring firewall for port $port/$proto..." "Mengonfigurasi firewall untuk port $port/$proto..." "正在为端口 $port/$proto 配置防火墙...")"

  # 1. Check UFW (Ubuntu/Debian)
  if command -v ufw &>/dev/null; then
    local ufw_status
    ufw_status="$(ufw status 2>/dev/null | grep -i "Status:" | awk '{print $2}' || echo "inactive")"
    if [[ "$ufw_status" == "active" ]]; then
      log_info "$(T "UFW is active: opening port $port/$proto..." "UFW aktif: membuka port $port/$proto..." "UFW 运行中：正在开放端口 $port/$proto...")"
      ufw allow "$port/$proto" comment "VPN WireGuard" >/dev/null 2>&1 || ufw allow "$port/$proto"
      # Ensure UFW DEFAULT_FORWARD_POLICY is ACCEPT
      if [[ -f /etc/default/ufw ]]; then
        if grep -q '^DEFAULT_FORWARD_POLICY="DROP"' /etc/default/ufw; then
          log_info "$(T "Changing UFW DEFAULT_FORWARD_POLICY from DROP to ACCEPT..." "Mengubah DEFAULT_FORWARD_POLICY UFW dari DROP ke ACCEPT..." "正在将 UFW DEFAULT_FORWARD_POLICY 从 DROP 改为 ACCEPT...")"
          sed -i 's/^DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
        fi
      fi
      ufw reload >/dev/null 2>&1 || true
      log_success "$(T "Port $port/$proto opened in UFW." "Port $port/$proto dibuka di UFW." "端口 $port/$proto 已在 UFW 中开放。")"
    else
      log_info "$(T "UFW is installed but inactive. Adding a preparatory rule..." "UFW terpasang tetapi nonaktif. Menambahkan rule persiapan..." "UFW 已安装但未运行。正在添加预备规则...")"
      ufw allow "$port/$proto" comment "VPN WireGuard" >/dev/null 2>&1 || true
    fi
  fi

  # 2. Check Firewalld (CentOS/RHEL/Rocky/Alma/Fedora/SUSE)
  if command -v firewall-cmd &>/dev/null; then
    if systemctl is-active --quiet firewalld 2>/dev/null; then
      log_info "$(T "firewalld is active: adding port $port/$proto and masquerade..." "firewalld aktif: menambahkan port $port/$proto dan masquerade..." "firewalld 运行中：正在添加端口 $port/$proto 和伪装规则...")"
      firewall-cmd --zone=public --add-port="$port/$proto" --permanent >/dev/null 2>&1 || true
      firewall-cmd --zone=public --add-masquerade --permanent >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null 2>&1 || true
      log_success "$(T "Port $port/$proto and masquerade opened in firewalld." "Port $port/$proto dan masquerade dibuka di firewalld." "端口 $port/$proto 和伪装规则已在 firewalld 中开放。")"
    fi
  fi

  # 3. iptables fallback (when neither UFW nor firewalld is used)
  # The wg-quick NAT/Masquerade rules are handled automatically via PostUp/PostDown in wg0.conf
  log_success "$(T "Firewall rule for port $port/$proto is ready." "Aturan firewall port $port/$proto siap." "端口 $port/$proto 的防火墙规则已就绪。")"
}

close_firewall_port() {
  local port="$1" proto="${2:-udp}"
  log_info "$(T "Removing firewall rule for port $port/$proto..." "Menghapus aturan firewall untuk port $port/$proto..." "正在删除端口 $port/$proto 的防火墙规则...")"

  if command -v ufw &>/dev/null; then
    ufw delete allow "$port/$proto" >/dev/null 2>&1 || true
  fi

  if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
    firewall-cmd --zone=public --remove-port="$port/$proto" --permanent >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
  fi
}
