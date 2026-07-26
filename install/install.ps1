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

.EXAMPLE
    irm https://raw.githubusercontent.com/gitkraken/merge-mate-cli/main/install/install.ps1 | iex

.EXAMPLE
    .\install.ps1 -Version 0.1.0
#>

param(
    [string]$Version,
    [string]$InstallDir
)

$ErrorActionPreference = "Stop"

$Repo = if ($env:MERGE_MATE_REPO) { $env:MERGE_MATE_REPO } else { "gitkraken/merge-mate-cli" }
$DefaultInstallDir = Join-Path $env:LOCALAPPDATA "merge-mate"
$InstallDir = if ($InstallDir) { $InstallDir } else { $DefaultInstallDir }
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

function Test-Architecture {
    if (-not [Environment]::Is64BitOperatingSystem) {
        Write-Err "Merge Mate CLI requires a 64-bit Windows installation"
    }
}

function Get-LatestVersion {
    $ReleasesUrl = "https://api.github.com/repos/$Repo/releases"

    try {
        $Releases = Invoke-RestMethod -Uri $ReleasesUrl -UseBasicParsing
        $CliRelease = $Releases | Where-Object { $_.tag_name -match "^v\d+\.\d+\.\d+$" } | Select-Object -First 1

        if (-not $CliRelease) {
            Write-Err "No CLI releases found"
        }

        return $CliRelease.tag_name -replace "^v", ""
    }
    catch {
        Write-Err "Failed to fetch releases: $_"
    }
}

function Get-Checksum {
    param(
        [string]$FilePath
    )

    $Hash = Get-FileHash -Path $FilePath -Algorithm SHA256
    return $Hash.Hash.ToLower()
}

function Install-MergeMate {
    param(
        [string]$Version
    )

    $Tag = "v$Version"
    $BinaryName = "merge-mate-windows-x64.exe"
    $DownloadUrl = "https://github.com/$Repo/releases/download/$Tag/$BinaryName"
    $ChecksumsUrl = "https://github.com/$Repo/releases/download/$Tag/checksums-sha256.txt"

    $TempDir = Join-Path $env:TEMP "merge-mate-install-$(Get-Random)"
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

    try {
        Write-Info "Downloading $BinaryName (v$Version)..."
        $BinaryPath = Join-Path $TempDir $BinaryName
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $BinaryPath -UseBasicParsing

        Write-Info "Verifying checksum..."
        $ChecksumsPath = Join-Path $TempDir "checksums.txt"
        Invoke-WebRequest -Uri $ChecksumsUrl -OutFile $ChecksumsPath -UseBasicParsing

        $ChecksumsContent = Get-Content $ChecksumsPath
        $ExpectedLine = $ChecksumsContent | Where-Object { $_ -match $BinaryName }

        if (-not $ExpectedLine) {
            Write-Err "Checksum not found for $BinaryName"
        }

        $ExpectedChecksum = ($ExpectedLine -split "\s+")[0].ToLower()
        $ActualChecksum = Get-Checksum -FilePath $BinaryPath

        if ($ExpectedChecksum -ne $ActualChecksum) {
            Write-Err "Checksum verification failed"
        }

        Write-Info "Checksum verified"

        if (-not (Test-Path $InstallDir)) {
            New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        }

        $DestPath = Join-Path $InstallDir $BinName
        Move-Item -Path $BinaryPath -Destination $DestPath -Force

        Write-Info "Installed to $DestPath"

        $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($UserPath -notlike "*$InstallDir*") {
            [Environment]::SetEnvironmentVariable("Path", "$UserPath;$InstallDir", "User")
            Write-Host ""
            Write-Host "Added $InstallDir to your PATH." -ForegroundColor Yellow
            Write-Host "Restart your terminal or run: `$env:Path = [Environment]::GetEnvironmentVariable('Path', 'User')" -ForegroundColor Yellow
        }
    }
    finally {
        Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Install {
    Test-Architecture

    if (-not $Version) {
        Write-Info "Detecting latest version..."
        $Version = Get-LatestVersion
    }

    Install-MergeMate -Version $Version

    Write-Host ""
    Write-Host "✓ Merge Mate CLI v$Version installed successfully" -ForegroundColor Green
    Write-Host ""
    Write-Host "Run 'merge-mate --help' to get started"
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Install
}
