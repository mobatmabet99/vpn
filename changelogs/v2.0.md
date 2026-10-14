# Changelog v2 — Bug Fixes & Documentation Corrections (wrwb Store)

Date: 13 October 2026 / Tanggal: 13 Oktober 2026 / 日期：2026年10月13日
Made by **wrwb Store** / Dibuat oleh **wrwb Store** / 由 **wrwb Store** 打造

## Summary / Ringkasan / 概述

Version 2 is a **bug fix release** focusing on correcting **documentation errors** 
found in all README files and CHANGELOG-v1.4.md. No functional code changes.

Versi 2 adalah **rilis perbaikan bug** yang fokus pada koreksi **kesalahan dokumentasi** 
di semua file README dan CHANGELOG-v1.4.md. Tidak ada perubahan kode fungsional.

v2 是一个**错误修复版本**，专注于纠正所有 README 文件和 CHANGELOG-v1.4.md 中的**文档错误**。无功能代码更改。

---

## What's Fixed / Yang Diperbaiki / 修复内容

### 1. **Escape Character Errors in Markdown (9 fixes / 9 perbaikan / 9 处修复)**

**Problem / Masalah / 问题:**
- Pipe characters (`|`) were incorrectly escaped with backslash (`\|`) inside inline 
  code blocks and command examples across all three README files.
- Karakter pipe (`|`) salah di-escape dengan backslash (`\|`) di dalam inline code 
  dan contoh perintah di ketiga file README.
- 在所有三个 README 文件的内联代码和命令示例中，管道字符 (`|`) 被错误地用反斜杠转义 (`\|`)。

**Fixed Files / File yang Diperbaiki / 已修复文件:**

#### README.en.md (3 fixes):
- ❌ `` `ss -lnup \| grep 51820` `` → ✅ `` `ss -lnup | grep 51820` ``
- ❌ `` `echo zh \| sudo tee /etc/vpn/lang` `` → ✅ `` `echo zh | sudo tee /etc/vpn/lang` ``
- ❌ `--lang en\|id\|zh` in table → ✅ `--lang en|id|zh`

#### README.md (Indonesian / Indonesia / 印尼语) (3 fixes):
- ❌ `` `ss -lnup \| grep 51820` `` → ✅ `` `ss -lnup | grep 51820` ``
- ❌ `` `echo id \| sudo tee /etc/vpn/lang` `` → ✅ `` `echo id | sudo tee /etc/vpn/lang` ``
- ❌ `--lang en\|id\|zh` in table → ✅ `--lang en|id|zh`

#### README.zh.md (Chinese / Mandarin / 中文) (3 fixes):
- ❌ `` `ss -lnup \| grep 51820` `` → ✅ `` `ss -lnup | grep 51820` ``
- ❌ `` `echo zh \| sudo tee /etc/vpn/lang` `` → ✅ `` `echo zh | sudo tee /etc/vpn/lang` ``
- ❌ `--lang en\|id\|zh` in table → ✅ `--lang en|id|zh`

**Impact / Dampak / 影响:**
- Users copying commands from documentation will now get correct syntax.
- Pengguna yang menyalin perintah dari dokumentasi sekarang mendapat sintaks yang benar.
- 从文档复制命令的用户现在将获得正确的语法。

---

### 2. **Wrong Release Date in CHANGELOG-v1.4.md (1 fix / 1 perbaikan / 1 处修复)**

**Problem / Masalah / 问题:**
- CHANGELOG-v1.4.md showed release date as **14 October 2026** instead of correct date.
- CHANGELOG-v1.4.md menampilkan tanggal rilis **14 Oktober 2026** padahal seharusnya beda.
- CHANGELOG-v1.4.md 显示发布日期为 **2026年10月14日**，但实际日期不同。

**Fixed / Diperbaiki / 已修复:**
- ❌ `Date: 14 October 2026 / Tanggal: 14 Oktober 2026 / 日期：2026年10月14日`
- ✅ `Date: 13 October 2026 / Tanggal: 13 Oktober 2026 / 日期：2026年10月13日`

---

## Files Changed / File yang Berubah / 已更改文件

```
CHANGELOG-v1.4.md  (1 line changed)
README.en.md       (3 lines changed)
README.md          (3 lines changed)
README.zh.md       (3 lines changed)

Total: 4 files changed, 10 insertions(+), 10 deletions(-)
```

---

## Verification / Verifikasi / 验证

All documentation errors found through comprehensive review:
- ✅ Checked all escape characters in markdown tables and code blocks
- ✅ Verified all dates in CHANGELOG files are correct
- ✅ Confirmed all GitHub links are valid
- ✅ Verified software versions are consistent (Xray v26.3.27, v2ray v5.53.0, Shadowsocks v1.25.0)
- ✅ Checked for common typos in English text
- ✅ No functional code changes (all `.sh` scripts unchanged)

Semua kesalahan dokumentasi ditemukan melalui review komprehensif:
- ✅ Memeriksa semua escape character di tabel markdown dan code block
- ✅ Memverifikasi semua tanggal di file CHANGELOG sudah benar
- ✅ Mengonfirmasi semua link GitHub valid
- ✅ Memverifikasi versi software konsisten (Xray v26.3.27, v2ray v5.53.0, Shadowsocks v1.25.0)
- ✅ Memeriksa typo umum di teks Bahasa Inggris
- ✅ Tidak ada perubahan kode fungsional (semua script `.sh` tidak berubah)

通过全面审查发现的所有文档错误：
- ✅ 检查了 markdown 表格和代码块中的所有转义字符
- ✅ 验证了 CHANGELOG 文件中的所有日期正确
- ✅ 确认了所有 GitHub 链接有效
- ✅ 验证了软件版本一致（Xray v26.3.27、v2ray v5.53.0、Shadowsocks v1.25.0）
- ✅ 检查了英文文本中的常见拼写错误
- ✅ 无功能代码更改（所有 `.sh` 脚本未更改）

---

## Compatibility / Kompatibilitas / 兼容性

**No breaking changes.** All v1.4 features remain intact:
- Trilingual support (EN/ID/ZH)
- Default limit 2 IPs & 100 GB
- 5-minute auto-suspend on multi-login
- All protocols: WireGuard, SSH VPN, Xray/V2Ray, OpenVPN, Shadowsocks

**Tidak ada perubahan yang merusak kompatibilitas.** Semua fitur v1.4 tetap utuh.

**无破坏性更改。** 所有 v1.4 功能保持不变。

---

## Upgrade Instructions / Instruksi Upgrade / 升级说明

No upgrade needed. This is a documentation-only fix.
If you want the corrected README files:

Tidak perlu upgrade. Ini hanya perbaikan dokumentasi.
Jika ingin file README yang sudah diperbaiki:

无需升级。这只是文档修复。
如果需要更正后的 README 文件：

```bash
cd vpn
git pull origin main
```

All existing installations continue to work without any changes.
Semua instalasi yang ada tetap berfungsi tanpa perubahan apapun.
所有现有安装无需任何更改即可继续工作。

---

Made by **wrwb Store** — v2 (Documentation fixes, no functional changes)
Dibuat oleh **wrwb Store** — v2 (Perbaikan dokumentasi, tanpa perubahan fungsional)
由 **wrwb Store** 打造 — v2（文档修复，无功能更改）
