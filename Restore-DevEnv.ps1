param (
    [Alias('o')]
    [string]$InputDirectory = (Get-Location).Path,

    [Alias('a', 'WithAppData')]
    [switch]$IncludeAppData,

    [Alias('n', 'WithNpm')]
    [switch]$IncludeNpm,

    [Alias('s', 'WithSkills', 'WithAiSkills')]
    [switch]$IncludeAiSkills,

    [Alias('All')]
    [switch]$FullRestore
)

if ($FullRestore) {
    $IncludeAppData = $true
    $IncludeNpm = $true
    $IncludeAiSkills = $true
}

# --- ADMINISTRATOR PRIVILEGE CHECK ---
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$IsAdmin) {
    Write-Host "Error: This restore script requires Administrator privileges to import system applications." -ForegroundColor Red
    Write-Host "Please restart PowerShell as Administrator and run the script again." -ForegroundColor Red
    return
}

Write-Host "Looking for backups in: $InputDirectory" -ForegroundColor Magenta
Write-Host "Restore AppData:        $($IncludeAppData.IsPresent)" -ForegroundColor Magenta
Write-Host "Restore NPM:            $($IncludeNpm.IsPresent)" -ForegroundColor Magenta
Write-Host "Restore AI Skills:      $($IncludeAiSkills.IsPresent)" -ForegroundColor Magenta

# Find the newest backup archive (supporting DevEnv_Backup_*.zip and legacy WinGet_Backup_*.zip)
$LatestZip = Get-ChildItem -Path $InputDirectory -Include "DevEnv_Backup_*.zip", "WinGet_Backup_*.zip" -File -Recurse:$false | 
             Sort-Object CreationTime -Descending | 
             Select-Object -First 1

if (!$LatestZip) {
    # Direct filter fallback
    $LatestZip = Get-ChildItem -Path $InputDirectory -Filter "*.zip" | 
                 Where-Object { $_.Name -like "DevEnv_Backup_*.zip" -or $_.Name -like "WinGet_Backup_*.zip" } | 
                 Sort-Object CreationTime -Descending | 
                 Select-Object -First 1
}

if (!$LatestZip) {
    Write-Host "Error: No matching 'DevEnv_Backup_*.zip' or 'WinGet_Backup_*.zip' file found in the target directory!" -ForegroundColor Red
    return
}

$ZipInputPath = $LatestZip.FullName
$TempExtractDir = Join-Path $InputDirectory "DevEnv_Restore_Temp"
$WinGetJsonPath = Join-Path $TempExtractDir "winget_packages.json"
$AppDataBackupPath = Join-Path $TempExtractDir "AppData_Backup"
$NpmListPath = Join-Path $TempExtractDir "npm_global_packages.txt"
$AiSkillsBackupPath = Join-Path $TempExtractDir "AiSkills_Backup"

Write-Host "Targeting newest archive: $($LatestZip.Name)" -ForegroundColor Green

# Clean up any leftover temp extraction folders
if (Test-Path -LiteralPath $TempExtractDir) {
    Remove-Item -LiteralPath $TempExtractDir -Recurse -Force
}

# --- 1. EXTRACT ARCHIVE ---
Write-Host "`n1. Extracting backup archive..." -ForegroundColor Cyan
Expand-Archive -Path $ZipInputPath -DestinationPath $TempExtractDir -Force

# --- 2. REINSTALL WINGET PACKAGES ---
Write-Host "`n2. Reinstalling apps via WinGet..." -ForegroundColor Cyan
if (Test-Path -LiteralPath $WinGetJsonPath) {
    winget import -i $WinGetJsonPath --accept-package-agreements --accept-source-agreements
} else {
    Write-Host "   WinGet JSON manifest missing from backup archive." -ForegroundColor Red
}

# --- 3. RESTORE APPDATA SETTINGS ---
if ($IncludeAppData) {
    Write-Host "`n3. Restoring AppData settings..." -ForegroundColor Cyan
    $RoamingPath = [System.Environment]::GetFolderPath('ApplicationData')
    $LocalPath = [System.Environment]::GetFolderPath('LocalApplicationData')

    # Restore Roaming Folders
    $RoamingBackupDir = Join-Path $AppDataBackupPath "Roaming"
    if (Test-Path -LiteralPath $RoamingBackupDir) {
        Write-Host "   Restoring Roaming configuration..." -ForegroundColor Yellow
        Get-ChildItem -LiteralPath $RoamingBackupDir | ForEach-Object {
            $Dest = Join-Path $RoamingPath $_.Name
            Copy-Item -LiteralPath $_.FullName -Destination $Dest -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Restore Local Folders
    $LocalBackupDir = Join-Path $AppDataBackupPath "Local"
    if (Test-Path -LiteralPath $LocalBackupDir) {
        Write-Host "   Restoring Local configuration..." -ForegroundColor Yellow
        Get-ChildItem -LiteralPath $LocalBackupDir | ForEach-Object {
            $Dest = Join-Path $LocalPath $_.Name
            Copy-Item -LiteralPath $_.FullName -Destination $Dest -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Host "`n3. Skipping AppData restore (default). Use -IncludeAppData to restore app settings." -ForegroundColor DarkGray
}

# --- 4. RESTORE GLOBAL NPM PACKAGES ---
if ($IncludeNpm) {
    Write-Host "`n4. Restoring Global NPM packages..." -ForegroundColor Cyan
    $NpmCmd = Get-Command npm -ErrorAction SilentlyContinue
    if (!$NpmCmd) {
        Write-Host "   npm command not found in PATH. Please install Node.js/npm first." -ForegroundColor Yellow
    } elseif (Test-Path -LiteralPath $NpmListPath) {
        $Packages = Get-Content -LiteralPath $NpmListPath | Where-Object { ![string]::IsNullOrWhiteSpace($_) }
        if ($Packages.Count -gt 0) {
            foreach ($Pkg in $Packages) {
                Write-Host "   Installing global npm package: $Pkg..." -ForegroundColor Yellow
                & npm install -g $Pkg
            }
            Write-Host "   NPM packages restoration completed." -ForegroundColor Green
        } else {
            Write-Host "   No packages listed in npm_global_packages.txt." -ForegroundColor DarkGray
        }
    } else {
        Write-Host "   No npm_global_packages.txt found in backup archive." -ForegroundColor DarkGray
    }
} else {
    Write-Host "`n4. Skipping NPM restore (default). Use -IncludeNpm to restore global npm packages." -ForegroundColor DarkGray
}

# --- 5. RESTORE AI AGENT SKILLS & MCP TOOLS ---
if ($IncludeAiSkills) {
    Write-Host "`n5. Restoring AI agent skills, rules & MCP configurations..." -ForegroundColor Cyan
    if (Test-Path -LiteralPath $AiSkillsBackupPath) {
        $UserProfile = [System.Environment]::GetFolderPath('UserProfile')
        $RoamingAppData = [System.Environment]::GetFolderPath('ApplicationData')

        $AiRestoreMap = @(
            # Gemini / Antigravity CLI
            @{ SubPath = "gemini\skills"; Target = Join-Path $UserProfile ".gemini\config\skills"; IsDir = $true },
            @{ SubPath = "gemini\plugins"; Target = Join-Path $UserProfile ".gemini\config\plugins"; IsDir = $true },
            @{ SubPath = "gemini\rules"; Target = Join-Path $UserProfile ".gemini\config\rules"; IsDir = $true },
            @{ SubPath = "gemini\mcp"; Target = Join-Path $UserProfile ".gemini\antigravity-cli\mcp"; IsDir = $true },

            # Claude / Claude Desktop
            @{ SubPath = "claude\skills"; Target = Join-Path $UserProfile ".claude\skills"; IsDir = $true },
            @{ SubPath = "claude\commands"; Target = Join-Path $UserProfile ".claude\commands"; IsDir = $true },
            @{ SubPath = "claude\claude_desktop_config.json"; Target = Join-Path $RoamingAppData "Claude\claude_desktop_config.json"; IsDir = $false },

            # Cursor
            @{ SubPath = "cursor\rules"; Target = Join-Path $UserProfile ".cursor\rules"; IsDir = $true },
            @{ SubPath = "cursor\mcp.json"; Target = Join-Path $UserProfile ".cursor\mcp.json"; IsDir = $false },
            @{ SubPath = "cursor\.cursorrules"; Target = Join-Path $UserProfile ".cursorrules"; IsDir = $false },

            # Windsurf
            @{ SubPath = "windsurf\mcp_config.json"; Target = Join-Path $UserProfile ".codeium\windsurf\mcp_config.json"; IsDir = $false },
            @{ SubPath = "windsurf\.windsurfrules"; Target = Join-Path $UserProfile ".windsurfrules"; IsDir = $false },

            # GitHub Copilot
            @{ SubPath = "copilot\copilot-instructions.md"; Target = Join-Path $UserProfile ".github\copilot-instructions.md"; IsDir = $false }
        )

        $RestoredAiCount = 0
        foreach ($Item in $AiRestoreMap) {
            $SourcePath = Join-Path $AiSkillsBackupPath $Item.SubPath
            if (Test-Path -LiteralPath $SourcePath) {
                $ParentTarget = Split-Path -Path $Item.Target -Parent
                if (!(Test-Path -LiteralPath $ParentTarget)) {
                    New-Item -ItemType Directory -Path $ParentTarget -Force | Out-Null
                }

                if ($Item.IsDir) {
                    Write-Host "   Restoring folder: $($Item.SubPath) -> $($Item.Target)" -ForegroundColor Yellow
                    Copy-Item -LiteralPath "$SourcePath\*" -Destination $Item.Target -Recurse -Force -ErrorAction SilentlyContinue
                } else {
                    Write-Host "   Restoring file: $($Item.SubPath) -> $($Item.Target)" -ForegroundColor Yellow
                    Copy-Item -LiteralPath $SourcePath -Destination $Item.Target -Force -ErrorAction SilentlyContinue
                }
                $RestoredAiCount++
            }
        }

        if ($RestoredAiCount -eq 0) {
            Write-Host "   No AI skill configurations found inside the archive to restore." -ForegroundColor DarkGray
        } else {
            Write-Host "   Successfully restored $RestoredAiCount AI configuration target(s)." -ForegroundColor Green
        }
    } else {
        Write-Host "   No AiSkills_Backup directory found in backup archive." -ForegroundColor DarkGray
    }
} else {
    Write-Host "`n5. Skipping AI skills restore (default). Use -IncludeAiSkills to restore skills & MCP configs." -ForegroundColor DarkGray
}

# Clean up temp folder
Remove-Item -LiteralPath $TempExtractDir -Recurse -Force

Write-Host "`nRestore complete! Please restart your apps and terminal to see all restored settings." -ForegroundColor Green
