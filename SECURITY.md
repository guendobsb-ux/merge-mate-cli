# Security Policy

## Reporting a vulnerability

Report suspected vulnerabilities in the installer scripts or in a published
release artifact privately through GitHub's
[private vulnerability reporting](https://github.com/guendobsb-ux/merge-mate-cli/security/advisories/new).
Please do not open a public issue for an unfixed vulnerability.

Include the affected version, your platform, and the steps needed to reproduce
the issue. Expect an acknowledgement within a few business days.

## Verifying a download yourself

Both installers verify the SHA-256 checksum of the downloaded binary against
`checksums-sha256.txt` from the same release and abort on a mismatch. To verify
manually:

```bash
curl -fsSLO https://github.com/gitkraken/merge-mate-cli/releases/download/v<version>/merge-mate-<platform>
curl -fsSLO https://github.com/gitkraken/merge-mate-cli/releases/download/v<version>/checksums-sha256.txt
sha256sum --ignore-missing -c checksums-sha256.txt
```

```powershell
(Get-FileHash .\merge-mate-windows-x64.exe -Algorithm SHA256).Hash.ToLower()
# compare against the matching line in checksums-sha256.txt
```

If a checksum does not match, stop and report it — do not run the binary.

## Supply-chain controls in this repository

- `scripts/check-installer-invariants.sh` fails CI if an installer loses its
  checksum verification, disables TLS validation, pipes downloads into a shell,
  requests elevated privileges, or evaluates dynamically decoded content.
- ShellCheck and PSScriptAnalyzer run against the installers on every pull
  request.
- Gitleaks scans the working tree and the full git history for committed
  secrets.
- CodeQL analyses the GitHub Actions workflows, and all third-party actions are
  pinned to a full commit SHA.
- Dependabot proposes weekly updates for GitHub Actions.
