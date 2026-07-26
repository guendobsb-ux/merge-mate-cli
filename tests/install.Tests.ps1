#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Unit tests for install/install.ps1

    The script's entrypoint (`Invoke-Install`) is guarded so that dot-sourcing
    does not trigger a real install. That lets these tests dot-source the script
    to load its functions and exercise them with mocked network / filesystem /
    system calls.
#>

BeforeAll {
    $script:InstallScript = Join-Path $PSScriptRoot '..' 'install' 'install.ps1'

    # install.ps1 targets Windows; provide the env vars it relies on so it can be
    # dot-sourced on any platform running PowerShell (e.g. Linux CI).
    if (-not $env:LOCALAPPDATA) { $env:LOCALAPPDATA = [System.IO.Path]::GetTempPath() }
    if (-not $env:TEMP) { $env:TEMP = [System.IO.Path]::GetTempPath() }

    # Dot-source so the functions ($Repo, Get-LatestVersion, Install-MergeMate,
    # ...) are available in the current scope. The entrypoint stays dormant
    # because $MyInvocation.InvocationName is '.' when dot-sourcing.
    . $script:InstallScript -Version '1.0.0'
}

Describe 'Script configuration' {
    It 'defaults Repo to gitkraken/merge-mate-cli' {
        $Repo | Should -Be 'gitkraken/merge-mate-cli'
    }

    It 'names the installed binary merge-mate.exe' {
        $BinName | Should -Be 'merge-mate.exe'
    }
}

Describe 'Get-Checksum' {
    It 'returns the lowercase SHA256 of a file' {
        $tmp = New-Item -ItemType File -Path (Join-Path $TestDrive 'payload.bin') -Force
        Set-Content -Path $tmp.FullName -Value 'merge-mate' -NoNewline

        $expected = (Get-FileHash -Path $tmp.FullName -Algorithm SHA256).Hash.ToLower()
        $actual = Get-Checksum -FilePath $tmp.FullName

        $actual | Should -Be $expected
        $actual | Should -MatchExactly '^[0-9a-f]{64}$'
    }
}

Describe 'Get-LatestVersion' {
    It 'returns the newest stable version without the leading v' {
        Mock Invoke-RestMethod {
            @(
                [pscustomobject]@{ tag_name = 'v2.0.0-rc.1' }
                [pscustomobject]@{ tag_name = 'v1.4.2' }
                [pscustomobject]@{ tag_name = 'v1.4.0' }
            )
        }

        Get-LatestVersion | Should -Be '1.4.2'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly
    }

    It 'ignores non semver tags' {
        Mock Invoke-RestMethod {
            @(
                [pscustomobject]@{ tag_name = 'nightly' }
                [pscustomobject]@{ tag_name = 'v3.1.0' }
            )
        }

        Get-LatestVersion | Should -Be '3.1.0'
    }

    It 'errors when no CLI release is found' {
        Mock Invoke-RestMethod { @() }
        Mock Write-Err { throw "write-err: $Message" }

        { Get-LatestVersion } | Should -Throw '*No stable release found*'
    }

    It 'errors when the releases request fails' {
        Mock Invoke-RestMethod { throw 'network down' }
        Mock Write-Err { throw "write-err: $Message" }

        { Get-LatestVersion } | Should -Throw '*Failed to fetch releases*'
    }
}

Describe 'Install-MergeMate' {
    BeforeEach {
        # Neutralise everything that touches the real machine.
        Mock Invoke-WebRequest { }
        Mock Move-Item { }
        Mock New-Item { }
        Mock Remove-Item { }
        Mock Write-Info { }
        Mock Write-Host { }
        Mock Test-Path { $true }
        Mock Get-Content { 'aaaa1111  merge-mate-windows-x64.exe' }
    }

    It 'installs the binary when the checksum matches' {
        Mock Get-Checksum { 'aaaa1111' }

        { Install-MergeMate -Version '1.0.0' } | Should -Not -Throw

        Should -Invoke Invoke-WebRequest -Times 2 -Exactly  # binary + checksums
        Should -Invoke Move-Item -Times 1 -Exactly
    }

    It 'aborts on a checksum mismatch and does not move the binary' {
        Mock Get-Checksum { 'ffffffff' }
        Mock Write-Err { throw "write-err: $Message" }

        { Install-MergeMate -Version '1.0.0' } | Should -Throw '*Checksum verification failed*'
        Should -Invoke Move-Item -Times 0 -Exactly
    }

    It 'aborts when the checksum entry is missing' {
        Mock Get-Content { 'deadbeef  some-other-file.exe' }
        Mock Write-Err { throw "write-err: $Message" }

        { Install-MergeMate -Version '1.0.0' } | Should -Throw '*Checksum not found*'
        Should -Invoke Move-Item -Times 0 -Exactly
    }

    It 'downloads from the version-specific release URL' {
        Mock Get-Checksum { 'aaaa1111' }

        Install-MergeMate -Version '9.9.9'

        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://github.com/gitkraken/merge-mate-cli/releases/download/v9.9.9/merge-mate-windows-x64.exe'
        }
    }
}
