# Changelog v3.1 — Bug Fixes & Small Improvements (wrwb Store)

Date: 13 October 2026 / Tanggal: 13 Oktober 2026 / 日期：2026年10月13日
Made by **wrwb Store** / Dibuat oleh **wrwb Store** / 由 **wrwb Store** 打造

## Summary / Ringkasan / 概述

Version 3.1 is a **minor maintenance release** on top of v3.0. It contains **bug fixes,
security hardening, and small usability improvements** — no new major features and
no breaking changes. Fully backward compatible with v3.0.

Versi 3.1 adalah **rilis pemeliharaan minor** di atas v3.0. Berisi **perbaikan bug,
penguatan keamanan, dan peningkatan kecil kegunaan** — tanpa fitur besar baru dan
tanpa perubahan yang merusak. Kompatibel penuh dengan v3.0.

v3.1 是 v3.0 之上的**小型维护版本**。包含**错误修复、安全加固和小幅易用性改进**——
无重大新功能、无破坏性更改。与 v3.0 完全向后兼容。

---

## What's Fixed & Improved / Yang Diperbaiki & Ditingkatkan / 修复与改进内容

### 1. **🐛 Backup Aborts Early on Low Disk Space (`backup.sh`)**

**Problem / Masalah / 问题:**
- `backup.sh` could start a backup even when the disk was almost full, producing a
  partial/corrupt `.tar.gz` archive.
- `backup.sh` bisa memulai backup walau disk hampir penuh, menghasilkan arsip
  `.tar.gz` yang tidak lengkap/rusak.
- 磁盘几乎已满时 `backup.sh` 仍会开始备份，生成不完整/损坏的 `.tar.gz` 文件。

**Fix / Perbaikan / 修复:**
- Added a pre-flight disk-space check: backup aborts **before doing any work** when
  less than **100MB** is free on `/var/backups/vpn`.
- Menambahkan pemeriksaan ruang disk di awal: backup dibatalkan **sebelum bekerja**
  bila ruang bebas di `/var/backups/vpn` kurang dari **100MB**.
- 增加备份前磁盘空间检查：当 `/var/backups/vpn` 可用空间不足 **100MB** 时，
  在**执行任何操作之前**中止备份。
- Trilingual error message + hint to clean old backups.
- Pesan error trilingual + saran membersihkan backup lama.
- 三语错误提示 + 清理旧备份建议。

---

### 2. **🔒 Web Dashboard: Rate Limiting + Input Validation (`server.js`)**

**Problem / Masalah / 问题:**
- Login and user-creation API endpoints had no brute-force protection, and user
  input was passed to shell scripts with minimal validation.
- Endpoint login dan pembuatan user tidak punya proteksi brute-force, dan input
  user diteruskan ke skrip shell dengan validasi minimal.
- 登录和用户创建接口没有防暴力破解保护，用户输入几乎未经验证就传给 shell 脚本。

**Fix / Perbaikan / 修复:**
- Added a lightweight in-memory **rate limiter** (no new dependency):
  - `POST /api/login` → max **10 requests/minute per IP** (HTTP 429 + `Retry-After` header when exceeded).
  - `POST /api/wireguard/clients`, `/api/ssh/users`, `/api/xray/users` → max **30 requests/minute per IP**.
- Menambahkan **rate limiter** ringan di memori (tanpa dependensi baru):
  - `POST /api/login` → maks **10 permintaan/menit per IP** (HTTP 429 + header `Retry-After` bila melebihi).
  - Endpoint tambah user/client → maks **30 permintaan/menit per IP**.
- 增加轻量内存**限流**（无新增依赖）：
  - `POST /api/login` → 每 IP 每分钟最多 **10 次请求**（超限返回 HTTP 429 + `Retry-After` 头）。
  - 用户/客户端创建接口 → 每 IP 每分钟最多 **30 次请求**。
- Added `isValidName()` whitelist validator: names must match
  `^[a-zA-Z0-9_-]{1,32}$` (same rule as `validate_client_name` in `lib/common.sh`).
  Invalid names are rejected with HTTP 400 and a clear message.
- Menambahkan validator whitelist `isValidName()`: nama harus cocok
  `^[a-zA-Z0-9_-]{1,32}$` (aturan sama seperti `validate_client_name` di `lib/common.sh`).
  Nama tidak valid ditolak dengan HTTP 400 dan pesan yang jelas.
- 增加 `isValidName()` 白名单校验：名称必须符合 `^[a-zA-Z0-9_-]{1,32}$`
  （与 `lib/common.sh` 中 `validate_client_name` 规则一致）。
  非法名称返回 HTTP 400 并附清晰提示。
- Hardened internal `runScript()` helper: only `*.sh` filenames and safe argument
  characters are allowed (defense against command injection).
- Memperkuat helper internal `runScript()`: hanya nama file `*.sh` dan karakter
  argumen yang aman diizinkan (pertahanan terhadap command injection).
- 加固内部 `runScript()`：仅允许 `*.sh` 文件名和安全参数字符（防范命令注入）。

---

### 3. **🤖 Telegram Bot: Longer Timeout + Clearer Message (`telegram-bot.py`)**

**Problem / Masalah / 问题:**
- Long operations (first backup, package installs) could exceed the 60-second timeout,
  and the error message (`Command timeout`) gave no guidance.
- Operasi lama (backup pertama, instalasi paket) bisa melebihi timeout 60 detik,
  dan pesan error (`Command timeout`) tidak memberi petunjuk.
- 长时间操作（首次备份、软件包安装）可能超过 60 秒超时，错误信息
  （`Command timeout`）没有给出任何指引。

**Fix / Perbaikan / 修复:**
- Timeout increased from **60s → 120s**.
- Timeout dinaikkan dari **60 dtk → 120 dtk**.
- 超时从 **60 秒 → 120 秒**。
- Timeout message now explains the situation:
  `Command timed out after 120s (server may be busy, try again).`
- Pesan timeout kini menjelaskan situasinya dan saran mencoba lagi.
- 超时信息现在会说明情况并建议重试。

---

### 4. **🎨 Web Dashboard UI: Validation + Clearer Confirmations (`index.html`)**

**Problem / Masalah / 问题:**
- Invalid client names were only rejected by the server (round-trip delay), and the
  restart confirmation dialog did not warn about connection interruption.
- Nama client tidak valid baru ditolak server (butuh round-trip), dan dialog
  konfirmasi restart tidak memperingatkan gangguan koneksi.
- 非法客户端名称要等服务器返回才被拒绝（多一次往返），重启确认框也没有
  提示连接会中断。

**Fix / Perbaikan / 修复:**
- Added client-side name validation in `addWgClient()` using the same
  `^[a-zA-Z0-9_-]{1,32}$` rule, with an instant error message before any request.
- Menambahkan validasi nama di sisi client pada `addWgClient()` memakai aturan
  yang sama `^[a-zA-Z0-9_-]{1,32}$`, dengan pesan error instan sebelum request.
- 在 `addWgClient()` 增加客户端名称校验（规则相同），请求发出前即时提示错误。
- Restart confirmation now warns:
  `Restart "<service>"? This may briefly interrupt VPN connections.`
- Konfirmasi restart kini memperingatkan kemungkinan gangguan koneksi VPN.
- 重启确认框现在会提示可能短暂中断 VPN 连接。
- Added "please wait" progress hints while creating clients and restarting services.
- Menambahkan petunjuk progres "please wait" saat membuat client dan restart service.
- 在创建客户端和重启服务时增加 "please wait" 进度提示。

---

### 5. **📝 Stronger Password Policy + Troubleshooting Docs (`server.js`, `README-v3.md`)**

**Problem / Masalah / 问题:**
- `POST /api/change-password` accepted passwords of any length, and the new v3.1
  behaviors (disk-space abort, HTTP 429, name validation, 120s bot timeout) were
  not documented.
- `POST /api/change-password` menerima password sepanjang apapun, dan perilaku
  baru v3.1 (batal disk penuh, HTTP 429, validasi nama, timeout bot 120 dtk) belum
  didokumentasikan.
- `POST /api/change-password` 接受任意长度密码，且 v3.1 新行为（磁盘不足中止、
  HTTP 429、名称校验、Bot 120 秒超时）尚未写入文档。

**Fix / Perbaikan / 修复:**
- `POST /api/change-password` now requires the new password to be at least
  **8 characters** (HTTP 400 otherwise), plus rate limiting (10 req/min per IP).
- `POST /api/change-password` kini mewajibkan password baru minimal **8 karakter**
  (jika tidak → HTTP 400), plus rate limiting (10 req/menit per IP).
- `POST /api/change-password` 现在要求新密码至少 **8 个字符**（否则 HTTP 400），
  并增加限流（每 IP 每分钟 10 次）。
- `README-v3.md` troubleshooting section extended with 4 new entries:
  - Backup aborted: insufficient disk space (how to clean + re-run).
  - HTTP 429 Too Many Requests (limits explained).
  - Invalid name error (rule explained with examples).
  - Telegram command timed out after 120s (what to check).
- Bagian troubleshooting `README-v3.md` ditambah 4 entri baru untuk keempat
  perilaku di atas (cara membersihkan disk, arti limit, aturan nama, pengecekan
  saat timeout).
- `README-v3.md` 故障排查章节新增 4 条，分别对应上述新行为（含清理磁盘方法、
  限流说明、命名规则示例、超时后检查步骤）。

---

## Files Changed / File yang Berubah / 已更改文件

```
backup.sh                        (disk-space pre-check, trilingual)
web-dashboard/server.js          (rate limiter, isValidName, runScript hardening,
                                  password min-length)
telegram-bot.py                  (timeout 60s -> 120s, clearer message)
web-dashboard/public/index.html  (client-side validation, clearer restart confirm,
                                  progress hints)
README-v3.md                     (4 new troubleshooting entries for v3.1)
CHANGELOG-v3.1.md                (this file)
```

---

## Compatibility / Kompatibilitas / 兼容性

**No breaking changes. / Tidak ada perubahan yang merusak. / 无破坏性更改。**
- All v3.0 features keep working as before:
  - Telegram Bot commands unchanged.
  - Web Dashboard API request/response format unchanged (only stricter validation).
  - Backup file format unchanged (`vpn_backup_<type>_<timestamp>.tar.gz`).
  - Menu options 18–22 unchanged.
- All v1.4 features (WireGuard/SSH/Xray/OpenVPN/Shadowsocks, limits, trilingual)
  remain intact.

---

## Upgrade Instructions / Instruksi Upgrade / 升级说明

```bash
cd vpn
git pull origin main

# No new dependencies, no new services, no config migration needed.
# Restart the dashboard + bot to pick up the fixes:
sudo systemctl restart vpn-web-dashboard
sudo systemctl restart vpn-telegram-bot

# Verify:
systemctl status vpn-web-dashboard vpn-telegram-bot
tail -f /var/log/vpn-backup.log   # next backup will use the disk-space check
```

---

## Verification / Verifikasi / 验证

- ✅ `backup.sh` aborts before doing work when free space < 100MB (trilingual message).
- ✅ Login endpoint returns HTTP 429 after 10 req/min per IP (with `Retry-After`).
- ✅ Invalid names (`phone andi!`, empty, >32 chars) rejected with HTTP 400.
- ✅ Telegram bot waits up to 120s for slow operations.
- ✅ Web UI validates client name instantly + warns before restart.
- ✅ Password change requires min 8 characters.
- ✅ README-v3.md documents all new v3.1 behaviors.
- ✅ No new npm/pip dependencies added.

---

Made by **wrwb Store** — v3.1 (Bug fixes & small improvements, no breaking changes)
Dibuat oleh **wrwb Store** — v3.1 (Perbaikan bug & peningkatan kecil, tanpa breaking changes)
由 **wrwb Store** 打造 — v3.1（错误修复与小幅改进，无破坏性更改）
