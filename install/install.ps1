#Requires -Version 5.1
<#
.SYNOPSIS
    Install Merge Mate CLI on Windows.

.DESCRIPTION
    Downloads and installs the Merge Mate CLI binary to %LOCALAPPDATA%\merge-mate.

.PARAMETER Version
    Specific version to install (e.g., "0.1.0"). If not specified, installs the latest version.

.PARAMETER InstallDir
    Installation directory. Default: $env:LOCALAPPDATA\merge-mate

.PARAMETER Force
    Reinstall even if the target version is already installed.

.EXAMPLE
    irm https://raw.githubusercontent.com/gitkraken/merge-mate-cli/main/install/install.ps1 | iex

.EXAMPLE
    .\install.ps1 -Version 0.1.0
#>

param(
    [string]$Version,
    [string]$InstallDir,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}
catch {
    Write-Warning "Could not enable TLS 1.2; downloads may fail on this system: $($_.Exception.Message)"
}

$Repo = if ($env:MERGE_MATE_REPO) { $env:MERGE_MATE_REPO } else { "gitkraken/merge-mate-cli" }
if (-not $InstallDir) {
    if (-not $env:LOCALAPPDATA) {
        Write-Host "Error: LOCALAPPDATA is not set; pass -InstallDir to choose an installation directory" -ForegroundColor Red
        exit 1
    }
    $InstallDir = Join-Path $env:LOCALAPPDATA "merge-mate"
}
$BinName = "merge-mate.exe"

function Write-Info {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Err {
    param([string]$Message)
    Write-Host "Error: $Message" -ForegroundColor Red
    exit 1
}

function Get-ErrorDetail {
    param($ErrorRecord)

    $Detail = $ErrorRecord.Exception.Message
    $Response = $ErrorRecord.Exception.Response

    if ($Response -and $Response.StatusCode) {
        $Detail = "HTTP $([int]$Response.StatusCode) $($Response.StatusCode) - $Detail"
    }

    return $Detail
}

function Test-VersionFormat {
    param(
        [string]$Value,
        [string]$Source
    )

    if ($Value -notmatch "^\d+\.\d+\.\d+([.-][0-9A-Za-z]+)*$") {
        Write-Err "Invalid version '$Value' from ${Source}. Expected a version like 0.1.0"
    }
}

function Test-Architecture {
    if (-not [Environment]::Is64BitOperatingSystem) {
        Write-Err "Merge Mate CLI requires a 64-bit Windows installation"
    }
}

function Get-LatestVersion {
    $ReleasesUrl = "https://api.github.com/repos/$Repo/releases"

    try {
        $Releases = Invoke-RestMethod -Uri $ReleasesUrl -UseBasicParsing
    }
    catch {
        Write-Err "Failed to fetch releases from ${ReleasesUrl}: $(Get-ErrorDetail $_). Check your internet connection, the GitHub API rate limit, or pass -Version"
    }

    $CliRelease = $Releases |
        Where-Object { -not $_.draft -and $_.tag_name -match "^v\d+\.\d+\.\d+$" } |
        Select-Object -First 1

    if (-not $CliRelease) {
        Write-Err "No stable release found for $Repo. Check the repository or pass -Version"
    }

    $Resolved = $CliRelease.tag_name -replace "^v", ""
    Test-VersionFormat -Value $Resolved -Source "the GitHub releases API"

    return $Resolved
}

function Add-ToUserPath {
    param([string]$Directory)

    try {
        $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $Entries = @($UserPath -split ";" | Where-Object { $_ })

        if ($Entries -contains $Directory) {
            return
        }

        $NewPath = (@($Entries) + $Directory) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")

        Write-Host ""
        Write-Host "Added $Directory to your PATH." -ForegroundColor Yellow
        Write-Host "Restart your terminal or run: `$env:Path = [Environment]::GetEnvironmentVariable('Path', 'User')" -ForegroundColor Yellow
    }
    catch {
        Write-Warning "Installed successfully, but failed to add $Directory to your PATH: $($_.Exception.Message)"
        Write-Warning "Add it manually, or run merge-mate from $Directory"
    }
}

function Get-Checksum {
    param(
        [string]$FilePath
    )

    $Hash = Get-FileHash -Path $FilePath -Algorithm SHA256
    return $Hash.Hash.ToLower()
}

function Get-InstalledVersion {
    param([string]$Path)

    try {
        $Output = & $Path --version 2>$null
    }
    catch {
        return $null
    }

    if ($LASTEXITCODE -ne 0 -or -not $Output) {
        return $null
    }

    $Match = [regex]::Match(($Output -join "`n"), "\d+(\.\d+)+[0-9A-Za-z.+-]*")
    if (-not $Match.Success) {
        return $null
    }

    return $Match.Value
}

function Install-MergeMate {
    param(
        [string]$Version
    )

    $Tag = "v$Version"
    $BinaryName = "merge-mate-windows-x64.exe"
    $DownloadUrl = "https://github.com/$Repo/releases/download/$Tag/$BinaryName"
    $ChecksumsUrl = "https://github.com/$Repo/releases/download/$Tag/checksums-sha256.txt"

    $TempDir = Join-Path $env:TEMP "merge-mate-install-$([guid]::NewGuid().ToString('N'))"

    try {
        New-Item -ItemType Directory -Path $TempDir | Out-Null
    }
    catch {
        Write-Err "Failed to create temporary directory ${TempDir}: $($_.Exception.Message)"
    }

    try {
        Write-Info "Downloading $BinaryName (v$Version)..."
        $BinaryPath = Join-Path $TempDir $BinaryName
        try {
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $BinaryPath -UseBasicParsing
        }
        catch {
            Write-Err "Failed to download $DownloadUrl : $(Get-ErrorDetail $_). Version $Version may not exist for windows-x64"
        }

        Write-Info "Verifying checksum..."
        $ChecksumsPath = Join-Path $TempDir "checksums.txt"
        try {
            Invoke-WebRequest -Uri $ChecksumsUrl -OutFile $ChecksumsPath -UseBasicParsing
        }
        catch {
            Write-Err "Failed to download checksums from $ChecksumsUrl : $(Get-ErrorDetail $_)"
        }

        $ChecksumsContent = Get-Content $ChecksumsPath
        $BinaryNamePattern = "\s\*?$([regex]::Escape($BinaryName))\s*$"
        $ExpectedLine = @($ChecksumsContent | Where-Object { $_ -match $BinaryNamePattern })

        if ($ExpectedLine.Count -eq 0) {
            Write-Err "Checksum not found for $BinaryName in $ChecksumsUrl"
        }

        $ExpectedChecksum = ($ExpectedLine[0] -split "\s+")[0].ToLower()
        $ActualChecksum = Get-Checksum -FilePath $BinaryPath

        if ($ExpectedChecksum -ne $ActualChecksum) {
            Write-Err "Checksum verification failed for $BinaryName (expected $ExpectedChecksum, got $ActualChecksum)"
        }

        Write-Info "Checksum verified"

        if (-not (Test-Path $InstallDir)) {
            try {
                New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
            }
            catch {
                Write-Err "Failed to create installation directory ${InstallDir}: $($_.Exception.Message)"
            }
        }

        $DestPath = Join-Path $InstallDir $BinName
        try {
            Move-Item -Path $BinaryPath -Destination $DestPath -Force
        }
        catch {
            Write-Err "Failed to install to ${DestPath}: $($_.Exception.Message). Close any running merge-mate process and check the directory permissions"
        }

        Write-Info "Installed to $DestPath"

        Add-ToUserPath -Directory $InstallDir
    }
    finally {
        if (Test-Path $TempDir) {
            try {
                Remove-Item -Path $TempDir -Recurse -Force
            }
            catch {
                Write-Warning "Failed to remove temporary directory ${TempDir}: $($_.Exception.Message)"
            }
        }
    }
}

function Invoke-Install {
    try {
        if ($Repo -ne "gitkraken/merge-mate-cli") {
            Write-Warning "Downloading from $Repo instead of gitkraken/merge-mate-cli."
            Write-Warning "Checksums are fetched from the same repository, so they do not prove authenticity."
        }

        Test-Architecture

        if ($Version) {
            Test-VersionFormat -Value $Version -Source "-Version"
        }

        if (-not $Version) {
            Write-Info "Detecting latest version..."
            $Version = Get-LatestVersion
        }

        if (-not $Force) {
            $ExistingPath = Join-Path $InstallDir $BinName

            if (Test-Path $ExistingPath) {
                $InstalledVersion = Get-InstalledVersion -Path $ExistingPath

                if ($InstalledVersion -eq $Version) {
                    Write-Info "merge-mate v$Version is already installed at $ExistingPath"
                    Write-Info "Use -Force to reinstall"
                    exit 0
                }
            }
        }

        Install-MergeMate -Version $Version
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "✓ Merge Mate CLI v$Version installed successfully" -ForegroundColor Green
    Write-Host ""
    Write-Host "Run 'merge-mate --help' to get started"
    exit 0
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Install
}
