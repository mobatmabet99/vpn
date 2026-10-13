#!/bin/bash
# ==============================================================================
#  backup.sh — VPN Configuration Backup Script (wrwb Store)
#  
#  Features:
#    - Automatic daily backups (via cron)
#    - Manual on-demand backups
#    - Backs up all VPN configs (WireGuard, SSH, Xray, OpenVPN, Shadowsocks)
#    - Retention policy (keeps last 7 backups)
#    - Compression (tar.gz)
#    - Integration with Telegram bot & Web dashboard
#  
#  Usage:
#    sudo ./backup.sh [auto|manual]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

need_root

# Configuration
BACKUP_DIR="/var/backups/vpn"
RETENTION_DAYS=7
BACKUP_TYPE="${1:-manual}"

log_step "$(T "VPN Configuration Backup" "Backup Konfigurasi VPN" "VPN 配置备份") - $(date)"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Generate backup filename with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="vpn_backup_${BACKUP_TYPE}_${TIMESTAMP}"
TEMP_DIR="/tmp/${BACKUP_NAME}"
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"

log_info "$(T "Creating backup: $BACKUP_NAME" "Membuat backup: $BACKUP_NAME" "正在创建备份: $BACKUP_NAME")"

# Create temporary directory
mkdir -p "$TEMP_DIR"

# Backup WireGuard configs
if [[ -d /etc/wireguard ]]; then
  log_info "$(T "Backing up WireGuard..." "Backup WireGuard..." "备份 WireGuard...")"
  mkdir -p "$TEMP_DIR/wireguard"
  cp -r /etc/wireguard/* "$TEMP_DIR/wireguard/" 2>/dev/null || true
fi

# Backup SSH VPN configs
if [[ -d /etc/ssh-vpn ]]; then
  log_info "$(T "Backing up SSH VPN..." "Backup SSH VPN..." "备份 SSH VPN...")"
  mkdir -p "$TEMP_DIR/ssh-vpn"
  cp -r /etc/ssh-vpn/* "$TEMP_DIR/ssh-vpn/" 2>/dev/null || true
fi

# Backup Xray configs
if [[ -d /etc/xray ]]; then
  log_info "$(T "Backing up Xray..." "Backup Xray..." "备份 Xray...")"
  mkdir -p "$TEMP_DIR/xray"
  cp -r /etc/xray/* "$TEMP_DIR/xray/" 2>/dev/null || true
fi

# Backup OpenVPN configs
if [[ -d /etc/openvpn ]]; then
  log_info "$(T "Backing up OpenVPN..." "Backup OpenVPN..." "备份 OpenVPN...")"
  mkdir -p "$TEMP_DIR/openvpn"
  cp -r /etc/openvpn/* "$TEMP_DIR/openvpn/" 2>/dev/null || true
fi

# Backup Shadowsocks configs
if [[ -d /etc/shadowsocks ]]; then
  log_info "$(T "Backing up Shadowsocks..." "Backup Shadowsocks..." "备份 Shadowsocks...")"
  mkdir -p "$TEMP_DIR/shadowsocks"
  cp -r /etc/shadowsocks/* "$TEMP_DIR/shadowsocks/" 2>/dev/null || true
fi

# Backup VPN limits database
if [[ -d /var/lib/vpn-limits ]]; then
  log_info "$(T "Backing up limits database..." "Backup database limit..." "备份限制数据库...")"
  mkdir -p "$TEMP_DIR/vpn-limits"
  cp -r /var/lib/vpn-limits/* "$TEMP_DIR/vpn-limits/" 2>/dev/null || true
fi

# Backup VPN language setting
if [[ -f /etc/vpn/lang ]]; then
  mkdir -p "$TEMP_DIR/vpn"
  cp /etc/vpn/lang "$TEMP_DIR/vpn/" 2>/dev/null || true
fi

# Backup Telegram bot config
if [[ -f /etc/vpn/telegram-bot.json ]]; then
  cp /etc/vpn/telegram-bot.json "$TEMP_DIR/vpn/" 2>/dev/null || true
fi

# Backup Web dashboard config
if [[ -f /etc/vpn/web-config.json ]]; then
  cp /etc/vpn/web-config.json "$TEMP_DIR/vpn/" 2>/dev/null || true
fi

# Create backup info file
cat > "$TEMP_DIR/backup_info.txt" <<EOF
VPN Backup Information
======================
Backup Type: $BACKUP_TYPE
Date: $(date)
Hostname: $(hostname)
OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "Unknown")
Kernel: $(uname -r)

Contents:
---------
$(find "$TEMP_DIR" -type f | wc -l) files backed up
$(du -sh "$TEMP_DIR" | cut -f1) total size

Directories:
$(ls -1 "$TEMP_DIR")

Created by: wrwb Store VPN Auto-Installer v3
EOF

# Compress backup
log_info "$(T "Compressing backup..." "Mengkompresi backup..." "压缩备份...")"
tar -czf "$BACKUP_FILE" -C /tmp "$BACKUP_NAME" 2>/dev/null

# Remove temporary directory
rm -rf "$TEMP_DIR"

# Set proper permissions
chmod 600 "$BACKUP_FILE"

BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
log_success "$(T "Backup completed: $BACKUP_FILE ($BACKUP_SIZE)" "Backup selesai: $BACKUP_FILE ($BACKUP_SIZE)" "备份完成: $BACKUP_FILE ($BACKUP_SIZE)")"

# Clean old backups (keep last 7)
log_info "$(T "Cleaning old backups (keeping last $RETENTION_DAYS)..." "Membersihkan backup lama (simpan $RETENTION_DAYS terakhir)..." "清理旧备份（保留最近 $RETENTION_DAYS 个）...")"
find "$BACKUP_DIR" -name "vpn_backup_*.tar.gz" -type f -mtime +$RETENTION_DAYS -delete 2>/dev/null || true

# List all backups
echo ""
echo "$(T "Available backups:" "Backup tersedia:" "可用备份：")"
ls -lh "$BACKUP_DIR"/vpn_backup_*.tar.gz 2>/dev/null | awk '{print $9, "-", $5}' || echo "$(T "No backups found" "Tidak ada backup" "无备份")"

# Save backup metadata for web dashboard
METADATA_FILE="${BACKUP_DIR}/.backup_metadata.json"
cat > "$METADATA_FILE" <<EOF
{
  "last_backup": "$TIMESTAMP",
  "backup_type": "$BACKUP_TYPE",
  "backup_file": "$BACKUP_FILE",
  "backup_size": "$BACKUP_SIZE",
  "retention_days": $RETENTION_DAYS,
  "total_backups": $(ls -1 "$BACKUP_DIR"/vpn_backup_*.tar.gz 2>/dev/null | wc -l)
}
EOF

echo ""
log_info "$(T "Backup directory: $BACKUP_DIR" "Direktori backup: $BACKUP_DIR" "备份目录: $BACKUP_DIR")"
