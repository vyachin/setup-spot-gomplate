#!/usr/bin/env bash
#
# Installs pinned releases of spot and gomplate into INSTALL_DIR.
#
# Required environment variables:
#   SPOT_VERSION      spot release tag, e.g. v1.20.1
#   GOMPLATE_VERSION  gomplate release tag, e.g. v5.3.1
# Optional:
#   INSTALL_DIR       destination directory (default: $RUNNER_TEMP/spot-gomplate or /tmp/spot-gomplate)
#
# The script is idempotent: binaries that already report the requested version
# are reused, which makes it safe to run after a GitHub Actions cache restore.
# Every download is verified against the checksum published in the release.

set -euo pipefail

spot_version="${SPOT_VERSION:?SPOT_VERSION is required}"
gomplate_version="${GOMPLATE_VERSION:?GOMPLATE_VERSION is required}"
install_dir="${INSTALL_DIR:-${RUNNER_TEMP:-/tmp}/spot-gomplate}"

spot_repo="https://github.com/umputun/spot"
gomplate_repo="https://github.com/hairyhenderson/gomplate"

os="$(uname -s)"
arch="$(uname -m)"

case "${os}/${arch}" in
  Linux/x86_64 | Linux/amd64)
    spot_platform="linux_x86_64"
    gomplate_platform="linux-amd64"
    ;;
  Linux/aarch64 | Linux/arm64)
    spot_platform="linux_arm64"
    gomplate_platform="linux-arm64"
    ;;
  Darwin/arm64)
    spot_platform="macos_arm64"
    gomplate_platform="darwin-arm64"
    ;;
  Darwin/x86_64)
    spot_platform="macos_x86_64"
    gomplate_platform="darwin-amd64"
    ;;
  *)
    echo "setup-spot-gomplate: unsupported platform '${os}/${arch}'" >&2
    exit 1
    ;;
esac

mkdir -p "$install_dir"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/spot-gomplate.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

log() {
  printf 'setup-spot-gomplate: %s\n' "$*"
}

# version_matches <binary> <version> checks that the binary prints the requested
# version. The leading "v" is dropped because gomplate reports "5.3.1" while its
# release tag is "v5.3.1"; spot prints "v1.20.1", which still contains "1.20.1".
version_matches() {
  local binary="$1" expected="$2" bare
  bare="${expected#v}"
  [ -x "$binary" ] || return 1
  "$binary" --version 2>/dev/null | grep -Fq "$bare"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# download <url> <output>
download() {
  curl -fsSL --retry 3 --retry-delay 2 --retry-connrefused -o "$2" "$1"
}

# expected_checksum <checksums-file> <asset-name> prints the hash for asset-name.
expected_checksum() {
  awk -v asset="$2" '$2 == asset || $2 == "bin/" asset { print $1; exit }' "$1"
}

# verify <file> <checksums-file> <asset-name>
verify() {
  local file="$1" checksums="$2" asset="$3" expected actual
  expected="$(expected_checksum "$checksums" "$asset")"
  if [ -z "$expected" ]; then
    echo "setup-spot-gomplate: no checksum for '${asset}' in ${checksums}" >&2
    exit 1
  fi
  actual="$(sha256_of "$file")"
  if [ "$actual" != "$expected" ]; then
    echo "setup-spot-gomplate: checksum mismatch for ${asset}" >&2
    echo "  expected: ${expected}" >&2
    echo "  actual:   ${actual}" >&2
    exit 1
  fi
}

install_spot() {
  local base_name="spot_${spot_version}_${spot_platform}.tar.gz"
  local checksums_name="spot_${spot_version#v}_checksums.txt"
  local archive="$tmp_dir/spot.tar.gz"

  log "downloading spot ${spot_version} (${spot_platform})"
  download "${spot_repo}/releases/download/${spot_version}/${checksums_name}" "$tmp_dir/spot_checksums.txt"
  download "${spot_repo}/releases/download/${spot_version}/${base_name}" "$archive"
  verify "$archive" "$tmp_dir/spot_checksums.txt" "$base_name"

  tar -xzf "$archive" -C "$tmp_dir" spot
  install -m 0755 "$tmp_dir/spot" "$install_dir/spot"
}

install_gomplate() {
  local base_name="gomplate_${gomplate_platform}"
  local checksums_name="checksums-${gomplate_version}_sha256.txt"

  log "downloading gomplate ${gomplate_version} (${gomplate_platform})"
  download "${gomplate_repo}/releases/download/${gomplate_version}/${checksums_name}" "$tmp_dir/gomplate_checksums.txt"
  download "${gomplate_repo}/releases/download/${gomplate_version}/${base_name}" "$tmp_dir/gomplate"
  verify "$tmp_dir/gomplate" "$tmp_dir/gomplate_checksums.txt" "$base_name"

  install -m 0755 "$tmp_dir/gomplate" "$install_dir/gomplate"
}

if version_matches "$install_dir/spot" "$spot_version"; then
  log "spot ${spot_version} already installed"
else
  install_spot
fi

if version_matches "$install_dir/gomplate" "$gomplate_version"; then
  log "gomplate ${gomplate_version} already installed"
else
  install_gomplate
fi

log "spot:     $("$install_dir/spot" --version)"
log "gomplate: $("$install_dir/gomplate" --version)"
