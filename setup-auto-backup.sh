#!/bin/bash
# ==============================================================================
#  setup-auto-backup.sh — Setup Automatic Daily Backup (wrwb Store)
#  
#  Features:
#    - Configures daily automatic backups at 03:00 AM
#    - Sets up backup retention policy (default: 7 days)
#    - Creates backup directory structure
#    - Tests backup functionality
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

need_root

echo "================================================================"
echo "  Setup Auto Backup - VPN Configuration (wrwb Store)"
echo "================================================================"

# Create backup directory
BACKUP_DIR="/var/backups/vpn"
log_info "Creating backup directory: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# Make backup script executable
chmod +x "$SCRIPT_DIR/backup.sh"

# Configure backup schedule
echo ""
echo "Configure automatic backup schedule:"
echo "  1) Daily at 03:00 AM (recommended)"
echo "  2) Daily at custom time"
echo "  3) Twice daily (03:00 AM and 03:00 PM)"
echo "  4) Weekly (Sunday at 03:00 AM)"
read -rp "Choose option [1-4] (default 1): " SCHEDULE_OPTION
SCHEDULE_OPTION="${SCHEDULE_OPTION:-1}"

case "$SCHEDULE_OPTION" in
  1)
    CRON_SCHEDULE="0 3 * * *"
    SCHEDULE_DESC="Daily at 03:00 AM"
    ;;
  2)
    read -rp "Enter hour (0-23): " HOUR
    read -rp "Enter minute (0-59): " MINUTE
    CRON_SCHEDULE="$MINUTE $HOUR * * *"
    SCHEDULE_DESC="Daily at $HOUR:$MINUTE"
    ;;
  3)
    CRON_SCHEDULE="0 3,15 * * *"
    SCHEDULE_DESC="Twice daily at 03:00 AM and 03:00 PM"
    ;;
  4)
    CRON_SCHEDULE="0 3 * * 0"
    SCHEDULE_DESC="Weekly on Sunday at 03:00 AM"
    ;;
  *)
    CRON_SCHEDULE="0 3 * * *"
    SCHEDULE_DESC="Daily at 03:00 AM"
    ;;
esac

# Configure retention
echo ""
read -rp "Backup retention (days) [7]: " RETENTION
RETENTION="${RETENTION:-7}"

# Create cron job
CRON_JOB="$CRON_SCHEDULE $SCRIPT_DIR/backup.sh auto >> /var/log/vpn-backup.log 2>&1"
CRON_FILE="/etc/cron.d/vpn-auto-backup"

log_info "Creating cron job..."
cat > "$CRON_FILE" <<EOF
# VPN Auto Backup - wrwb Store
# Schedule: $SCHEDULE_DESC
# Retention: $RETENTION days
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

$CRON_JOB
EOF

chmod 644 "$CRON_FILE"

# Create log file
touch /var/log/vpn-backup.log
chmod 644 /var/log/vpn-backup.log

# Setup logrotate for backup logs
log_info "Setting up log rotation..."
cat > /etc/logrotate.d/vpn-backup <<EOF
/var/log/vpn-backup.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF

# Test backup
log_step "Testing backup functionality..."
if "$SCRIPT_DIR/backup.sh" manual; then
  log_success "Test backup completed successfully!"
else
  log_error "Test backup failed!"
  exit 1
fi

# Show summary
echo ""
echo "================================================================"
echo "  Auto Backup Configuration Complete!"
echo "================================================================"
echo ""
echo "Configuration:"
echo "  Backup directory: $BACKUP_DIR"
echo "  Schedule: $SCHEDULE_DESC"
echo "  Retention: $RETENTION days"
echo "  Log file: /var/log/vpn-backup.log"
echo ""
echo "Manual backup command:"
echo "  sudo $SCRIPT_DIR/backup.sh manual"
echo ""
echo "View backup logs:"
echo "  tail -f /var/log/vpn-backup.log"
echo ""
echo "List backups:"
echo "  ls -lh $BACKUP_DIR"
echo ""
echo "Restore from backup:"
echo "  1. Extract: tar -xzf /var/backups/vpn/vpn_backup_*.tar.gz -C /tmp"
echo "  2. Copy configs back to /etc/wireguard, /etc/xray, etc."
echo "  3. Restart services"
echo ""
log_success "Automatic backups are now active!"
