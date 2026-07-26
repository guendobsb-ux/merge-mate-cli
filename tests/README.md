# Tests

Unit tests for the installer scripts.

## install.sh — [bats](https://github.com/bats-core/bats-core)

```sh
sudo apt-get install -y bats   # or: brew install bats-core
bats tests/install_sh.bats
```

## install.ps1 — [Pester](https://pester.dev)

```powershell
Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck
Invoke-Pester -Path tests/install.Tests.ps1 -Output Detailed
```

Both suites source (dot-source) the installer scripts and mock all
network/filesystem/system calls (`curl`, `uname`, `Invoke-WebRequest`,
`Get-FileHash`, ...), so they never download anything or modify the machine.
The scripts guard their entrypoint so sourcing them does not run an install.
