#!/usr/bin/env bash
# Enforces supply-chain safety invariants on the installer scripts.
# Comments, doc blocks and usage text are stripped before scanning so that
# documented examples are not mistaken for executable code.
set -euo pipefail

SH="install/install.sh"
PS="install/install.ps1"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

pass() {
  echo "ok: $1"
}

strip_shell_comments() {
  awk '
    /^[[:space:]]*cat <<EOF/ { in_doc = 1; next }
    in_doc && /^EOF$/ { in_doc = 0; next }
    in_doc { next }
    /^[[:space:]]*#/ { next }
    { print }
  ' "$1"
}

strip_powershell_comments() {
  awk '
    /<#/ { in_doc = 1 }
    in_doc { if (/#>/) { in_doc = 0 }; next }
    /^[[:space:]]*#/ { next }
    { print }
  ' "$1"
}

require() {
  local file="$1" pattern="$2" description="$3"
  if grep -Eq -- "$pattern" "$file"; then
    pass "$(basename "$file") $description"
  else
    fail "$(basename "$file") $description"
  fi
}

forbid() {
  local file="$1" pattern="$2" description="$3"
  if grep -Eqi -- "$pattern" "$file"; then
    fail "$(basename "$file") $description"
    grep -Eni -- "$pattern" "$file" >&2
  else
    pass "$(basename "$file") $description"
  fi
}

for file in "$SH" "$PS"; do
  if [[ ! -f "$file" ]]; then
    fail "$file is missing"
    exit 1
  fi
done

sh_code="$WORK_DIR/install.sh"
ps_code="$WORK_DIR/install.ps1"
strip_shell_comments "$SH" >"$sh_code"
strip_powershell_comments "$PS" >"$ps_code"

for file in "$sh_code" "$ps_code"; do
  forbid "$file" 'http://[^"[:space:]]' "uses only https URLs"
  forbid "$file" '(^|[^[:alnum:]_-])(eval|iex|Invoke-Expression)([^[:alnum:]_-]|$)' "does not evaluate dynamic code"
  forbid "$file" 'base64 (-d|--decode)|FromBase64String' "does not decode base64 payloads"
  forbid "$file" 'curl -k|--insecure|-SkipCertificateCheck|ServerCertificateValidationCallback' "does not disable TLS verification"
done

require "$sh_code" '^set -euo pipefail' "aborts on errors (set -euo pipefail)"
require "$sh_code" 'sha256sum|shasum -a 256' "computes a SHA-256 checksum"
# shellcheck disable=SC2016  # the pattern matches literal shell source text
require "$sh_code" 'expected_checksum" != "\$actual_checksum' "compares the downloaded checksum"
require "$sh_code" 'checksums-sha256\.txt' "downloads the published checksums file"
forbid "$sh_code" 'curl[^|]*\|[[:space:]]*(ba)?sh' "does not pipe downloads into a shell"
forbid "$sh_code" '(^|[^[:alnum:]_-])sudo([^[:alnum:]_-]|$)' "does not require elevated privileges"

require "$ps_code" 'ErrorActionPreference = "Stop"' "aborts on errors"
require "$ps_code" 'Get-FileHash .* -Algorithm SHA256' "computes a SHA-256 checksum"
# shellcheck disable=SC2016  # the pattern matches literal PowerShell source text
require "$ps_code" 'ExpectedChecksum -ne \$ActualChecksum' "compares the downloaded checksum"
require "$ps_code" 'checksums-sha256\.txt' "downloads the published checksums file"
require "$ps_code" 'SecurityProtocolType\]::Tls12' "requires TLS 1.2 or newer"

if [[ $failures -gt 0 ]]; then
  echo "$failures installer invariant(s) violated" >&2
  exit 1
fi

echo "All installer invariants hold"
