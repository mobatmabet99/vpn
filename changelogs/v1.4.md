# Changelog v1.4 — Trilingual EN/ID/ZH, Default English (wrwb Store)

Date: 13 October 2026 / Tanggal: 13 Oktober 2026 / 日期：2026年10月13日
Made by **wrwb Store** / Dibuat oleh **wrwb Store** / 由 **wrwb Store** 打造

## Summary / Ringkasan / 概述

Version 1.4 adds **Simplified Chinese (简体中文)** alongside English (default)
and Indonesia — still a **single codebase, no duplicated scripts**.

Versi 1.4 menambahkan **Bahasa Mandarin Sederhana (简体中文)** di samping
English (default) dan Indonesia — tetap **satu codebase, tanpa duplikasi skrip**.

v1.4 新增**简体中文**，与默认英文、印尼语并存 — 依然**单代码库，无重复脚本**。

- Install prompt is now: `1) English (default)` / `2) Indonesia` / `3) 中文`.
  Just press **Enter** (or skip) = automatic **English**.
- Prompt instalasi kini: `1) English (default)` / `2) Indonesia` / `3) 中文`.
  Tekan **Enter** (atau skip) = otomatis **English**.
- 安装提示现为：`1) English (default)` / `2) Indonesia` / `3) 中文`。
  直接按**回车**（或跳过）= 自动**英文**。

## What's New / Poin Update / 更新内容

1. **Trilingual core `lib/lang.sh` (v1.4)**
   - Helper is now `T "English" "Indonesia" "中文"` (3rd arg = Simplified Chinese).
   - Old 2-arg calls still work: Chinese falls back to English.
   - `VPN_LANG` is now `en` / `id` / `zh`, saved in `/etc/vpn/lang`
     (`--lang en|id|zh` CLI > `VPN_LANG` env > file > default `en`).
   - New `lang_is_zh()` + `lang_label()` prints `语言：简体中文` for zh.
2. **All 22 scripts converted to trilingual (no duplication)**
   - `install.sh` (3-language prompt + `--lang en|id|zh` + `--help` in 3 languages),
     `menu.sh` (0-17, item 17 = switch EN/ID/ZH), `add-client.sh`,
     `remove-client.sh`, `add-ssh-user.sh`, `remove-ssh-user.sh`,
     `add-xray-user.sh`, `remove-xray-user.sh`, `list-clients.sh`, `show-qr.sh`,
     `check-limits.sh`, `status.sh`, `uninstall.sh`.
   - Libraries: `lib/common.sh` (auto-loads lang), `lib/system.sh`,
     `lib/wireguard.sh`, `lib/ssh.sh`, `lib/xray.sh`, `lib/openvpn.sh`,
     `lib/shadowsocks.sh`, `lib/limits.sh`.
3. **Docs: English default, Indonesia + Chinese kept**
   - New `README.zh.md` (Simplified Chinese, full — same coverage as `README.en.md`).
   - `README.en.md` + `README.md` gain a 3-language section linking all three.
4. **Portability kept (Debian 13 & Ubuntu 26.04 smooth run)**
   - Still `awk`/`sed`-only parsing (no functional `grep -oP`).
   - All 22 files pass `bash -n` with zero errors.
5. **v1.2 / v1.3 features kept intact (wrwb Store)**
   - Default limit 2 IPs & 100 GB, 5-minute auto-suspend + auto-clear sessions.
   - `vpn-limits` systemd monitor every 60 seconds.
   - Branding `wrwb Store` kept everywhere.

## Usage / Cara Pakai / 用法

```bash
# Interactive (asks language, default English / 交互，询问语言，默认英文)
sudo ./install.sh

# Non-interactive English (default)
sudo ./install.sh --yes

# Non-interactive Indonesian / Non-interaktif Indonesia
sudo ./install.sh --lang id --yes

# Non-interactive Chinese / Non-interaktif Mandarin / 中文非交互
sudo ./install.sh --lang zh --yes
VPN_LANG=zh sudo ./install.sh --yes

# Switch later / Ganti nanti / 稍后切换
sudo ./menu.sh          # → 17) Switch language / Ganti bahasa / 切换语言
sudo ./menu.sh --lang zh
echo zh | sudo tee /etc/vpn/lang
```

## Compatibility / Kompatibilitas / 兼容性

- Ubuntu 20.04 / 22.04 / 24.04 / 26.04 LTS, Debian 10 / 11 / 12 / 13,
  CentOS / Rocky / AlmaLinux 8 / 9, RHEL 8/9, Fedora.
- `awk`/`sed`-only parsing (no `grep -P`), safe on Alpine/minimal RHEL
  and fresh Debian 13 / Ubuntu 26 installs.

## Verification / Verifikasi / 验证

```bash
for f in *.sh lib/*.sh; do bash -n "$f" && echo "OK: $f"; done
# expect 22x OK, zero FAIL / harap 22x OK, nol FAIL / 应 22 个 OK，0 个 FAIL

# no functional grep -oP left (comments only)
grep -rn "grep -oP" *.sh lib/*.sh
```
