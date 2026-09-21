param (
    [Alias('o')]
    [string]$OutputDirectory = (Get-Location).Path,

    [Alias('a', 'WithAppData')]
    [switch]$IncludeAppData
)

# --- ADMINISTRATOR PRIVILEGE CHECK ---
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$IsAdmin) {
    Write-Host "Warning: Script is not running as Administrator. WinGet may fail to access or export some system packages." -ForegroundColor Yellow
    Write-Host "Press any key to continue anyway or close this window to run as Admin..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# --- DYNAMIC DATE STAMP CONFIGURATION ---
$DateStamp = Get-Date -Format "yyyyMMdd_HHmm"
$ZipFileName = "WinGet_Backup_$DateStamp.zip"

$TempBackupDir = Join-Path $OutputDirectory "WinGet_Backup_Temp"
$WinGetJsonPath = Join-Path $TempBackupDir "winget_packages.json"
$AppDataBackupPath = Join-Path $TempBackupDir "AppData_Backup"
$ZipOutputPath = Join-Path $OutputDirectory $ZipFileName

Write-Host "Target Directory: $OutputDirectory" -ForegroundColor Magenta
Write-Host "Backup File Name: $ZipFileName" -ForegroundColor Magenta
Write-Host "Include AppData:  $($IncludeAppData.IsPresent)" -ForegroundColor Magenta

# Clean up any leftover temp folders from failed previous runs
if (Test-Path -LiteralPath $TempBackupDir) {
    Remove-Item -LiteralPath $TempBackupDir -Recurse -Force
}

# Create temporary staging directories
New-Item -ItemType Directory -Path $TempBackupDir -Force | Out-Null

Write-Host "`n1. Exporting WinGet package list..." -ForegroundColor Cyan
winget export -o $WinGetJsonPath --include-versions --accept-source-agreements
if (!(Test-Path -LiteralPath $WinGetJsonPath)) {
    Write-Host "   Failed to export WinGet list." -ForegroundColor Red
    Remove-Item -LiteralPath $TempBackupDir -Recurse -Force
    return
}

if ($IncludeAppData) {
    Write-Host "`n2. Scanning and copying matching AppData folders..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path (Join-Path $AppDataBackupPath "Roaming") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $AppDataBackupPath "Local") -Force | Out-Null

    $PackageData = Get-Content -LiteralPath $WinGetJsonPath -Raw | ConvertFrom-Json

    # Flatten all packages across all sources
    $Packages = @()
    if ($PackageData.Sources) {
        foreach ($Source in $PackageData.Sources) {
            if ($Source.Packages) {
                $Packages += $Source.Packages
            }
        }
    }

    $RoamingPath = [System.Environment]::GetFolderPath('ApplicationData')
    $LocalPath = [System.Environment]::GetFolderPath('LocalApplicationData')

    # Disallowed generic terms that could match broad system/vendor folders
    $IgnoredTerms = @("Microsoft", "Windows", "Common", "System", "Apps", "Software", "Local", "Roaming", "Temp")
    $BackedUpPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($Pkg in $Packages) {
        # Extract package identifier safely
        $PackageIdentifier = if ($Pkg.PackageIdentifier) { 
            $Pkg.PackageIdentifier 
        } elseif ($Pkg.PackageId) { 
            $Pkg.PackageId 
        } elseif ($Pkg.Id) { 
            $Pkg.Id 
        } else { 
            $null 
        }

        if ([string]::IsNullOrWhiteSpace($PackageIdentifier)) {
            continue
        }

        $SearchTerms = [System.Collections.Generic.List[string]]::new()
        $IdParts = $PackageIdentifier.Split('.')

        # 1. Full identifier
        $SearchTerms.Add($PackageIdentifier)

        # 2. Last segment
        if ($IdParts.Count -gt 0) {
            $LastPart = $IdParts[-1]
            if (![string]::IsNullOrWhiteSpace($LastPart)) {
                $SearchTerms.Add($LastPart)
            }
        }

        # 3. Vendor\App subfolder structure
        if ($IdParts.Count -ge 2) {
            $Vendor = $IdParts[0]
            $App = $IdParts[-1]
            if (![string]::IsNullOrWhiteSpace($Vendor) -and ![string]::IsNullOrWhiteSpace($App)) {
                $SearchTerms.Add("$Vendor\$App")
            }
        }

        # 4. Known aliases
        if ($PackageIdentifier -eq "Microsoft.VisualStudioCode") {
            $SearchTerms.Add("Code")
        }

        foreach ($SourceDir in @($RoamingPath, $LocalPath)) {
            $FolderType = if ($SourceDir -eq $RoamingPath) { "Roaming" } else { "Local" }
            
            foreach ($Term in $SearchTerms) {
                $TrimmedTerm = $Term.Trim().Trim('\', '/')
                if ([string]::IsNullOrWhiteSpace($TrimmedTerm) -or $TrimmedTerm.Length -le 1 -or $IgnoredTerms -contains $TrimmedTerm) {
                    continue
                }

                $PotentialPath = Join-Path $SourceDir $TrimmedTerm
                
                if ((Test-Path -LiteralPath $PotentialPath) -and (Test-Path -LiteralPath $PotentialPath -PathType Container)) {
                    $ResolvedPath = (Get-Item -LiteralPath $PotentialPath).FullName
                    
                    if ($ResolvedPath -eq $SourceDir -or $BackedUpPaths.Contains($ResolvedPath)) {
                        continue
                    }

                    $TargetBackupDir = Join-Path $AppDataBackupPath "$FolderType\$TrimmedTerm"
                    
                    if (!(Test-Path -LiteralPath $TargetBackupDir)) {
                        Write-Host "   [Found] Staging settings for $PackageIdentifier ($FolderType\$TrimmedTerm)..." -ForegroundColor Yellow
                        $ParentDir = Split-Path -Path $TargetBackupDir -Parent
                        if (!(Test-Path -LiteralPath $ParentDir)) {
                            New-Item -ItemType Directory -Path $ParentDir -Force | Out-Null
                        }
                        Copy-Item -LiteralPath $ResolvedPath -Destination $TargetBackupDir -Recurse -Force -ErrorAction SilentlyContinue
                        $BackedUpPaths.Add($ResolvedPath) | Out-Null
                    }
                }
            }
        }
    }
} else {
    Write-Host "`n2. Skipping AppData backup (default). Use -IncludeAppData to include app settings." -ForegroundColor DarkGray
}

Write-Host "`n3. Compressing backup into ZIP archive..." -ForegroundColor Cyan
Compress-Archive -Path "$TempBackupDir\*" -DestinationPath $ZipOutputPath -Force

# Clean up temporary files
Remove-Item -LiteralPath $TempBackupDir -Recurse -Force

Write-Host "`nBackup Complete! Saved as: $ZipOutputPath" -ForegroundColor Green
