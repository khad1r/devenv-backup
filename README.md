# WinGet Environment Backup & Restore

Automated PowerShell scripts to export WinGet-installed applications and optionally backup/restore matching AppData (`Roaming` and `Local`) configurations.

---

## Default Behavior
- **Default:** Backs up / restores **only** WinGet application packages (`winget export` / `winget import`).
- **Optional (`-IncludeAppData`):** Scans and packages matching AppData folders for installed applications.

---

## Files

- [`Backup-WinGetEnv.ps1`](./Backup-WinGetEnv.ps1): Exports installed WinGet packages to JSON, optionally stages matching AppData configs, and packages everything into a timestamped ZIP archive (`WinGet_Backup_YYYYMMDD_HHmm.zip`).
- [`Restore-WinGetEnv.ps1`](./Restore-WinGetEnv.ps1): Extracts the backup archive, reinstalls applications via `winget import`, and optionally restores AppData configurations.

---

## Usage Examples

### 1. Backup

* **Standard Backup (WinGet packages only - Fast & Light):**
  ```powershell
  .\Backup-WinGetEnv.ps1
  ```

* **Full Backup (WinGet packages + AppData settings):**
  ```powershell
  .\Backup-WinGetEnv.ps1 -IncludeAppData
  ```

* **Custom Output Directory:**
  ```powershell
  .\Backup-WinGetEnv.ps1 -OutputDirectory "D:\Backups" -IncludeAppData
  ```

---

### 2. Restore

* **Standard Restore (Reinstall packages only):**
  ```powershell
  .\Restore-WinGetEnv.ps1
  ```

* **Full Restore (Reinstall packages + Restore AppData settings):**
  ```powershell
  .\Restore-WinGetEnv.ps1 -IncludeAppData
  ```

* **Specify Backup Directory:**
  ```powershell
  .\Restore-WinGetEnv.ps1 -InputDirectory "D:\Backups" -IncludeAppData
  ```

---

## Tips & Automation

### Execution Policy Bypass
If Windows restricts script execution, run with `-ExecutionPolicy Bypass`:
```powershell
powershell -ExecutionPolicy Bypass -File .\Backup-WinGetEnv.ps1
# With AppData:
powershell -ExecutionPolicy Bypass -File .\Backup-WinGetEnv.ps1 -IncludeAppData
```

### Windows Task Scheduler (Weekly Automated Backup)
To schedule automatic backups every Sunday at 02:00 AM as Administrator:
```powershell
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSScriptRoot\Backup-WinGetEnv.ps1`""
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2am
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "WinGet-Weekly-Backup" -Action $Action -Trigger $Trigger -Principal $Principal -Description "Automated weekly WinGet backup."
```
