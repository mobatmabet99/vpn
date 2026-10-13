# Changelog v3.2 — README Restructure: OS & Specs on Top (wrwb Store)

Date: 13 October 2026 / Tanggal: 13 Oktober 2026 / 日期：2026年10月13日
Made by **wrwb Store** / Dibuat oleh **wrwb Store** / 由 **wrwb Store** 打造

## Summary / Ringkasan / 概述

Version 3.2 is a **documentation-only release**. It restructures the top of all three
README files: OS support and minimum VPS specs move to a dedicated section right at
the top (above the language section), the OS row is removed from the Main Features
table (no more duplication), and the old "New in v1.x" highlight blockquotes are
removed so the header stays clean.

Versi 3.2 adalah **rilis khusus dokumentasi**. Susunan bagian atas ketiga file README
dirapikan: dukungan OS dan spesifikasi minimum VPS dipindah ke section khusus tepat
di atas (di atas section bahasa), baris OS dihapus dari tabel Fitur Utama (tidak ada
lagi duplikasi), dan blockquote highlight lama "Baru di v1.x" dihapus agar header
tetap bersih.

v3.2 是**纯文档版本**。重排了三个 README 文件的顶部：操作系统支持和 VPS 最低配置
移到顶部专用章节（语言章节之上），主功能表格中的系统行被删除（不再重复），
旧的 "v1.x 新特性" 高亮引用块被删除，头部保持简洁。

---

## What Changed / Yang Berubah / 更改内容

### 1. **New top section: OS Support & Minimum Requirements**

Added right after the intro header in all three READMEs, before the language section:

- `README.md` → `## 🖥️ Dukungan OS & Spesifikasi Minimum`
- `README.en.md` → `## 🖥️ OS Support & Minimum Requirements`
- `README.zh.md` → `## 🖥️ 系统支持与最低配置`

Contents (same in all three languages):
- Supported OS: Ubuntu 20.04 / 22.04 / 24.04 / 26.04 LTS, Debian 10 / 11 / 12 / 13,
  CentOS / Rocky / AlmaLinux 8 / 9, RHEL 8/9, Fedora.
- Minimum VPS specs: 1 vCPU, 512 MB RAM (1 GB+ recommended for v3 features),
  5 GB free disk (10 GB+ with automatic backups), public IP + internet + TUN
  device (`/dev/net/tun`), root / `sudo` access.

### 2. **Removed OS row from the Main Features table**

The `🖥️ OS Support / Dukungan OS / 系统支持` row is deleted from the features table
in all three READMEs because the same information now lives in the new top section.
No information is lost — only the duplication is removed.

### 3. **Removed old "New in v1.x" highlight blockquotes**

Deleted from the header area of all three READMEs:
- v1.4 trilingual highlight, v1.3 bilingual highlight, v1.2 limits highlight.
- Full history remains available in `CHANGELOG-v1.2.md`, `CHANGELOG-v1.3.md`,
  `CHANGELOG-v1.4.md` — nothing is deleted from the changelog files.

---

## Files Changed / File yang Berubah / 已更改文件

```
README.md          (header restructured, new OS+specs section, OS row removed)
README.en.md       (header restructured, new OS+specs section, OS row removed)
README.zh.md       (header restructured, new OS+specs section, OS row removed)
CHANGELOG-v3.2.md  (this file)
```

No code changes. No functional changes. Documentation only.

---

## Compatibility / Kompatibilitas / 兼容性

**No breaking changes. / Tidak ada perubahan yang merusak. / 无破坏性更改。**
All scripts, configs, and v3/v3.1 features work exactly as before.

---

## Upgrade Instructions / Instruksi Upgrade / 升级说明

```bash
cd vpn
git pull origin main
```

No action needed — documentation update only.

---

Made by **wrwb Store** — v3.2 (README restructure, docs only)
Dibuat oleh **wrwb Store** — v3.2 (Restrukturisasi README, hanya dokumentasi)
由 **wrwb Store** 打造 — v3.2（README 重构，仅文档）
