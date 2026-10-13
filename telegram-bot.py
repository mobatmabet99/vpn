#!/usr/bin/env python3
# ==============================================================================
#  telegram-bot.py — VPN Management via Telegram Bot (wrwb Store)
#  
#  Features:
#    - Add/remove WireGuard clients
#    - Manage SSH/Xray users
#    - Check server status
#    - View limits & usage
#    - Backup server configs
#    - Restart services
#  
#  Installation:
#    pip3 install python-telegram-bot requests
#  
#  Usage:
#    python3 telegram-bot.py
# ==============================================================================

import os
import sys
import json
import subprocess
import logging
from datetime import datetime
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, ContextTypes

# Configuration
CONFIG_FILE = "/etc/vpn/telegram-bot.json"
LOG_FILE = "/var/log/vpn-telegram-bot.log"

# Setup logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Default configuration
DEFAULT_CONFIG = {
    "bot_token": "",
    "admin_chat_ids": [],
    "script_dir": "/root/vpn",
    "language": "en"
}

def load_config():
    """Load bot configuration from file"""
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    return DEFAULT_CONFIG.copy()

def save_config(config):
    """Save bot configuration to file"""
    os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=2)
    os.chmod(CONFIG_FILE, 0o600)

def is_admin(user_id: int) -> bool:
    """Check if user is admin"""
    config = load_config()
    return user_id in config.get('admin_chat_ids', [])

def run_script(script_name: str, *args) -> tuple:
    """Run a VPN management script and return (success, output)"""
    config = load_config()
    script_dir = config.get('script_dir', '/root/vpn')
    script_path = os.path.join(script_dir, script_name)
    
    if not os.path.exists(script_path):
        return False, f"Script not found: {script_name}"
    
    try:
        # v3.1: longer timeout (120s) for slow operations like first backup / installs
        cmd = ['sudo', 'bash', script_path] + list(args)
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=120
        )
        return result.returncode == 0, result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        # v3.1: clearer timeout message for slow server operations
        return False, "Command timed out after 120s (server may be busy, try again)."
    except Exception as e:
        return False, f"Error: {str(e)}"

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    user_id = update.effective_user.id
    
    if not is_admin(user_id):
        await update.message.reply_text(
            "❌ Unauthorized. Contact admin to get access."
        )
        return
    
    keyboard = [
        [InlineKeyboardButton("📊 Server Status", callback_data='status')],
        [InlineKeyboardButton("👥 WireGuard Clients", callback_data='wg_menu')],
        [InlineKeyboardButton("🔑 SSH Users", callback_data='ssh_menu')],
        [InlineKeyboardButton("⚡ Xray Users", callback_data='xray_menu')],
        [InlineKeyboardButton("📈 Check Limits", callback_data='check_limits')],
        [InlineKeyboardButton("💾 Backup", callback_data='backup_menu')],
        [InlineKeyboardButton("🔄 Restart Services", callback_data='restart_menu')],
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        "🎛️ *VPN Management Bot - wrwb Store*\n\n"
        "Welcome! Choose an option:",
        parse_mode='Markdown',
        reply_markup=reply_markup
    )

async def button_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle button callbacks"""
    query = update.callback_query
    await query.answer()
    
    user_id = update.effective_user.id
    if not is_admin(user_id):
        await query.edit_message_text("❌ Unauthorized")
        return
    
    data = query.data
    
    # Main menu
    if data == 'main_menu':
        keyboard = [
            [InlineKeyboardButton("📊 Server Status", callback_data='status')],
            [InlineKeyboardButton("👥 WireGuard Clients", callback_data='wg_menu')],
            [InlineKeyboardButton("🔑 SSH Users", callback_data='ssh_menu')],
            [InlineKeyboardButton("⚡ Xray Users", callback_data='xray_menu')],
            [InlineKeyboardButton("📈 Check Limits", callback_data='check_limits')],
            [InlineKeyboardButton("💾 Backup", callback_data='backup_menu')],
            [InlineKeyboardButton("🔄 Restart Services", callback_data='restart_menu')],
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await query.edit_message_text(
            "🎛️ *VPN Management Bot - wrwb Store*\n\nChoose an option:",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )
    
    # Server Status
    elif data == 'status':
        await query.edit_message_text("⏳ Checking server status...")
        success, output = run_script('status.sh')
        
        # Truncate if too long for Telegram
        if len(output) > 4000:
            output = output[:4000] + "\n... (truncated)"
        
        keyboard = [[InlineKeyboardButton("« Back", callback_data='main_menu')]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await query.edit_message_text(
            f"```\n{output}\n```",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )
    
    # WireGuard Menu
    elif data == 'wg_menu':
        keyboard = [
            [InlineKeyboardButton("📋 List Clients", callback_data='wg_list')],
            [InlineKeyboardButton("« Back", callback_data='main_menu')]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await query.edit_message_text(
            "👥 *WireGuard Management*\n\n"
            "To add client: `/add_wg <name> [max_ip] [max_gb]`\n"
            "To remove: `/del_wg <name>`\n"
            "To show QR: `/qr_wg <name>`",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )
    
    elif data == 'wg_list':
        await query.edit_message_text("⏳ Loading WireGuard clients...")
        success, output = run_script('list-clients.sh')
        
        if len(output) > 4000:
            output = output[:4000] + "\n... (truncated)"
        
        keyboard = [[InlineKeyboardButton("« Back", callback_data='wg_menu')]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await query.edit_message_text(
            f"```\n{output}\n```",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )
    
    # SSH Menu
    elif data == 'ssh_menu':
        keyboard = [[InlineKeyboardButton("« Back", callback_data='main_menu')]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await query.edit_message_text(
            "🔑 *SSH VPN Management*\n\n"
            "To add user: `/add_ssh <username> [password] [days]`\n"
            "To remove: `/del_ssh <username>`",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )
    
    # Xray Menu
    elif data == 'xray_menu':
        keyboard = [[InlineKeyboardButton("« Back", callback_data='main_menu')]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await query.edit_message_text(
            "⚡ *Xray Management*\n\n"
            "To add user: `/add_xray <name> [max_ip] [max_gb]`\n"
            "To remove: `/del_xray <name>`",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )
    
    # Check Limits
    elif data == 'check_limits':
        await query.edit_message_text("⏳ Checking limits...")
        success, output = run_script('check-limits.sh')
        
        if len(output) > 4000:
            output = output[:4000] + "\n... (truncated)"
        
        keyboard = [[InlineKeyboardButton("« Back", callback_data='main_menu')]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await query.edit_message_text(
            f"```\n{output}\n```",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )
    
    # Backup Menu
    elif data == 'backup_menu':
        keyboard = [
            [InlineKeyboardButton("💾 Manual Backup Now", callback_data='backup_now')],
            [InlineKeyboardButton("📥 Download Backup", callback_data='backup_download')],
            [InlineKeyboardButton("« Back", callback_data='main_menu')]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await query.edit_message_text(
            "💾 *Backup Management*\n\n"
            "Auto-backup runs daily at 03:00 AM\n"
            "Manual backup available anytime",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )
    
    elif data == 'backup_now':
        await query.edit_message_text("⏳ Creating backup...")
        success, output = run_script('backup.sh', 'manual')
        
        keyboard = [[InlineKeyboardButton("« Back", callback_data='backup_menu')]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        status = "✅ Backup completed!" if success else "❌ Backup failed!"
        await query.edit_message_text(
            f"{status}\n\n```\n{output[:500]}\n```",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )
    
    # Restart Menu
    elif data == 'restart_menu':
        keyboard = [
            [InlineKeyboardButton("🔄 WireGuard", callback_data='restart_wg')],
            [InlineKeyboardButton("🔄 SSH Services", callback_data='restart_ssh')],
            [InlineKeyboardButton("🔄 Xray", callback_data='restart_xray')],
            [InlineKeyboardButton("🔄 All Services", callback_data='restart_all')],
            [InlineKeyboardButton("« Back", callback_data='main_menu')]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await query.edit_message_text(
            "🔄 *Restart Services*\n\nChoose service to restart:",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )
    
    elif data.startswith('restart_'):
        service = data.replace('restart_', '')
        await query.edit_message_text(f"⏳ Restarting {service}...")
        
        if service == 'wg':
            success, output = subprocess.getstatusoutput('systemctl restart wg-quick@wg0')
        elif service == 'ssh':
            success, output = subprocess.getstatusoutput('systemctl restart ssh dropbear stunnel4 ssh-ws')
        elif service == 'xray':
            success, output = subprocess.getstatusoutput('systemctl restart xray')
        elif service == 'all':
            success, output = subprocess.getstatusoutput('systemctl restart wg-quick@wg0 ssh dropbear xray')
        else:
            success, output = False, "Unknown service"
        
        keyboard = [[InlineKeyboardButton("« Back", callback_data='restart_menu')]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        status = "✅ Restarted!" if success == 0 else "❌ Failed!"
        await query.edit_message_text(
            f"{status}",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )

# Command handlers
async def add_wg(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Add WireGuard client: /add_wg <name> [max_ip] [max_gb]"""
    if not is_admin(update.effective_user.id):
        await update.message.reply_text("❌ Unauthorized")
        return
    
    if len(context.args) < 1:
        await update.message.reply_text("Usage: /add_wg <name> [max_ip] [max_gb]")
        return
    
    name = context.args[0]
    max_ip = context.args[1] if len(context.args) > 1 else "2"
    max_gb = context.args[2] if len(context.args) > 2 else "100"
    
    await update.message.reply_text(f"⏳ Adding WireGuard client '{name}'...")
    success, output = run_script('add-client.sh', name, max_ip, max_gb)
    
    if success:
        await update.message.reply_text(f"✅ Client '{name}' created!\n\nUse /qr_wg {name} to get QR code")
    else:
        await update.message.reply_text(f"❌ Failed to create client:\n{output[:500]}")

async def del_wg(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Remove WireGuard client: /del_wg <name>"""
    if not is_admin(update.effective_user.id):
        await update.message.reply_text("❌ Unauthorized")
        return
    
    if len(context.args) < 1:
        await update.message.reply_text("Usage: /del_wg <name>")
        return
    
    name = context.args[0]
    await update.message.reply_text(f"⏳ Removing WireGuard client '{name}'...")
    success, output = run_script('remove-client.sh', name)
    
    if success:
        await update.message.reply_text(f"✅ Client '{name}' removed!")
    else:
        await update.message.reply_text(f"❌ Failed:\n{output[:500]}")

async def qr_wg(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Show QR code: /qr_wg <name>"""
    if not is_admin(update.effective_user.id):
        await update.message.reply_text("❌ Unauthorized")
        return
    
    if len(context.args) < 1:
        await update.message.reply_text("Usage: /qr_wg <name>")
        return
    
    name = context.args[0]
    qr_path = f"/etc/wireguard/clients/{name}/{name}.png"
    
    if os.path.exists(qr_path):
        await update.message.reply_photo(photo=open(qr_path, 'rb'), caption=f"QR Code for {name}")
    else:
        await update.message.reply_text(f"❌ QR code not found for '{name}'")

async def add_ssh(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Add SSH user: /add_ssh <username> [password] [days]"""
    if not is_admin(update.effective_user.id):
        await update.message.reply_text("❌ Unauthorized")
        return
    
    if len(context.args) < 1:
        await update.message.reply_text("Usage: /add_ssh <username> [password] [days]")
        return
    
    username = context.args[0]
    password = context.args[1] if len(context.args) > 1 else ""
    days = context.args[2] if len(context.args) > 2 else "30"
    
    await update.message.reply_text(f"⏳ Creating SSH user '{username}'...")
    success, output = run_script('add-ssh-user.sh', username, password, days)
    
    if success:
        await update.message.reply_text(f"✅ SSH user '{username}' created!\n\n{output[:1000]}")
    else:
        await update.message.reply_text(f"❌ Failed:\n{output[:500]}")

async def del_ssh(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Remove SSH user: /del_ssh <username>"""
    if not is_admin(update.effective_user.id):
        await update.message.reply_text("❌ Unauthorized")
        return
    
    if len(context.args) < 1:
        await update.message.reply_text("Usage: /del_ssh <username>")
        return
    
    username = context.args[0]
    await update.message.reply_text(f"⏳ Removing SSH user '{username}'...")
    success, output = run_script('remove-ssh-user.sh', username)
    
    if success:
        await update.message.reply_text(f"✅ SSH user '{username}' removed!")
    else:
        await update.message.reply_text(f"❌ Failed:\n{output[:500]}")

async def add_xray(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Add Xray user: /add_xray <name> [max_ip] [max_gb]"""
    if not is_admin(update.effective_user.id):
        await update.message.reply_text("❌ Unauthorized")
        return
    
    if len(context.args) < 1:
        await update.message.reply_text("Usage: /add_xray <name> [max_ip] [max_gb]")
        return
    
    name = context.args[0]
    max_ip = context.args[1] if len(context.args) > 1 else "2"
    max_gb = context.args[2] if len(context.args) > 2 else "100"
    
    await update.message.reply_text(f"⏳ Adding Xray user '{name}'...")
    success, output = run_script('add-xray-user.sh', name, max_ip, max_gb)
    
    if success:
        await update.message.reply_text(f"✅ Xray user '{name}' created!\n\n{output[:1000]}")
    else:
        await update.message.reply_text(f"❌ Failed:\n{output[:500]}")

async def del_xray(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Remove Xray user: /del_xray <name>"""
    if not is_admin(update.effective_user.id):
        await update.message.reply_text("❌ Unauthorized")
        return
    
    if len(context.args) < 1:
        await update.message.reply_text("Usage: /del_xray <name>")
        return
    
    name = context.args[0]
    await update.message.reply_text(f"⏳ Removing Xray user '{name}'...")
    success, output = run_script('remove-xray-user.sh', name)
    
    if success:
        await update.message.reply_text(f"✅ Xray user '{name}' removed!")
    else:
        await update.message.reply_text(f"❌ Failed:\n{output[:500]}")

def main():
    """Main function"""
    config = load_config()
    
    if not config.get('bot_token'):
        print("ERROR: Bot token not configured!")
        print(f"Please edit {CONFIG_FILE} and add your bot token")
        print("\nExample config:")
        print(json.dumps(DEFAULT_CONFIG, indent=2))
        sys.exit(1)
    
    # Create application
    application = Application.builder().token(config['bot_token']).build()
    
    # Add handlers
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("add_wg", add_wg))
    application.add_handler(CommandHandler("del_wg", del_wg))
    application.add_handler(CommandHandler("qr_wg", qr_wg))
    application.add_handler(CommandHandler("add_ssh", add_ssh))
    application.add_handler(CommandHandler("del_ssh", del_ssh))
    application.add_handler(CommandHandler("add_xray", add_xray))
    application.add_handler(CommandHandler("del_xray", del_xray))
    application.add_handler(CallbackQueryHandler(button_callback))
    
    # Start bot
    logger.info("Starting VPN Telegram Bot...")
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == '__main__':
    main()
