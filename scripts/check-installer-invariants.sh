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
  # Enter a heredoc doc block on any "<<" / "<<-" redirection, capturing the
  # bare delimiter word so the matching terminator can be recognised regardless
  # of the delimiter name, quoting, or terminator indentation (<<- tabs).
  awk '
    !in_doc && match($0, /<<-?[[:space:]]*["'\'']?[A-Za-z_][A-Za-z0-9_]*["'\'']?/) {
      delim = substr($0, RSTART, RLENGTH)
      gsub(/^<<-?[[:space:]]*["'\'']?/, "", delim)
      gsub(/["'\'']?$/, "", delim)
      in_doc = 1
      next
    }
    in_doc {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (line == delim) { in_doc = 0 }
      next
    }
    /^[[:space:]]*#/ { next }
    { print }
  ' "$1"
}

strip_powershell_comments() {
  awk '
    {
      line = $0
      # Remove any complete inline block comments first so real code on the
      # same line survives.
      while (match(line, /<#.*#>/)) {
        line = substr(line, 1, RSTART - 1) substr(line, RSTART + RLENGTH)
      }
      if (in_doc) {
        if (match(line, /#>/)) {
          line = substr(line, RSTART + RLENGTH)
          in_doc = 0
        } else {
          next
        }
      }
      if (match(line, /<#/)) {
        line = substr(line, 1, RSTART - 1)
        in_doc = 1
      }
      if (line ~ /^[[:space:]]*#/) { next }
      if (line ~ /^[[:space:]]*$/) { next }
      print line
    }
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
forbid "$sh_code" 'curl.*\|[[:space:]]*(ba)?sh([[:space:]]|$)' "does not pipe downloads into a shell"
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
