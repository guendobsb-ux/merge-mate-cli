#!/usr/bin/env bash
set -euo pipefail

REPO="${MERGE_MATE_REPO:-gitkraken/merge-mate-cli}"
INSTALL_DIR="${MERGE_MATE_INSTALL_DIR:-$HOME/.local/bin}"
BIN_NAME="merge-mate"
VERSION=""
TMP_DIR=""

cleanup() {
  [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
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

detect_platform() {
  local os arch

  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)

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

  echo "${os}-${arch}"
}

get_latest_version() {
  local releases_url="https://api.github.com/repos/${REPO}/releases"
  local version

  version=$(curl -fsSL "$releases_url" | grep -o '"tag_name": "v[^"]*"' | grep -v -- '-' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')

  if [[ -z "$version" ]]; then
    error "Could not determine latest version. Check your internet connection or specify --version"
  fi

  echo "$version"
}

download_and_verify() {
  local version="$1"
  local platform="$2"
  local tag="v${version}"
  local binary_name="merge-mate-${platform}"
  local download_url="https://github.com/${REPO}/releases/download/${tag}/${binary_name}"
  local checksums_url="https://github.com/${REPO}/releases/download/${tag}/checksums-sha256.txt"
  TMP_DIR=$(mktemp -d)

  info "Downloading $binary_name (v$version)..."
  if ! curl -fsSL "$download_url" -o "$TMP_DIR/$binary_name"; then
    error "Failed to download binary. Version $version may not exist for $platform"
  fi

  info "Verifying checksum..."
  if ! curl -fsSL "$checksums_url" -o "$TMP_DIR/checksums.txt"; then
    error "Failed to download checksums"
  fi

  local expected_checksum actual_checksum
  expected_checksum=$(grep "$binary_name" "$TMP_DIR/checksums.txt" | awk '{print $1}')

  if [[ -z "$expected_checksum" ]]; then
    error "Checksum not found for $binary_name"
  fi

  if command -v sha256sum &>/dev/null; then
    actual_checksum=$(sha256sum "$TMP_DIR/$binary_name" | awk '{print $1}')
  elif command -v shasum &>/dev/null; then
    actual_checksum=$(shasum -a 256 "$TMP_DIR/$binary_name" | awk '{print $1}')
  else
    error "Neither sha256sum nor shasum found"
  fi

  if [[ "$expected_checksum" != "$actual_checksum" ]]; then
    error "Checksum verification failed"
  fi

  info "Checksum verified"

  if [[ "$(uname -s)" == "Darwin" ]]; then
    xattr -d com.apple.quarantine "$TMP_DIR/$binary_name" 2>/dev/null || true
  fi

  mkdir -p "$INSTALL_DIR"
  chmod +x "$TMP_DIR/$binary_name"
  mv "$TMP_DIR/$binary_name" "$INSTALL_DIR/$BIN_NAME"

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

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        VERSION="$2"
        shift 2
        ;;
      --dir)
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

  local platform
  platform=$(detect_platform)

  if [[ -z "$VERSION" ]]; then
    info "Detecting latest version..."
    VERSION=$(get_latest_version)
  fi

  download_and_verify "$VERSION" "$platform"
  check_path

  echo ""
  echo "✓ Merge Mate CLI v$VERSION installed successfully"
  echo ""
  echo "Run 'merge-mate --help' to get started"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
