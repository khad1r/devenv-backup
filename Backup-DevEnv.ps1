param (
    [Alias('o')]
    [string]$OutputDirectory = (Get-Location).Path,

    [Alias('a', 'WithAppData')]
    [switch]$IncludeAppData,

    [Alias('n', 'WithNpm')]
    [switch]$IncludeNpm,

    [Alias('s', 'WithSkills', 'WithAiSkills')]
    [switch]$IncludeAiSkills,

    [Alias('All')]
    [switch]$FullBackup
)

if ($FullBackup) {
    $IncludeAppData = $true
    $IncludeNpm = $true
    $IncludeAiSkills = $true
}

# --- ADMINISTRATOR PRIVILEGE CHECK ---
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$IsAdmin) {
    Write-Host "Warning: Script is not running as Administrator. WinGet may fail to access or export some system packages." -ForegroundColor Yellow
    Write-Host "Press any key to continue anyway or close this window to run as Admin..." -ForegroundColor Yellow
    if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}

# --- DYNAMIC DATE STAMP CONFIGURATION ---
$DateStamp = Get-Date -Format "yyyyMMdd_HHmm"
$ZipFileName = "DevEnv_Backup_$DateStamp.zip"

$TempBackupDir = Join-Path $OutputDirectory "DevEnv_Backup_Temp"
$WinGetJsonPath = Join-Path $TempBackupDir "winget_packages.json"
$AppDataBackupPath = Join-Path $TempBackupDir "AppData_Backup"
$AiSkillsBackupPath = Join-Path $TempBackupDir "AiSkills_Backup"
$ZipOutputPath = Join-Path $OutputDirectory $ZipFileName

Write-Host "Target Directory:  $OutputDirectory" -ForegroundColor Magenta
Write-Host "Backup File Name:  $ZipFileName" -ForegroundColor Magenta
Write-Host "Include AppData:   $($IncludeAppData.IsPresent)" -ForegroundColor Magenta
Write-Host "Include NPM:       $($IncludeNpm.IsPresent)" -ForegroundColor Magenta
Write-Host "Include AI Skills: $($IncludeAiSkills.IsPresent)" -ForegroundColor Magenta

# Clean up any leftover temp folders from failed previous runs
if (Test-Path -LiteralPath $TempBackupDir) {
    Remove-Item -LiteralPath $TempBackupDir -Recurse -Force
}

# Create temporary staging directories
New-Item -ItemType Directory -Path $TempBackupDir -Force | Out-Null

# --- 1. WINGET PACKAGES ---
Write-Host "`n1. Exporting WinGet package list..." -ForegroundColor Cyan
winget export -o $WinGetJsonPath --include-versions --accept-source-agreements
if (!(Test-Path -LiteralPath $WinGetJsonPath)) {
    Write-Host "   Failed to export WinGet list." -ForegroundColor Red
    Remove-Item -LiteralPath $TempBackupDir -Recurse -Force
    return
}

# --- 2. APPDATA SETTINGS ---
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

# --- 3. NPM & NPX TOOLS ---
if ($IncludeNpm) {
    Write-Host "`n3. Exporting Global NPM packages & tools..." -ForegroundColor Cyan
    $NpmCmd = Get-Command npm -ErrorAction SilentlyContinue
    if ($NpmCmd) {
        try {
            $NpmJsonRaw = & npm list -g --depth=0 --json 2>$null
            if ($NpmJsonRaw) {
                $NpmJsonPath = Join-Path $TempBackupDir "npm_global_packages.json"
                Set-Content -LiteralPath $NpmJsonPath -Value $NpmJsonRaw -Encoding utf8
                Write-Host "   [Saved] npm_global_packages.json" -ForegroundColor Yellow

                $ParsedNpm = $NpmJsonRaw | ConvertFrom-Json
                $NpmList = @()
                if ($ParsedNpm.dependencies) {
                    $NpmList = $ParsedNpm.dependencies.PSObject.Properties.Name | Where-Object { $_ -ne "npm" }
                }

                if ($NpmList.Count -gt 0) {
                    $NpmTextPath = Join-Path $TempBackupDir "npm_global_packages.txt"
                    $NpmList | Set-Content -LiteralPath $NpmTextPath -Encoding utf8
                    Write-Host "   [Found] $($NpmList.Count) global npm package(s) staged." -ForegroundColor Yellow
                } else {
                    Write-Host "   No third-party global npm packages found." -ForegroundColor DarkGray
                }
            }
        } catch {
            Write-Host "   Warning: Failed to export npm global list: $_" -ForegroundColor Yellow
        }

        # Stage npx cache metadata if present
        $NpxCachePath = Join-Path $env:LOCALAPPDATA "npm-cache\_npx"
        if (Test-Path -LiteralPath $NpxCachePath) {
            $NpxItems = Get-ChildItem -LiteralPath $NpxCachePath -Directory -ErrorAction SilentlyContinue
            if ($NpxItems) {
                $NpxMetaPath = Join-Path $TempBackupDir "npx_cached_tools.txt"
                $NpxItems.Name | Set-Content -LiteralPath $NpxMetaPath -Encoding utf8
                Write-Host "   [Saved] npx_cached_tools.txt ($($NpxItems.Count) cached tool execution hash(es))." -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "   npm command not found in PATH, skipping." -ForegroundColor Yellow
    }
} else {
    Write-Host "`n3. Skipping NPM global tools backup (default). Use -IncludeNpm to include global npm packages." -ForegroundColor DarkGray
}

# --- 4. AI AGENT SKILLS & MCP TOOLS ---
if ($IncludeAiSkills) {
    Write-Host "`n4. Backing up AI agent skills, rules & MCP configurations..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $AiSkillsBackupPath -Force | Out-Null

    $UserProfile = [System.Environment]::GetFolderPath('UserProfile')
    $RoamingAppData = [System.Environment]::GetFolderPath('ApplicationData')

    $AiLocations = @(
        # Gemini / Antigravity CLI
        @{ Name = "Gemini Skills"; Path = Join-Path $UserProfile ".gemini\config\skills"; SubPath = "gemini\skills"; IsDir = $true },
        @{ Name = "Gemini Plugins"; Path = Join-Path $UserProfile ".gemini\config\plugins"; SubPath = "gemini\plugins"; IsDir = $true },
        @{ Name = "Gemini Rules"; Path = Join-Path $UserProfile ".gemini\config\rules"; SubPath = "gemini\rules"; IsDir = $true },
        @{ Name = "Gemini MCP Schemas"; Path = Join-Path $UserProfile ".gemini\antigravity-cli\mcp"; SubPath = "gemini\mcp"; IsDir = $true },

        # Claude / Claude Desktop
        @{ Name = "Claude Skills"; Path = Join-Path $UserProfile ".claude\skills"; SubPath = "claude\skills"; IsDir = $true },
        @{ Name = "Claude Commands"; Path = Join-Path $UserProfile ".claude\commands"; SubPath = "claude\commands"; IsDir = $true },
        @{ Name = "Claude Desktop Config"; Path = Join-Path $RoamingAppData "Claude\claude_desktop_config.json"; SubPath = "claude\claude_desktop_config.json"; IsDir = $false },

        # Cursor
        @{ Name = "Cursor Rules"; Path = Join-Path $UserProfile ".cursor\rules"; SubPath = "cursor\rules"; IsDir = $true },
        @{ Name = "Cursor MCP Config"; Path = Join-Path $UserProfile ".cursor\mcp.json"; SubPath = "cursor\mcp.json"; IsDir = $false },
        @{ Name = "Cursor Global Rules"; Path = Join-Path $UserProfile ".cursorrules"; SubPath = "cursor\.cursorrules"; IsDir = $false },

        # Windsurf
        @{ Name = "Windsurf MCP Config"; Path = Join-Path $UserProfile ".codeium\windsurf\mcp_config.json"; SubPath = "windsurf\mcp_config.json"; IsDir = $false },
        @{ Name = "Windsurf Global Rules"; Path = Join-Path $UserProfile ".windsurfrules"; SubPath = "windsurf\.windsurfrules"; IsDir = $false },

        # GitHub Copilot
        @{ Name = "Copilot Instructions"; Path = Join-Path $UserProfile ".github\copilot-instructions.md"; SubPath = "copilot\copilot-instructions.md"; IsDir = $false }
    )

    $BackedUpAiCount = 0
    foreach ($Item in $AiLocations) {
        if (Test-Path -LiteralPath $Item.Path) {
            $TargetDest = Join-Path $AiSkillsBackupPath $Item.SubPath
            $ParentDir = Split-Path -Path $TargetDest -Parent
            if (!(Test-Path -LiteralPath $ParentDir)) {
                New-Item -ItemType Directory -Path $ParentDir -Force | Out-Null
            }

            if ($Item.IsDir) {
                $ChildItems = Get-ChildItem -LiteralPath $Item.Path -ErrorAction SilentlyContinue
                if ($ChildItems) {
                    Write-Host "   [Found] Staging $($Item.Name) ($($Item.Path))..." -ForegroundColor Yellow
                    Copy-Item -LiteralPath $Item.Path -Destination $TargetDest -Recurse -Force -ErrorAction SilentlyContinue
                    $BackedUpAiCount++
                }
            } else {
                Write-Host "   [Found] Staging $($Item.Name) ($($Item.Path))..." -ForegroundColor Yellow
                Copy-Item -LiteralPath $Item.Path -Destination $TargetDest -Force -ErrorAction SilentlyContinue
                $BackedUpAiCount++
            }
        }
    }

    if ($BackedUpAiCount -eq 0) {
        Write-Host "   No active AI skills, rules, or MCP configs detected at default locations." -ForegroundColor DarkGray
    } else {
        Write-Host "   Staged $BackedUpAiCount AI configuration/skill target(s)." -ForegroundColor Green
    }
} else {
    Write-Host "`n4. Skipping AI agent skills backup (default). Use -IncludeAiSkills to include skills & MCP configs." -ForegroundColor DarkGray
}

# --- 5. COMPRESSION & CLEANUP ---
Write-Host "`n5. Compressing backup into ZIP archive..." -ForegroundColor Cyan
Compress-Archive -Path "$TempBackupDir\*" -DestinationPath $ZipOutputPath -Force

# Clean up temporary files
Remove-Item -LiteralPath $TempBackupDir -Recurse -Force

Write-Host "`nBackup Complete! Saved as: $ZipOutputPath" -ForegroundColor Green
