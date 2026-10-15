# DevEnv Backup & Restore (WinGet, NPM & AI Agent Tools)

Automated PowerShell scripts to export your entire Windows developer environment into a single portable ZIP archive:
- **WinGet Applications** (`winget export` / `winget import`)
- **Application Settings & AppData** (`Roaming` & `Local`)
- **Global Node/NPM Packages & NPX Tool Metadata**
- **AI Agent Skills, Rules & MCP (Model Context Protocol) Configs** (Antigravity/Gemini, Claude, Cursor, Windsurf, Copilot)

---

## Supported Components

| Component | Switch | Description | Default Output / Paths |
| :--- | :--- | :--- | :--- |
| **WinGet Packages** | *(Default)* | Exports installed applications via `winget export`. | `winget_packages.json` |
| **Application AppData** | `-IncludeAppData` (`-a`) | Scans & backs up matching `Roaming` and `Local` app settings. | `%AppData%`, `%LocalAppData%` |
| **Global NPM & NPX** | `-IncludeNpm` (`-n`) | Exports `npm -g` package manifests and cached `npx` tool metadata. | `npm_global_packages.json`, `npm_global_packages.txt`, `npx_cached_tools.txt` |
| **AI Agent Skills & MCP** | `-IncludeAiSkills` (`-s`) | Backs up agent skills, custom rules, and Model Context Protocol configs. | Antigravity/Gemini (`.gemini/config/skills`, `plugins`, `rules`, `mcp`), Claude (`.claude/skills`, `claude_desktop_config.json`), Cursor (`.cursor/rules`, `mcp.json`, `.cursorrules`), Windsurf (`mcp_config.json`, `.windsurfrules`), Copilot. |
| **Full Environment** | `-All` | Stages all components above in a single step. | Everything |

---

## Files

- [`Backup-DevEnv.ps1`](./Backup-DevEnv.ps1): Stages packages, app data, npm tools, and AI skills, then creates a timestamped ZIP archive (`DevEnv_Backup_YYYYMMDD_HHmm.zip`).
- [`Restore-DevEnv.ps1`](./Restore-DevEnv.ps1): Extracts the archive, reinstalls applications via `winget import`, reinstalls global NPM packages, and restores AppData and AI agent configurations (also supports legacy `WinGet_Backup_*.zip` archives).

---

## Usage Examples

### 1. Backup

* **Fast Backup (WinGet packages only):**
  ```powershell
  .\Backup-DevEnv.ps1
  ```

* **WinGet + Global NPM Tools:**
  ```powershell
  .\Backup-DevEnv.ps1 -IncludeNpm
  ```

* **WinGet + AI Agent Skills & MCP Tools:**
  ```powershell
  .\Backup-DevEnv.ps1 -IncludeAiSkills
  ```

* **Full Environment Backup (WinGet + AppData + NPM + AI Skills):**
  ```powershell
  .\Backup-DevEnv.ps1 -All
  ```

* **Custom Output Directory:**
  ```powershell
  .\Backup-DevEnv.ps1 -OutputDirectory "D:\Backups" -All
  ```

---

### 2. Restore

* **Standard Restore (WinGet packages only):**
  ```powershell
  .\Restore-DevEnv.ps1
  ```

* **Restore NPM Packages & AI Skills:**
  ```powershell
  .\Restore-DevEnv.ps1 -IncludeNpm -IncludeAiSkills
  ```

* **Complete Environment Restore:**
  ```powershell
  .\Restore-DevEnv.ps1 -All
  ```

* **Specify Backup Directory:**
  ```powershell
  .\Restore-DevEnv.ps1 -InputDirectory "D:\Backups" -All
  ```

---

## Supported AI Agent Paths

When `-IncludeAiSkills` is specified, the script automatically checks and backs up configurations from:

* **Antigravity / Gemini CLI:**
  * Skills: `~/.gemini/config/skills`
  * Plugins: `~/.gemini/config/plugins`
  * Instructions & Rules: `~/.gemini/config/rules`
  * MCP Server Schemas: `~/.gemini/antigravity-cli/mcp`
* **Claude & Claude Desktop:**
  * Skills & Prompts: `~/.claude/skills`
  * Custom Slash Commands: `~/.claude/commands`
  * Desktop MCP Config: `%APPDATA%\Claude\claude_desktop_config.json`
* **Cursor:**
  * Rules: `~/.cursor/rules` and `~/.cursorrules`
  * MCP Servers: `~/.cursor/mcp.json`
* **Windsurf:**
  * Rules: `~/.windsurfrules`
  * MCP Servers: `~/.codeium/windsurf/mcp_config.json`
* **GitHub Copilot:**
  * Global Instructions: `~/.github/copilot-instructions.md`

---

## Tips & Automation

### Execution Policy Bypass
If Windows restricts script execution, run with `-ExecutionPolicy Bypass`:
```powershell
powershell -ExecutionPolicy Bypass -File .\Backup-DevEnv.ps1 -All
```

### Windows Task Scheduler (Weekly Automated Backup)
To schedule automatic full backups every Sunday at 02:00 AM as Administrator:
```powershell
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSScriptRoot\Backup-DevEnv.ps1`" -All"
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2am
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "DevEnv-Weekly-Backup" -Action $Action -Trigger $Trigger -Principal $Principal -Description "Automated weekly full developer environment backup."
```
