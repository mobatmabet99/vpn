#!/bin/bash
#
# lib/system.sh — Manajemen paket, kernel sysctl, dan firewall
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "File ini adalah library. Jangan dijalankan langsung." >&2
  exit 1
fi

# ----------------------------------------------------------- IP Forwarding
enable_ip_forwarding() {
  log_step "Mengaktifkan IP Forwarding (IPv4 & IPv6)..."

  local conf_file="/etc/sysctl.d/99-vpn-forward.conf"

  cat > "$conf_file" <<'EOF'
# Diaktifkan otomatis untuk VPN
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
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
    log_success "IPv4 Forwarding aktif (nilai: 1)"
  else
    die "Gagal mengaktifkan net.ipv4.ip_forward=1. Periksa izin kernel/virtualisasi."
  fi

  if [[ "$cur_v6" == "1" ]]; then
    log_info "IPv6 Forwarding aktif (nilai: 1)"
  else
    log_warn "IPv6 Forwarding tidak aktif (mungkin dinonaktifkan di level VPS provider)."
  fi
}

# ----------------------------------------------------------- Paket & Dependensi
install_wireguard_packages() {
  log_step "Memperbarui repositori dan menginstal dependensi WireGuard..."

  detect_os

  case "$PKG_MGR" in
    apt)
      export DEBIAN_FRONTEND=noninteractive

      # Penanganan khusus Debian 10 (Buster): butuh backports untuk wireguard
      if [[ "$OS_ID" == "debian" && "$OS_MAJOR" == "10" ]]; then
        log_info "Debian 10 terdeteksi: menambahkan buster-backports untuk WireGuard..."
        if ! grep -q "buster-backports" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
          echo "deb http://deb.debian.org/debian buster-backports main" > /etc/apt/sources.list.d/buster-backports.list
        fi
      fi

      apt-get update -y || {
        log_warn "apt-get update mengembalikan non-zero code, mencoba melanjutkan..."
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

      # iptables-persistent jika tersedia
      apt-get install -y "${pkgs[@]}" || {
        # Fallback tanpa wireguard meta-package jika di kernel lama butuh dkms
        log_warn "Instalasi standard gagal, mencoba dengan wireguard-dkms..."
        apt-get install -y wireguard-tools wireguard-dkms iptables qrencode curl iproute2
      }
      ;;

    dnf|yum)
      local mgr="$PKG_MGR"

      # Di RHEL/CentOS/Rocky/Alma butuh EPEL untuk qrencode & wireguard-tools (versi 8)
      if [[ "$OS_FAMILY" == "rhel" ]]; then
        log_info "Memastikan EPEL repository aktif..."
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

    *)
      die "Package manager '$PKG_MGR' tidak didukung untuk instalasi otomatis. Pasang wireguard-tools, iptables, qrencode secara manual."
      ;;
  esac

  # Cek ketersediaan perintah penting
  local needed=(wg wg-quick iptables qrencode curl ip)
  for c in "${needed[@]}"; do
    if ! command -v "$c" &>/dev/null; then
      die "Perintah wajib '$c' tidak ditemukan setelah instalasi paket."
    fi
  done

  # Muat modul kernel wireguard jika belum termuat
  if ! lsmod | grep -q "^wireguard"; then
    modprobe wireguard 2>/dev/null || {
      log_warn "modprobe wireguard gagal. WireGuard mungkin dibangun built-in ke kernel atau menggunakan wireguard-go."
    }
  fi

  log_success "Dependensi WireGuard berhasil diinstal."
}

# ----------------------------------------------------------- Firewall
open_firewall_port() {
  local port="$1" proto="${2:-udp}"
  log_step "Mengonfigurasi firewall untuk port $port/$proto..."

  # 1. Cek UFW (Ubuntu/Debian)
  if command -v ufw &>/dev/null; then
    local ufw_status
    ufw_status="$(ufw status 2>/dev/null | grep -i "Status:" | awk '{print $2}' || echo "inactive")"
    if [[ "$ufw_status" == "active" ]]; then
      log_info "UFW aktif: membuka port $port/$proto..."
      ufw allow "$port/$proto" comment "VPN WireGuard" >/dev/null 2>&1 || ufw allow "$port/$proto"
      # Pastikan DEFAULT_FORWARD_POLICY di UFW diset ke ACCEPT
      if [[ -f /etc/default/ufw ]]; then
        if grep -q '^DEFAULT_FORWARD_POLICY="DROP"' /etc/default/ufw; then
          log_info "Mengubah DEFAULT_FORWARD_POLICY UFW dari DROP ke ACCEPT..."
          sed -i 's/^DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
        fi
      fi
      ufw reload >/dev/null 2>&1 || true
      log_success "Port $port/$proto dibuka di UFW."
    else
      log_info "UFW terpasang tetapi nonaktif. Menambahkan rule persiapan..."
      ufw allow "$port/$proto" comment "VPN WireGuard" >/dev/null 2>&1 || true
    fi
  fi

  # 2. Cek Firewalld (CentOS/RHEL/Rocky/Alma/Fedora/SUSE)
  if command -v firewall-cmd &>/dev/null; then
    if systemctl is-active --quiet firewalld 2>/dev/null; then
      log_info "firewalld aktif: menambahkan port $port/$proto dan masquerade..."
      firewall-cmd --zone=public --add-port="$port/$proto" --permanent >/dev/null 2>&1 || true
      firewall-cmd --zone=public --add-masquerade --permanent >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null 2>&1 || true
      log_success "Port $port/$proto dan masquerade dibuka di firewalld."
    fi
  fi

  # 3. iptables cadangan (jika tidak pakai UFW / firewalld)
  # Rule NAT/Masquerade spesifik wg-quick sudah ditangani otomatis via PostUp/PostDown di wg0.conf
  log_success "Aturan firewall port $port/$proto siap."
}

close_firewall_port() {
  local port="$1" proto="${2:-udp}"
  log_info "Menghapus aturan firewall untuk port $port/$proto..."

  if command -v ufw &>/dev/null; then
    ufw delete allow "$port/$proto" >/dev/null 2>&1 || true
  fi

  if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
    firewall-cmd --zone=public --remove-port="$port/$proto" --permanent >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
  fi
}
