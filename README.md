# windows-reinstall-backup

Simple interactive PowerShell scripts to back up your important user data before reinstalling Windows, and restore it afterwards.

اسکریپت‌های تعاملی و سادهٔ PowerShell برای بکاپ گرفتن از داده‌های مهم کاربر قبل از نصب مجدد ویندوز و بازیابی آن‌ها بعد از نصب.

## What it backs up / چه چیزهایی بکاپ می‌شود
- User folders: `Desktop`, `Documents`, `Downloads`, `Pictures`, `Videos`, `Music` (including OneDrive folders when present)
- Browser data: bookmarks/profile data for Chrome, Edge, Brave, and Firefox
- Outlook data (`PST/OST`) and Sticky Notes
- System info: Wi-Fi profiles/password export, installed programs list, printers, IP config, mapped network drives
- Optional: any custom folder you choose

- پوشه‌های کاربر: `Desktop`, `Documents`, `Downloads`, `Pictures`, `Videos`, `Music` (در صورت وجود، پوشه‌های OneDrive هم شامل می‌شود)
- داده‌های مرورگر: بوکمارک/داده‌های پروفایل Chrome، Edge، Brave و Firefox
- داده‌های Outlook (`PST/OST`) و Sticky Notes
- اطلاعات سیستم: خروجی پروفایل‌ها/رمزهای Wi-Fi، لیست برنامه‌های نصب‌شده، پرینترها، تنظیمات IP و درایوهای شبکه
- اختیاری: هر پوشهٔ سفارشی که خودتان انتخاب کنید

## Requirements
- Windows with PowerShell (scripts use built-in tools like `robocopy` and `netsh`)
- Administrator access (scripts request elevation automatically)
- An external drive or a drive other than `C:` with enough free space for backup

## How to use

### 1) Download
- **Option A:** On GitHub, click **Code → Download ZIP**, then extract the files.
- **Option B:** Clone the repo:
  ```bash
  git clone https://github.com/zebka/windows-reinstall-backup.git
  ```

### 2) Backup (before reinstall)
1. Connect an external drive.
2. Run `Run-Backup.bat` (or `Backup-BeforeReinstall.ps1`).
3. Select what to back up in the menu and continue.
4. The backup will be saved in a folder like `Backup_<PC>_<timestamp>` on the destination drive.

### 3) Restore (after reinstall)
1. After reinstalling Windows, copy/download this repo again (if needed) and connect the backup drive.
2. Run `Run-Restore.bat` (or `Restore-AfterReinstall.ps1`).
3. Choose the backup folder and map backup users to Windows users if asked.
4. Select items to restore and continue.

## Notes / نکات
- This is for backing up user data/settings, **not** a full disk/system image.
- Existing files are generally not overwritten during restore (browser bookmark files are renamed to `*.before-restore` before copying).
- Some restored items (e.g. Outlook data, Sticky Notes, system info, custom folders) may be placed in `Documents\Restored-Backup` for manual use/import.
- The backup may contain sensitive data (browser data, Wi-Fi passwords/profiles, Outlook files). Keep the backup drive in a safe place.

- این ابزار برای بکاپ داده‌ها/تنظیمات کاربر است، **نه** ایمیج کامل دیسک/سیستم.
- هنگام بازیابی، معمولاً فایل‌های موجود بازنویسی نمی‌شوند (فایل‌های بوکمارک مرورگر قبل از کپی به `*.before-restore` تغییر نام می‌دهند).
- برخی موارد بازیابی‌شده (مثل داده‌های Outlook، Sticky Notes، اطلاعات سیستم و پوشه‌های سفارشی) ممکن است برای استفاده/ایمپورت دستی در `Documents\Restored-Backup` قرار بگیرند.
- بکاپ ممکن است شامل داده‌های حساس باشد (داده‌های مرورگر، رمز/پروفایل Wi-Fi، فایل‌های Outlook). درایو بکاپ را در جای امن نگه دارید.
