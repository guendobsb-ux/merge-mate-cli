#!/usr/bin/env bats
#
# Unit tests for install/install.sh
#
# The script is sourced (its `main` entrypoint is guarded so sourcing does not
# trigger an install). System/network commands (uname, curl, sha256sum, ...) are
# overridden with shell functions so the pure logic can be exercised in isolation.

SCRIPT="${BATS_TEST_DIRNAME}/../install/install.sh"

setup() {
  # Isolate HOME so default INSTALL_DIR does not touch the real environment.
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$HOME"
  unset MERGE_MATE_REPO MERGE_MATE_INSTALL_DIR
}

# Source the script into the current shell so its functions become available.
load_script() {
  # shellcheck disable=SC1090
  source "$SCRIPT"
  # The script enables `set -euo pipefail`, which leaks into the test shell and
  # makes assertions abort the whole run. Disable it here; individual functions
  # do their own error handling.
  set +euo pipefail
}

# ---------------------------------------------------------------------------
# Default configuration
# ---------------------------------------------------------------------------

@test "defaults: REPO, INSTALL_DIR and BIN_NAME have expected values" {
  load_script
  [ "$REPO" = "gitkraken/merge-mate-cli" ]
  [ "$INSTALL_DIR" = "$HOME/.local/bin" ]
  [ "$BIN_NAME" = "merge-mate" ]
}

@test "defaults: environment variables override REPO and INSTALL_DIR" {
  export MERGE_MATE_REPO="acme/fork"
  export MERGE_MATE_INSTALL_DIR="/opt/tools"
  load_script
  [ "$REPO" = "acme/fork" ]
  [ "$INSTALL_DIR" = "/opt/tools" ]
}

# ---------------------------------------------------------------------------
# info / error helpers
# ---------------------------------------------------------------------------

@test "info: prints an arrow-prefixed message to stdout" {
  load_script
  run info "hello world"
  [ "$status" -eq 0 ]
  [ "$output" = "==> hello world" ]
}

@test "error: prints to stderr and exits non-zero" {
  run bash -c "source '$SCRIPT'; error 'boom'"
  [ "$status" -eq 1 ]
  [[ "$output" == "Error: boom" ]]
}

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------

@test "usage: documents options and examples" {
  load_script
  run usage
  [ "$status" -eq 0 ]
  [[ "$output" == *"Install Merge Mate CLI"* ]]
  [[ "$output" == *"--version VERSION"* ]]
  [[ "$output" == *"--dir DIRECTORY"* ]]
  [[ "$output" == *"MERGE_MATE_REPO"* ]]
}

# ---------------------------------------------------------------------------
# detect_platform
# ---------------------------------------------------------------------------

@test "detect_platform: linux x86_64 -> linux-x64" {
  load_script
  uname() { case "$1" in -s) echo "Linux";; -m) echo "x86_64";; esac; }
  run detect_platform
  [ "$status" -eq 0 ]
  [ "$output" = "linux-x64" ]
}

@test "detect_platform: darwin arm64 -> darwin-arm64" {
  load_script
  uname() { case "$1" in -s) echo "Darwin";; -m) echo "arm64";; esac; }
  run detect_platform
  [ "$status" -eq 0 ]
  [ "$output" = "darwin-arm64" ]
}

@test "detect_platform: aarch64 normalizes to arm64 (darwin)" {
  load_script
  uname() { case "$1" in -s) echo "Darwin";; -m) echo "aarch64";; esac; }
  run detect_platform
  [ "$status" -eq 0 ]
  [ "$output" = "darwin-arm64" ]
}

@test "detect_platform: amd64 normalizes to x64 (linux)" {
  load_script
  uname() { case "$1" in -s) echo "Linux";; -m) echo "amd64";; esac; }
  run detect_platform
  [ "$status" -eq 0 ]
  [ "$output" = "linux-x64" ]
}

@test "detect_platform: unsupported OS errors" {
  load_script
  uname() { case "$1" in -s) echo "FreeBSD";; -m) echo "x86_64";; esac; }
  run detect_platform
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported OS: freebsd"* ]]
}

@test "detect_platform: unsupported architecture errors" {
  load_script
  uname() { case "$1" in -s) echo "Linux";; -m) echo "riscv64";; esac; }
  run detect_platform
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported architecture: riscv64"* ]]
}

@test "detect_platform: linux arm64 is rejected (x64 only)" {
  load_script
  uname() { case "$1" in -s) echo "Linux";; -m) echo "arm64";; esac; }
  run detect_platform
  [ "$status" -eq 1 ]
  [[ "$output" == *"Linux builds are only available for x64"* ]]
}

@test "detect_platform: darwin x64 is rejected (arm64 only)" {
  load_script
  uname() { case "$1" in -s) echo "Darwin";; -m) echo "x86_64";; esac; }
  run detect_platform
  [ "$status" -eq 1 ]
  [[ "$output" == *"macOS builds are only available for Apple Silicon"* ]]
}

# ---------------------------------------------------------------------------
# get_latest_version
# ---------------------------------------------------------------------------

@test "get_latest_version: extracts newest stable tag, skipping prereleases" {
  load_script
  curl() {
    cat <<'JSON'
[
  {"tag_name": "v1.2.0-rc.1"},
  {"tag_name": "v1.1.0"},
  {"tag_name": "v1.0.0"}
]
JSON
  }
  run get_latest_version
  [ "$status" -eq 0 ]
  [ "$output" = "1.1.0" ]
}

@test "get_latest_version: errors when no version can be parsed" {
  load_script
  curl() { echo "[]"; }
  run get_latest_version
  [ "$status" -eq 1 ]
  [[ "$output" == *"Could not determine latest version"* ]]
}

# ---------------------------------------------------------------------------
# check_path
# ---------------------------------------------------------------------------

@test "check_path: warns when INSTALL_DIR is not on PATH" {
  load_script
  INSTALL_DIR="/some/unlisted/dir"
  PATH="/usr/bin:/bin"
  run check_path
  [ "$status" -eq 0 ]
  [[ "$output" == *"is not in your PATH"* ]]
  [[ "$output" == *"/some/unlisted/dir"* ]]
}

@test "check_path: silent when INSTALL_DIR is already on PATH" {
  load_script
  INSTALL_DIR="/opt/tools"
  PATH="/usr/bin:/opt/tools:/bin"
  run check_path
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# main: argument parsing
# ---------------------------------------------------------------------------

@test "main: --help prints usage and exits 0" {
  load_script
  run main --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: install.sh"* ]]
}

@test "main: unknown option errors" {
  load_script
  run main --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: --bogus"* ]]
}

@test "main: --version and --dir feed download_and_verify" {
  load_script
  # Stub the pieces main orchestrates so we can assert wiring only.
  detect_platform() { echo "linux-x64"; }
  get_latest_version() { echo "SHOULD_NOT_BE_CALLED"; }
  check_path() { :; }
  download_and_verify() { echo "dv:$1:$2:$INSTALL_DIR"; }
  run main --version 9.9.9 --dir /custom/dir
  [ "$status" -eq 0 ]
  [[ "$output" == *"dv:9.9.9:linux-x64:/custom/dir"* ]]
  [[ "$output" == *"installed successfully"* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "main: without --version auto-detects latest" {
  load_script
  detect_platform() { echo "linux-x64"; }
  get_latest_version() { echo "3.2.1"; }
  check_path() { :; }
  download_and_verify() { echo "dv:$1:$2"; }
  run main
  [ "$status" -eq 0 ]
  [[ "$output" == *"Detecting latest version"* ]]
  [[ "$output" == *"dv:3.2.1:linux-x64"* ]]
}

# ---------------------------------------------------------------------------
# download_and_verify
# ---------------------------------------------------------------------------

@test "download_and_verify: installs binary when checksum matches" {
  load_script
  INSTALL_DIR="${BATS_TEST_TMPDIR}/bin"

  # curl writes deterministic content to the -o target.
  curl() {
    local out=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -o) out="$2"; shift 2;;
        *) shift;;
      esac
    done
    if [[ "$out" == *checksums* ]]; then
      printf '%s  %s\n' "$(printf 'BINARY' | sha256sum | awk '{print $1}')" "merge-mate-linux-x64" > "$out"
    else
      printf 'BINARY' > "$out"
    fi
  }

  run download_and_verify "1.0.0" "linux-x64"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Checksum verified"* ]]
  [ -x "$INSTALL_DIR/merge-mate" ]
  [ "$(cat "$INSTALL_DIR/merge-mate")" = "BINARY" ]
}

@test "download_and_verify: fails on checksum mismatch" {
  load_script
  INSTALL_DIR="${BATS_TEST_TMPDIR}/bin"
  curl() {
    local out=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -o) out="$2"; shift 2;;
        *) shift;;
      esac
    done
    if [[ "$out" == *checksums* ]]; then
      printf '%s  %s\n' "0000000000000000000000000000000000000000000000000000000000000000" "merge-mate-linux-x64" > "$out"
    else
      printf 'BINARY' > "$out"
    fi
  }
  run download_and_verify "1.0.0" "linux-x64"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Checksum verification failed"* ]]
}

@test "download_and_verify: errors when checksum entry is missing" {
  load_script
  INSTALL_DIR="${BATS_TEST_TMPDIR}/bin"
  curl() {
    local out=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -o) out="$2"; shift 2;;
        *) shift;;
      esac
    done
    if [[ "$out" == *checksums* ]]; then
      printf '%s  %s\n' "deadbeef" "some-other-file" > "$out"
    else
      printf 'BINARY' > "$out"
    fi
  }
  run download_and_verify "1.0.0" "linux-x64"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Checksum not found"* ]]
}

@test "download_and_verify: errors when binary download fails" {
  load_script
  INSTALL_DIR="${BATS_TEST_TMPDIR}/bin"
  curl() { return 22; }  # emulate curl -f HTTP failure
  run download_and_verify "9.9.9" "linux-x64"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to download binary"* ]]
}
