#!/usr/bin/env node
// ==============================================================================
//  server.js — VPN Management Web Dashboard Backend (wrwb Store)
//  
//  Features:
//    - Secure authentication with JWT
//    - REST API for VPN management
//    - Real-time server status
//    - User management (WireGuard, SSH, Xray)
//    - Backup management
//    - Service control
// ==============================================================================

const express = require('express');
const session = require('express-session');
const bodyParser = require('body-parser');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const compression = require('compression');
const helmet = require('helmet');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');
const util = require('util');

const execPromise = util.promisify(exec);

const app = express();
const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET || 'change-this-secret-key-in-production';

// Configuration
const CONFIG_FILE = '/etc/vpn/web-config.json';
const SCRIPT_DIR = path.resolve(__dirname, '..');

// Middleware
app.use(helmet());
app.use(compression());
app.use(cors());
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'public')));

// Session configuration
app.use(session({
  secret: JWT_SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: { secure: false, maxAge: 24 * 60 * 60 * 1000 } // 24 hours
}));

// Load configuration
function loadConfig() {
  if (fs.existsSync(CONFIG_FILE)) {
    return JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
  }
  return {
    users: {
      admin: bcrypt.hashSync('admin', 10)
    },
    scriptDir: SCRIPT_DIR
  };
}

function saveConfig(config) {
  fs.mkdirSync(path.dirname(CONFIG_FILE), { recursive: true });
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));
  fs.chmodSync(CONFIG_FILE, 0o600);
}

// Initialize config
let config = loadConfig();
if (!fs.existsSync(CONFIG_FILE)) {
  saveConfig(config);
}

// Authentication middleware
function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'Access denied. No token provided.' });
  }

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) {
      return res.status(403).json({ error: 'Invalid token' });
    }
    req.user = user;
    next();
  });
}

// Helper function to run VPN scripts
async function runScript(scriptName, ...args) {
  const scriptPath = path.join(config.scriptDir, scriptName);
  const command = `sudo bash ${scriptPath} ${args.join(' ')}`;
  
  try {
    const { stdout, stderr } = await execPromise(command, { timeout: 60000 });
    return { success: true, output: stdout + stderr };
  } catch (error) {
    return { success: false, output: error.message };
  }
}

// Routes

// Login
app.post('/api/login', (req, res) => {
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ error: 'Username and password required' });
  }

  if (!config.users[username]) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  if (!bcrypt.compareSync(password, config.users[username])) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  const token = jwt.sign({ username }, JWT_SECRET, { expiresIn: '24h' });
  res.json({ token, username });
});

// Change password
app.post('/api/change-password', authenticateToken, (req, res) => {
  const { oldPassword, newPassword } = req.body;
  const username = req.user.username;

  if (!bcrypt.compareSync(oldPassword, config.users[username])) {
    return res.status(401).json({ error: 'Invalid old password' });
  }

  config.users[username] = bcrypt.hashSync(newPassword, 10);
  saveConfig(config);

  res.json({ success: true, message: 'Password changed successfully' });
});

// Server status
app.get('/api/status', authenticateToken, async (req, res) => {
  try {
    const result = await runScript('status.sh');
    res.json({ success: result.success, data: result.output });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// WireGuard - List clients
app.get('/api/wireguard/clients', authenticateToken, async (req, res) => {
  try {
    const result = await runScript('list-clients.sh');
    res.json({ success: result.success, data: result.output });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// WireGuard - Add client
app.post('/api/wireguard/clients', authenticateToken, async (req, res) => {
  const { name, maxIp = '2', maxGb = '100' } = req.body;

  if (!name) {
    return res.status(400).json({ error: 'Client name required' });
  }

  try {
    const result = await runScript('add-client.sh', name, maxIp, maxGb);
    res.json({ success: result.success, message: result.output });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// WireGuard - Remove client
app.delete('/api/wireguard/clients/:name', authenticateToken, async (req, res) => {
  const { name } = req.params;

  try {
    const result = await runScript('remove-client.sh', name);
    res.json({ success: result.success, message: result.output });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// WireGuard - Get QR code
app.get('/api/wireguard/clients/:name/qr', authenticateToken, (req, res) => {
  const { name } = req.params;
  const qrPath = `/etc/wireguard/clients/${name}/${name}.png`;

  if (fs.existsSync(qrPath)) {
    res.sendFile(qrPath);
  } else {
    res.status(404).json({ error: 'QR code not found' });
  }
});

// SSH - Add user
app.post('/api/ssh/users', authenticateToken, async (req, res) => {
  const { username, password = '', days = '30', maxIp = '2', maxGb = '100' } = req.body;

  if (!username) {
    return res.status(400).json({ error: 'Username required' });
  }

  try {
    const result = await runScript('add-ssh-user.sh', username, password, days, maxIp, maxGb);
    res.json({ success: result.success, message: result.output });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// SSH - Remove user
app.delete('/api/ssh/users/:username', authenticateToken, async (req, res) => {
  const { username } = req.params;

  try {
    const result = await runScript('remove-ssh-user.sh', username);
    res.json({ success: result.success, message: result.output });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Xray - Add user
app.post('/api/xray/users', authenticateToken, async (req, res) => {
  const { name, maxIp = '2', maxGb = '100' } = req.body;

  if (!name) {
    return res.status(400).json({ error: 'User name required' });
  }

  try {
    const result = await runScript('add-xray-user.sh', name, maxIp, maxGb);
    res.json({ success: result.success, message: result.output });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Xray - Remove user
app.delete('/api/xray/users/:name', authenticateToken, async (req, res) => {
  const { name } = req.params;

  try {
    const result = await runScript('remove-xray-user.sh', name);
    res.json({ success: result.success, message: result.output });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Limits - Check
app.get('/api/limits', authenticateToken, async (req, res) => {
  try {
    const result = await runScript('check-limits.sh');
    res.json({ success: result.success, data: result.output });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Backup - Create manual backup
app.post('/api/backup', authenticateToken, async (req, res) => {
  try {
    const result = await runScript('backup.sh', 'manual');
    res.json({ success: result.success, message: result.output });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Backup - List backups
app.get('/api/backup/list', authenticateToken, (req, res) => {
  const backupDir = '/var/backups/vpn';
  
  try {
    if (!fs.existsSync(backupDir)) {
      return res.json({ success: true, backups: [] });
    }

    const files = fs.readdirSync(backupDir)
      .filter(f => f.startsWith('vpn_backup_') && f.endsWith('.tar.gz'))
      .map(f => {
        const stat = fs.statSync(path.join(backupDir, f));
        return {
          name: f,
          size: stat.size,
          date: stat.mtime,
          path: path.join(backupDir, f)
        };
      })
      .sort((a, b) => b.date - a.date);

    res.json({ success: true, backups: files });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Backup - Download
app.get('/api/backup/download/:filename', authenticateToken, (req, res) => {
  const { filename } = req.params;
  const backupPath = path.join('/var/backups/vpn', filename);

  if (!fs.existsSync(backupPath) || !filename.startsWith('vpn_backup_')) {
    return res.status(404).json({ error: 'Backup not found' });
  }

  res.download(backupPath);
});

// Services - Restart
app.post('/api/services/restart/:service', authenticateToken, async (req, res) => {
  const { service } = req.params;
  
  let command;
  switch (service) {
    case 'wireguard':
      command = 'sudo systemctl restart wg-quick@wg0';
      break;
    case 'ssh':
      command = 'sudo systemctl restart ssh dropbear stunnel4 ssh-ws';
      break;
    case 'xray':
      command = 'sudo systemctl restart xray';
      break;
    case 'all':
      command = 'sudo systemctl restart wg-quick@wg0 ssh dropbear xray';
      break;
    default:
      return res.status(400).json({ error: 'Invalid service' });
  }

  try {
    await execPromise(command);
    res.json({ success: true, message: `${service} restarted successfully` });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Serve frontend
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Start server
app.listen(PORT, () => {
  console.log(`VPN Web Dashboard (wrwb Store) running on port ${PORT}`);
  console.log(`Default login: admin / admin`);
  console.log(`Change password immediately after first login!`);
});
