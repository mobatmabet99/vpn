# Changelog v1.3 — Bilingual EN/ID, Default English (wrwb Store)

Date: 13 October 2026 / Tanggal: 13 Oktober 2026
Made by **wrwb Store** / Dibuat oleh **wrwb Store**

## Summary / Ringkasan

Version 1.3 adds **bilingual support: English (default) / Indonesia** with a
**single codebase — no duplicated scripts**.

Versi 1.3 menambahkan **dukungan dua bahasa: English (default) / Indonesia**
dengan **satu codebase — tanpa duplikasi skrip**.

- At install time you are asked: `1) English (default)` / `2) Indonesia`.
  Just press **Enter** (or skip) = automatic **English**.
- Saat instalasi Anda ditanya: `1) English (default)` / `2) Indonesia`.
  Tekan **Enter** (atau skip) = otomatis **English**.

## What's New / Poin Update

1. **New module `lib/lang.sh` (bilingual core)**
   - Inline helper `T "English" "Indonesia"` (default `en`).
   - Priority: `--lang en|id` CLI > `VPN_LANG` env > `/etc/vpn/lang` file > default `en`.
   - Saved choice in `/etc/vpn/lang` (`en` / `id`), used by all scripts.
   - Menu `17) Switch language` in `menu.sh` + `menu.sh --lang en|id`.
   - `uninstall.sh` removes `/etc/vpn/lang`.
2. **All 22 scripts converted to bilingual (no duplication)**
   - `install.sh` (language prompt + `--lang` flag + `--help` in both languages),
     `menu.sh` (0-17), `add-client.sh`, `remove-client.sh`,
     `add-ssh-user.sh`, `remove-ssh-user.sh`, `add-xray-user.sh`,
     `remove-xray-user.sh`, `list-clients.sh`, `show-qr.sh`,
     `check-limits.sh`, `status.sh`, `uninstall.sh`.
   - Libraries: `lib/common.sh` (auto-loads lang), `lib/system.sh`,
     `lib/wireguard.sh`, `lib/ssh.sh`, `lib/xray.sh`, `lib/openvpn.sh`,
     `lib/shadowsocks.sh`, `lib/limits.sh`.
   - Library headers standardized to English-first + `Branding: wrwb Store`.
3. **Docs: English default, Indonesian kept**
   - New `README.en.md` (English, default). `README.md` stays Indonesian
     + new `🌐 Language / Bahasa` section linking both ways.
4. **Portability fixes (Debian 13 & Ubuntu 26.04 smooth run)**
   - Replaced non-portable `grep -oP` with `awk`/`sed` in `lib/common.sh`
     (`get_public_ip`) and `lib/limits.sh` (`ss` PID + Xray log parsing).
   - Only remaining `grep -oP` hits are comments explaining the fix.
   - All 22 files pass `bash -n` with zero errors.
5. **v1.2 features kept intact (wrwb Store)**
   - Default limit 2 IPs & 100 GB, 5-minute auto-suspend + auto-clear sessions.
   - `vpn-limits` systemd monitor every 60 seconds.
   - Branding `wrwb Store` kept in banners, menus, and service descriptions.

## Usage / Cara Pakai

```bash
# Interactive (asks language, default English)
sudo ./install.sh

# Non-interactive English (default)
sudo ./install.sh --yes

# Non-interactive Indonesian
sudo ./install.sh --lang id --yes
VPN_LANG=id sudo ./install.sh --yes

# Switch later
sudo ./menu.sh          # → 17) Switch language
sudo ./menu.sh --lang id
echo en | sudo tee /etc/vpn/lang
```

## Compatibility / Kompatibilitas

- Ubuntu 20.04 / 22.04 / 24.04 / 26.04 LTS, Debian 10 / 11 / 12 / 13,
  CentOS / Rocky / AlmaLinux 8 / 9, RHEL 8/9, Fedora.
- New: `awk`/`sed`-only parsing (no `grep -P`), safe on Alpine/minimal RHEL
  and fresh Debian 13 / Ubuntu 26 installs.

## Verification / Verifikasi

```bash
for f in *.sh lib/*.sh; do bash -n "$f" && echo "OK: $f"; done
# expect 22x OK, zero FAIL

# no functional grep -oP left (comments only)
grep -rn "grep -oP" *.sh lib/*.sh
```
