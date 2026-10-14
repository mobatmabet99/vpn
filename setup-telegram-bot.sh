#!/bin/bash
# ==============================================================================
#  setup-telegram-bot.sh — Setup Telegram Bot for VPN Management
#  Branding: wrwb Store
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

install_cleanup_trap
need_root

echo "================================================================"
echo "  Setup Telegram Bot - VPN Management (wrwb Store)"
echo "================================================================"

# Install Python and dependencies
log_step "Installing Python dependencies..."
detect_os

if [[ "$OS_FAMILY" == "debian" ]]; then
  apt-get update
  apt-get install -y python3 python3-pip python3-venv
elif [[ "$OS_FAMILY" == "rhel" ]]; then
  $PKG_MGR install -y python3 python3-pip
fi

# Create virtual environment
VENV_DIR="/opt/vpn-telegram-bot"
log_info "Creating Python virtual environment at $VENV_DIR..."
mkdir -p "$VENV_DIR"
python3 -m venv "$VENV_DIR/venv"

# Install required packages
log_info "Installing Python packages..."
"$VENV_DIR/venv/bin/pip" install --upgrade pip
"$VENV_DIR/venv/bin/pip" install python-telegram-bot requests

# Copy bot script
log_info "Installing bot script..."
cp "$SCRIPT_DIR/telegram-bot.py" "$VENV_DIR/telegram-bot.py"
chmod +x "$VENV_DIR/telegram-bot.py"

# Get bot configuration
echo ""
echo "To create a Telegram bot:"
echo "  1. Open Telegram and search for @BotFather"
echo "  2. Send /newbot and follow instructions"
echo "  3. Copy the bot token"
echo ""
read -rp "Enter your Telegram Bot Token: " BOT_TOKEN

echo ""
echo "To get your Chat ID:"
echo "  1. Search for @userinfobot in Telegram"
echo "  2. Start chat and it will show your ID"
echo ""
read -rp "Enter your Telegram Chat ID (admin): " CHAT_ID

# Create config file
CONFIG_FILE="/etc/vpn/telegram-bot.json"
mkdir -p /etc/vpn

cat > "$CONFIG_FILE" <<EOF
{
  "bot_token": "$BOT_TOKEN",
  "admin_chat_ids": [$CHAT_ID],
  "script_dir": "$SCRIPT_DIR",
  "language": "en"
}
EOF

chmod 600 "$CONFIG_FILE"
log_success "Configuration saved to $CONFIG_FILE"

# Create systemd service
log_info "Creating systemd service..."
cat > /etc/systemd/system/vpn-telegram-bot.service <<EOF
[Unit]
Description=VPN Management Telegram Bot (wrwb Store)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$VENV_DIR
ExecStart=$VENV_DIR/venv/bin/python3 $VENV_DIR/telegram-bot.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
systemctl daemon-reload
systemctl enable vpn-telegram-bot
systemctl start vpn-telegram-bot

log_success "Telegram bot installed and started!"
echo ""
echo "Bot Commands:"
echo "  /start         - Show main menu"
echo "  /add_wg <name> - Add WireGuard client"
echo "  /del_wg <name> - Remove WireGuard client"
echo "  /qr_wg <name>  - Show QR code"
echo "  /add_ssh <user>- Add SSH user"
echo "  /del_ssh <user>- Remove SSH user"
echo "  /add_xray <name>- Add Xray user"
echo "  /del_xray <name>- Remove Xray user"
echo ""
echo "Check status: systemctl status vpn-telegram-bot"
echo "View logs: journalctl -u vpn-telegram-bot -f"
