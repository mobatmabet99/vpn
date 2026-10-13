#!/bin/bash
# ==============================================================================
#  setup-all-v3.sh — Install ALL v3 Features (Telegram Bot + Web Dashboard + Auto Backup)
#  Branding: wrwb Store
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

need_root

echo "================================================================"
echo "  VPN Management v3 - Complete Setup (wrwb Store)"
echo "================================================================"
echo ""
echo "This will install:"
echo "  ✓ Telegram Bot for remote VPN management"
echo "  ✓ Web Dashboard for browser-based control"
echo "  ✓ Automatic daily backups"
echo ""
read -rp "Continue? [Y/n]: " CONFIRM
[[ "$CONFIRM" =~ ^[Nn]$ ]] && exit 0

# Make all scripts executable
chmod +x "$SCRIPT_DIR"/*.sh

# 1. Setup Auto Backup
log_step "Step 1/3: Setting up automatic backups..."
"$SCRIPT_DIR/setup-auto-backup.sh"

echo ""
read -rp "Press Enter to continue to Telegram Bot setup..."

# 2. Setup Telegram Bot
log_step "Step 2/3: Setting up Telegram Bot..."
echo ""
echo "Do you want to setup Telegram Bot?"
read -rp "[Y/n]: " SETUP_TELEGRAM
if [[ ! "$SETUP_TELEGRAM" =~ ^[Nn]$ ]]; then
  "$SCRIPT_DIR/setup-telegram-bot.sh"
else
  log_warn "Skipping Telegram Bot setup"
fi

echo ""
read -rp "Press Enter to continue to Web Dashboard setup..."

# 3. Setup Web Dashboard
log_step "Step 3/3: Setting up Web Dashboard..."
echo ""
echo "Do you want to setup Web Dashboard?"
read -rp "[Y/n]: " SETUP_WEB
if [[ ! "$SETUP_WEB" =~ ^[Nn]$ ]]; then
  "$SCRIPT_DIR/setup-web-dashboard.sh"
else
  log_warn "Skipping Web Dashboard setup"
fi

# Summary
clear
echo "================================================================"
echo "  🎉 VPN Management v3 Setup Complete! (wrwb Store)"
echo "================================================================"
echo ""
echo "✅ Installed Features:"
echo ""
echo "1. 💾 Automatic Backups"
echo "   - Location: /var/backups/vpn"
echo "   - View logs: tail -f /var/log/vpn-backup.log"
echo "   - Manual backup: sudo $SCRIPT_DIR/backup.sh manual"
echo ""

if [[ ! "$SETUP_TELEGRAM" =~ ^[Nn]$ ]]; then
  echo "2. 🤖 Telegram Bot"
  echo "   - Status: systemctl status vpn-telegram-bot"
  echo "   - Logs: journalctl -u vpn-telegram-bot -f"
  echo "   - Send /start to your bot to begin"
  echo ""
fi

if [[ ! "$SETUP_WEB" =~ ^[Nn]$ ]]; then
  SERVER_IP=$(get_public_ip)
  WEB_PORT=$(grep PORT /opt/vpn-web-dashboard/.env 2>/dev/null | cut -d= -f2 || echo "3000")
  
  echo "3. 🌐 Web Dashboard"
  echo "   - URL: http://$SERVER_IP:$WEB_PORT"
  echo "   - Login: admin / admin (CHANGE THIS!)"
  echo "   - Status: systemctl status vpn-web-dashboard"
  echo ""
fi

echo "================================================================"
echo ""
echo "Quick Commands:"
echo "  sudo ./menu.sh          # Interactive menu"
echo "  sudo ./status.sh        # Check server status"
echo "  sudo ./backup.sh manual # Create backup now"
echo ""
log_success "All v3 features are ready to use!"
