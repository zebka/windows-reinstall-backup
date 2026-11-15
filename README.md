# windows-reinstall-backup

[فارسی (Persian)](README.fa.md)

Interactive PowerShell backup & restore for Windows reinstall: save your user folders, browser bookmarks, Wi-Fi passwords, and Outlook data before reinstalling Windows or doing a fresh install (e.g. Windows 7 to Windows 10 upgrade), then restore them afterwards.

> **Trust & safety:** The `.bat` launchers run PowerShell with `-ExecutionPolicy Bypass` for this run only; they do not change your system execution policy. The full source code is available to review in this repository.

## Screenshot

<!-- TODO: Add a screenshot or GIF of the interactive menu and progress bar -->

## What it backs up
- User folders: `Desktop`, `Documents`, `Downloads`, `Pictures`, `Videos`, `Music` (including OneDrive folders when present)
- Browser data: bookmarks/profile data for Chrome, Edge, Brave, and Firefox
- Outlook data (`PST/OST`) and Sticky Notes
- System info: Wi-Fi profiles/password export, installed programs list, printers, IP config, mapped network drives
- Optional: any custom folder you choose

## Requirements
- Windows 7 SP1 to Windows 11
- PowerShell 2.0 or later
- Administrator access (scripts request elevation automatically)
- An external drive or a drive other than `C:` with enough free space for backup
- Built-in Windows tools used by the scripts: `robocopy`, `netsh`

## How to use

### 1) Download
- **Option A:** On GitHub, click **Code → Download ZIP**, then extract the files. (You can also download the ZIP from the [Releases](https://github.com/zebka/windows-reinstall-backup/releases) page.)
- **Option B:** Clone the repo:
  ```bash
  git clone https://github.com/zebka/windows-reinstall-backup.git
  ```

### 2) Backup (before reinstall)
1. Connect an external drive.
2. Run `Run-Backup.bat` (or `Backup-BeforeReinstall.ps1`).
3. Select what to back up in the interactive menu and continue.
4. The backup will be saved in a folder like `Backup_<PC>_<timestamp>` on the destination drive.

### 3) Restore (after reinstall)
1. After reinstalling Windows, copy/download this repo again (if needed) and connect the backup drive.
2. Run `Run-Restore.bat` (or `Restore-AfterReinstall.ps1`).
3. Choose the backup folder and map backup users to Windows users if asked.
4. Select items to restore and continue.

## Notes
- This is for backing up user data/settings, **not** a full disk/system image.
- Existing files are generally not overwritten during restore (browser bookmark files are renamed to `*.before-restore` before copying).
- Some restored items (e.g. Outlook data, Sticky Notes, system info, custom folders) may be placed in `Documents\Restored-Backup` for manual use/import.
- Backups may contain sensitive data (browser data, exported Wi-Fi passwords/profiles, Outlook files). Keep the backup drive in a safe place.

## License
[MIT](LICENSE)
