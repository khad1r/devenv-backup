param (
    [Alias('o')]
    [string]$InputDirectory = (Get-Location).Path,

    [Alias('a', 'WithAppData')]
    [switch]$IncludeAppData
)

# --- ADMINISTRATOR PRIVILEGE CHECK ---
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$IsAdmin) {
    Write-Host "Error: This restore script requires Administrator privileges to import system applications." -ForegroundColor Red
    Write-Host "Please restart PowerShell as Administrator and run the script again." -ForegroundColor Red
    return
}

Write-Host "Looking for backups in: $InputDirectory" -ForegroundColor Magenta
Write-Host "Restore AppData:        $($IncludeAppData.IsPresent)" -ForegroundColor Magenta

# Find the newest WinGet backup file in the directory
$LatestZip = Get-ChildItem -Path $InputDirectory -Filter "WinGet_Backup_*.zip" | 
             Sort-Object CreationTime -Descending | 
             Select-Object -First 1

if (!$LatestZip) {
    Write-Host "Error: No matching 'WinGet_Backup_*.zip' file found in the target directory!" -ForegroundColor Red
    return
}

$ZipInputPath = $LatestZip.FullName
$TempExtractDir = Join-Path $InputDirectory "WinGet_Restore_Temp"
$WinGetJsonPath = Join-Path $TempExtractDir "winget_packages.json"
$AppDataBackupPath = Join-Path $TempExtractDir "AppData_Backup"

Write-Host "Targeting newest archive: $($LatestZip.Name)" -ForegroundColor Green

# Clean up any leftover temp extraction folders
if (Test-Path -LiteralPath $TempExtractDir) {
    Remove-Item -LiteralPath $TempExtractDir -Recurse -Force
}

Write-Host "`n1. Extracting backup archive..." -ForegroundColor Cyan
Expand-Archive -Path $ZipInputPath -DestinationPath $TempExtractDir -Force

Write-Host "`n2. Reinstalling apps via WinGet..." -ForegroundColor Cyan
if (Test-Path -LiteralPath $WinGetJsonPath) {
    winget import -i $WinGetJsonPath --accept-package-agreements --accept-source-agreements
} else {
    Write-Host "   WinGet JSON manifest missing from backup archive." -ForegroundColor Red
}

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

# Clean up temp folder
Remove-Item -LiteralPath $TempExtractDir -Recurse -Force

Write-Host "`nRestore complete! Please restart your apps to see your custom settings." -ForegroundColor Green
