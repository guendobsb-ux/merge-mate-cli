#!/usr/bin/env bash
set -euo pipefail

REPO="${MERGE_MATE_REPO:-gitkraken/merge-mate-cli}"
INSTALL_DIR="${MERGE_MATE_INSTALL_DIR:-$HOME/.local/bin}"
BIN_NAME="merge-mate"
VERSION=""
PLATFORM=""
TMP_DIR=""

cleanup() {
  local status=$?
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR" || echo "Warning: failed to remove temporary directory $TMP_DIR" >&2
  fi
  return $status
}
trap cleanup EXIT

usage() {
  cat <<EOF
Install Merge Mate CLI

Usage: install.sh [OPTIONS]

Options:
  --version VERSION   Install specific version (e.g., 0.1.0)
  --dir DIRECTORY     Installation directory (default: ~/.local/bin)
  --help              Show this help message

Environment:
  MERGE_MATE_REPO         GitHub repository (default: gitkraken/merge-mate-cli)
  MERGE_MATE_INSTALL_DIR  Installation directory (default: ~/.local/bin)

Examples:
  curl -fsSL https://raw.githubusercontent.com/$REPO/main/install/install.sh | bash
  curl -fsSL .../install.sh | bash -s -- --version 0.1.0
EOF
}

error() {
  echo "Error: $1" >&2
  exit 1
}

info() {
  echo "==> $1"
}

validate_repo() {
  if [[ ! "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    error "Invalid repository: $REPO (expected owner/name)"
  fi
}

validate_version() {
  if [[ ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.]+)*$ ]]; then
    error "Invalid version: $1 (expected semver, e.g. 0.1.0)"
  fi
}

detect_platform() {
  local os arch

  if ! os=$(uname -s); then
    error "Failed to detect the operating system (uname -s failed)"
  fi
  os=$(echo "$os" | tr '[:upper:]' '[:lower:]')

  if ! arch=$(uname -m); then
    error "Failed to detect the machine architecture (uname -m failed)"
  fi

  case "$os" in
    linux) os="linux" ;;
    darwin) os="darwin" ;;
    *) error "Unsupported OS: $os" ;;
  esac

  case "$arch" in
    x86_64|amd64) arch="x64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) error "Unsupported architecture: $arch" ;;
  esac

  if [[ "$os" == "linux" && "$arch" != "x64" ]]; then
    error "Linux builds are only available for x64 architecture"
  fi

  if [[ "$os" == "darwin" && "$arch" != "arm64" ]]; then
    error "macOS builds are only available for Apple Silicon (arm64)"
  fi

  PLATFORM="${os}-${arch}"
}

get_latest_version() {
  local releases_url="https://api.github.com/repos/${REPO}/releases"
  local releases http_status curl_status

  releases=$(curl -sSL -w '\n%{http_code}' "$releases_url" 2>/dev/null) && curl_status=0 || curl_status=$?

  if [[ $curl_status -ne 0 ]]; then
    error "Failed to reach $releases_url (curl exit code $curl_status). Check your internet connection or specify --version"
  fi

  http_status="${releases##*$'\n'}"
  releases="${releases%$'\n'*}"

  if [[ "$http_status" == "403" || "$http_status" == "429" ]]; then
    error "GitHub API rate limit reached (HTTP $http_status). Retry later or specify --version"
  fi

  if [[ "$http_status" != "200" ]]; then
    error "GitHub API request failed with HTTP $http_status for $releases_url. Verify MERGE_MATE_REPO=$REPO or specify --version"
  fi

  VERSION=$(echo "$releases" | grep -o '"tag_name": "v[^"]*"' | grep -v -- '-' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/') || true

  if [[ -z "$VERSION" ]]; then
    error "No stable release found for $REPO. Check the repository or specify --version"
  fi
}

download_and_verify() {
  local version="$1"
  local platform="$2"
  local tag="v${version}"
  local binary_name="merge-mate-${platform}"
  local download_url="https://github.com/${REPO}/releases/download/${tag}/${binary_name}"
  local checksums_url="https://github.com/${REPO}/releases/download/${tag}/checksums-sha256.txt"

  if ! TMP_DIR=$(mktemp -d); then
    error "Failed to create a temporary directory"
  fi

  info "Downloading $binary_name (v$version)..."
  if ! curl -fsSL "$download_url" -o "$TMP_DIR/$binary_name"; then
    error "Failed to download binary. Version $version may not exist for $platform"
  fi

  info "Verifying checksum..."
  if ! curl -fsSL "$checksums_url" -o "$TMP_DIR/checksums.txt"; then
    error "Failed to download checksums"
  fi

  local expected_checksum actual_checksum
  expected_checksum=$(awk -v name="$binary_name" '$2 == name || $2 == "*" name {print $1; exit}' "$TMP_DIR/checksums.txt")

  if [[ -z "$expected_checksum" ]]; then
    error "Checksum not found for $binary_name in $checksums_url"
  fi

  if command -v sha256sum &>/dev/null; then
    actual_checksum=$(sha256sum "$TMP_DIR/$binary_name" | awk '{print $1}') || error "Failed to compute checksum with sha256sum"
  elif command -v shasum &>/dev/null; then
    actual_checksum=$(shasum -a 256 "$TMP_DIR/$binary_name" | awk '{print $1}') || error "Failed to compute checksum with shasum"
  else
    error "Neither sha256sum nor shasum found"
  fi

  if [[ "$expected_checksum" != "$actual_checksum" ]]; then
    error "Checksum verification failed for $binary_name (expected $expected_checksum, got $actual_checksum)"
  fi

  info "Checksum verified"

  if [[ "$(uname -s)" == "Darwin" ]]; then
    xattr -d com.apple.quarantine "$TMP_DIR/$binary_name" 2>/dev/null || true
  fi

  mkdir -p "$INSTALL_DIR" || error "Failed to create installation directory $INSTALL_DIR"
  chmod +x "$TMP_DIR/$binary_name" || error "Failed to make $binary_name executable"

  if ! mv "$TMP_DIR/$binary_name" "$INSTALL_DIR/$BIN_NAME" 2>/dev/null; then
    if ! cp "$TMP_DIR/$binary_name" "$INSTALL_DIR/$BIN_NAME"; then
      error "Failed to install to $INSTALL_DIR/$BIN_NAME. Check the directory permissions and that $BIN_NAME is not currently running"
    fi
  fi

  info "Installed to $INSTALL_DIR/$BIN_NAME"
}

check_path() {
  if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo ""
    echo "Note: $INSTALL_DIR is not in your PATH."
    echo "Add it to your shell profile:"
    echo ""
    echo "  export PATH=\"\$PATH:$INSTALL_DIR\""
    echo ""
  fi
}

require_value() {
  local option="$1"
  local value="${2:-}"

  if [[ -z "$value" || "$value" == --* ]]; then
    error "Option $option requires a value"
  fi
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        require_value "--version" "${2:-}"
        VERSION="$2"
        shift 2
        ;;
      --dir)
        require_value "--dir" "${2:-}"
        INSTALL_DIR="$2"
        shift 2
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        error "Unknown option: $1"
        ;;
    esac
  done

  validate_repo
  detect_platform

  if [[ -z "$VERSION" ]]; then
    info "Detecting latest version..."
    get_latest_version
  fi

  validate_version "$VERSION"

  download_and_verify "$VERSION" "$PLATFORM"
  check_path

  echo ""
  echo "✓ Merge Mate CLI v$VERSION installed successfully"
  echo ""
  echo "Run 'merge-mate --help' to get started"
}

main "$@"
