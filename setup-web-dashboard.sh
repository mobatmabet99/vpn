#!/bin/bash
# ==============================================================================
#  setup-web-dashboard.sh — Setup Web Dashboard for VPN Management
#  Branding: wrwb Store
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

need_root

echo "================================================================"
echo "  Setup Web Dashboard - VPN Management (wrwb Store)"
echo "================================================================"

# Install Node.js
log_step "Installing Node.js..."
detect_os

if [[ "$OS_FAMILY" == "debian" ]]; then
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  apt-get install -y nodejs
elif [[ "$OS_FAMILY" == "rhel" ]]; then
  curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
  $PKG_MGR install -y nodejs
fi

# Verify installation
node --version
npm --version

# Install web dashboard
WEB_DIR="/opt/vpn-web-dashboard"
log_info "Installing web dashboard to $WEB_DIR..."

if [[ -d "$WEB_DIR" ]]; then
  log_warn "Web dashboard already exists. Backing up..."
  mv "$WEB_DIR" "${WEB_DIR}.backup.$(date +%Y%m%d%H%M%S)"
fi

mkdir -p "$WEB_DIR"
cp -r "$SCRIPT_DIR/web-dashboard/"* "$WEB_DIR/"

# Install npm dependencies
log_info "Installing Node.js dependencies..."
cd "$WEB_DIR"
npm install --production

# Create initial config
CONFIG_FILE="/etc/vpn/web-config.json"
mkdir -p /etc/vpn

if [[ ! -f "$CONFIG_FILE" ]]; then
  log_info "Creating initial configuration..."
  
  # Generate random JWT secret
  JWT_SECRET=$(openssl rand -base64 32)
  
  # Hash default password
  ADMIN_HASH='$2a$10$YourHashHere' # Will be replaced on first login
  
  cat > "$CONFIG_FILE" <<EOF
{
  "users": {
    "admin": "\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy"
  },
  "scriptDir": "$SCRIPT_DIR",
  "jwtSecret": "$JWT_SECRET"
}
EOF
  
  chmod 600 "$CONFIG_FILE"
  log_success "Configuration created: $CONFIG_FILE"
  log_warn "Default login: admin / admin (CHANGE THIS IMMEDIATELY!)"
fi

# Get server port
echo ""
read -rp "Enter web dashboard port [3000]: " WEB_PORT
WEB_PORT="${WEB_PORT:-3000}"

# Create environment file
cat > "$WEB_DIR/.env" <<EOF
PORT=$WEB_PORT
JWT_SECRET=$(openssl rand -base64 32)
NODE_ENV=production
EOF

# Create systemd service
log_info "Creating systemd service..."
cat > /etc/systemd/system/vpn-web-dashboard.service <<EOF
[Unit]
Description=VPN Management Web Dashboard (wrwb Store)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WEB_DIR
ExecStart=/usr/bin/node $WEB_DIR/server.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

# Open firewall port
log_info "Opening firewall port $WEB_PORT..."
open_firewall_port "$WEB_PORT" "tcp"

# Enable and start service
systemctl daemon-reload
systemctl enable vpn-web-dashboard
systemctl start vpn-web-dashboard

# Get server IP
SERVER_IP=$(get_public_ip)

log_success "Web dashboard installed and started!"
echo ""
echo "================================================================"
echo "  Access your dashboard at:"
echo "  http://$SERVER_IP:$WEB_PORT"
echo ""
echo "  Default credentials:"
echo "    Username: admin"
echo "    Password: admin"
echo ""
echo "  ⚠️  IMPORTANT: Change password immediately after first login!"
echo "================================================================"
echo ""
echo "Useful commands:"
echo "  Check status: systemctl status vpn-web-dashboard"
echo "  View logs: journalctl -u vpn-web-dashboard -f"
echo "  Restart: systemctl restart vpn-web-dashboard"
