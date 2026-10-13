# VPN Management v3 - New Features Documentation

> **wrwb Store** — Advanced VPN Management with Remote Control & Auto Backup

Version 3.0 adds powerful new features for managing your VPN server remotely and automatically backing up configurations.

## 🆕 What's New in v3

### 1. 🤖 Telegram Bot Management
Control your entire VPN server through Telegram! No need to SSH into the server anymore.

**Features:**
- ✅ Add/remove WireGuard clients remotely
- ✅ Manage SSH and Xray users
- ✅ Check server status in real-time
- ✅ View limits and usage statistics
- ✅ Create manual backups
- ✅ Restart services
- ✅ Get QR codes directly in Telegram

**Setup:**
```bash
sudo ./setup-telegram-bot.sh
```

**Commands:**
- `/start` - Show main menu
- `/add_wg <name> [max_ip] [max_gb]` - Add WireGuard client
- `/del_wg <name>` - Remove WireGuard client
- `/qr_wg <name>` - Get QR code image
- `/add_ssh <user> [password] [days]` - Add SSH user
- `/del_ssh <user>` - Remove SSH user
- `/add_xray <name> [max_ip] [max_gb]` - Add Xray user
- `/del_xray <name>` - Remove Xray user

**Requirements:**
- Telegram Bot Token (get from @BotFather)
- Your Telegram Chat ID (get from @userinfobot)

---

### 2. 🌐 Web Dashboard
Beautiful browser-based control panel for managing your VPN server from anywhere.

**Features:**
- ✅ Modern, responsive web interface
- ✅ Secure JWT authentication
- ✅ Real-time server status monitoring
- ✅ User management (WireGuard, SSH, Xray)
- ✅ Backup management (create, list, download)
- ✅ Service control (restart services)
- ✅ Mobile-friendly design

**Setup:**
```bash
sudo ./setup-web-dashboard.sh
```

**Default Access:**
- URL: `http://YOUR_SERVER_IP:3000`
- Username: `admin`
- Password: `admin`

⚠️ **IMPORTANT:** Change the default password immediately after first login!

**Technology Stack:**
- Backend: Node.js + Express
- Frontend: Pure HTML/CSS/JavaScript (no frameworks needed)
- Authentication: JWT tokens
- Security: Helmet.js, bcrypt password hashing

---

### 3. 💾 Automatic Backup System
Never lose your VPN configurations again! Automatic daily backups with configurable retention.

**Features:**
- ✅ Automatic daily backups (default: 03:00 AM)
- ✅ Configurable schedule (daily, twice daily, weekly)
- ✅ Backup retention policy (default: keep 7 days)
- ✅ Backs up all configs: WireGuard, SSH, Xray, OpenVPN, Shadowsocks
- ✅ Compressed archives (tar.gz)
- ✅ Manual backup anytime
- ✅ Integrated with Web Dashboard and Telegram Bot

**Setup:**
```bash
sudo ./setup-auto-backup.sh
```

**Manual Backup:**
```bash
sudo ./backup.sh manual
```

**Backup Location:**
```
/var/backups/vpn/
```

**Backup Contents:**
- WireGuard configurations and client keys
- SSH VPN user database
- Xray/V2Ray configurations and user database
- OpenVPN certificates and configs
- Shadowsocks configurations
- VPN limits database
- Language settings
- Bot configurations

**Restore from Backup:**
```bash
# Extract backup
tar -xzf /var/backups/vpn/vpn_backup_manual_20261013_120000.tar.gz -C /tmp

# Copy configs back
cp -r /tmp/vpn_backup_*/wireguard/* /etc/wireguard/
cp -r /tmp/vpn_backup_*/xray/* /etc/xray/
# ... etc

# Restart services
systemctl restart wg-quick@wg0 xray ssh dropbear
```

---

## 🚀 Quick Start - Install All v3 Features

Want everything? One command installs all v3 features:

```bash
sudo ./setup-all-v3.sh
```

This will interactively install:
1. Automatic backup system
2. Telegram bot (optional)
3. Web dashboard (optional)

---

## 📋 New Menu Options

Run `sudo ./menu.sh` to see new options:

```
[18] Setup Telegram Bot (remote management)
[19] Setup Web Dashboard (browser control)
[20] Setup Auto Backup (daily backups)
[21] Manual Backup Now
[22] Install ALL v3 Features
```

---

## 🔧 Configuration Files

### Telegram Bot
```
/etc/vpn/telegram-bot.json
```

### Web Dashboard
```
/etc/vpn/web-config.json
/opt/vpn-web-dashboard/.env
```

### Backups
```
/var/backups/vpn/          # Backup files
/var/log/vpn-backup.log    # Backup logs
/etc/cron.d/vpn-auto-backup # Cron schedule
```

---

## 🛠️ Service Management

### Telegram Bot
```bash
# Status
systemctl status vpn-telegram-bot

# Logs
journalctl -u vpn-telegram-bot -f

# Restart
systemctl restart vpn-telegram-bot

# Stop
systemctl stop vpn-telegram-bot

# Start
systemctl start vpn-telegram-bot
```

### Web Dashboard
```bash
# Status
systemctl status vpn-web-dashboard

# Logs
journalctl -u vpn-web-dashboard -f

# Restart
systemctl restart vpn-web-dashboard

# Change port
nano /opt/vpn-web-dashboard/.env
# Edit PORT=3000
systemctl restart vpn-web-dashboard
```

---

## 🔒 Security Recommendations

1. **Change Default Passwords**
   - Web dashboard: Change `admin/admin` immediately
   - Use strong passwords (min 12 characters)

2. **Firewall Configuration**
   - Web dashboard port should be secured (consider VPN-only access)
   - Use HTTPS with reverse proxy (nginx/caddy) in production

3. **Telegram Bot**
   - Keep bot token secret
   - Only add trusted Chat IDs to admin list
   - Bot config file is chmod 600 by default

4. **Backups**
   - Backup files contain sensitive data
   - Secured with chmod 600
   - Consider offsite backup storage

5. **SSL/TLS**
   - For production, use nginx reverse proxy with Let's Encrypt
   - Example nginx config provided below

---

## 🌐 Production Setup with HTTPS (Optional)

### Using Nginx + Let's Encrypt

1. Install nginx and certbot:
```bash
sudo apt install nginx certbot python3-certbot-nginx
```

2. Configure nginx:
```nginx
server {
    listen 80;
    server_name vpn.yourdomain.com;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

3. Get SSL certificate:
```bash
sudo certbot --nginx -d vpn.yourdomain.com
```

---

## 📊 System Requirements for v3

- **Python 3.7+** (for Telegram bot)
- **Node.js 16+** (for Web dashboard)
- **Additional disk space:** ~50MB for dependencies
- **RAM:** +100MB for running services
- **Network:** Ports 3000 (web) and bot uses HTTPS to Telegram

---

## 🐛 Troubleshooting

### Telegram Bot Not Responding
```bash
# Check status
systemctl status vpn-telegram-bot

# Check logs
journalctl -u vpn-telegram-bot -n 50

# Verify token
cat /etc/vpn/telegram-bot.json

# Test bot manually
/opt/vpn-telegram-bot/venv/bin/python3 /opt/vpn-telegram-bot/telegram-bot.py
```

### Web Dashboard Not Loading
```bash
# Check if port is open
ss -tlnp | grep 3000

# Check service
systemctl status vpn-web-dashboard

# Check logs
journalctl -u vpn-web-dashboard -n 50

# Test manually
cd /opt/vpn-web-dashboard
node server.js
```

### Backup Failed
```bash
# Check logs
tail -f /var/log/vpn-backup.log

# Check permissions
ls -la /var/backups/vpn

# Run manually with verbose
sudo bash -x ./backup.sh manual
```

### Backup Aborted: Insufficient Disk Space (v3.1)
The backup script checks free space first and aborts when less than 100MB is available:
```bash
# Check free space
df -h /var/backups/vpn

# Remove backups older than 7 days manually
find /var/backups/vpn -name "vpn_backup_*.tar.gz" -mtime +7 -delete

# Re-run backup
sudo ./backup.sh manual
```

### Web Dashboard: 429 Too Many Requests (v3.1)
Login and user-creation endpoints are rate-limited to prevent brute-force:
- Login: max 10 attempts per minute per IP
- Add user/client: max 30 requests per minute per IP

Wait one minute and try again. If you are behind a shared NAT, all users share the same limit.

### Web Dashboard: Invalid Name Error (v3.1)
User and client names must match `^[a-zA-Z0-9_-]{1,32}$` (letters, numbers, dash, underscore only, max 32 chars).
Rename the account (e.g. `phone-andi` is valid, `phone andi!` is not) and try again.

### Telegram Bot: Command Timed Out After 120s (v3.1)
Long operations (first backup, package installs) can take a while. The bot waits up to 120 seconds.
If it times out, the operation may still be running in the background — check the result with `/start` → Server Status, or run the script manually via SSH.

---

## 🔄 Upgrade from v1.4 to v3

Your existing VPN setup is fully compatible! v3 only adds new features:

```bash
cd vpn
git pull origin main

# Install new features
sudo ./setup-all-v3.sh

# Or install individually
sudo ./setup-telegram-bot.sh
sudo ./setup-web-dashboard.sh
sudo ./setup-auto-backup.sh
```

No changes to existing clients or configurations required!

---

## 📱 Screenshots & Examples

### Telegram Bot Interface
```
🎛️ VPN Management Bot - wrwb Store

Welcome! Choose an option:

📊 Server Status
👥 WireGuard Clients
🔑 SSH Users
⚡ Xray Users
📈 Check Limits
💾 Backup
🔄 Restart Services
```

### Web Dashboard
- Clean, modern interface
- Mobile responsive
- Real-time status updates
- One-click actions

---

## 💡 Use Cases

### Home Users
- Manage VPN from phone via Telegram
- Create backups before experiments
- Check who's connected

### Resellers
- Professional web interface for customers
- Remote management without SSH access
- Automated backups for peace of mind

### Developers
- API-ready backend (REST endpoints)
- Easy to extend with custom features
- Clean code structure

---

## 🤝 Contributing

Found a bug or want to add features? Pull requests welcome!

**Priorities for community contributions:**
- Mobile app (React Native / Flutter)
- REST API documentation
- Docker containerization
- Monitoring/alerting integration
- Multi-language support for web UI

---

## 📄 License

Same as main project - Free for personal and commercial use.

---

## 🙏 Credits

Made with ❤️ by **wrwb Store**

v3 Features:
- Telegram Bot: Python + python-telegram-bot
- Web Dashboard: Node.js + Express
- Backup System: Bash + tar + cron

---

**Questions or Issues?**
- Check logs first: `journalctl -u vpn-* -f`
- Run diagnostics: `sudo ./status.sh`
- Join our community (if available)

---

🎉 **Enjoy your supercharged VPN management with v3!**
