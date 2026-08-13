#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSIONS_FILE="$ROOT/scripts/supply-chain/versions.env"
TOOLS_DIR="${SUPPLY_CHAIN_TOOLS_DIR:-$ROOT/.tmp/supply-chain-tools}"

fail() {
  printf '[error] %s\n' "$1" >&2
  exit 1
}

require_tool() {
  local tool="$1"
  command -v "$tool" >/dev/null 2>&1 || fail "required tool missing: $tool"
}

load_versions() {
  [ -f "$VERSIONS_FILE" ] || fail "versions metadata missing"

  while IFS='=' read -r key value; do
    case "$key" in
      '' | \#*)
        ;;
      SYFT_VERSION | SYFT_ASSET | SYFT_SHA256 | SYFT_DARWIN_ARM64_ASSET | SYFT_DARWIN_ARM64_SHA256 | SYFT_RELEASE_BASE_URL | SYFT_CHECKSUM_SOURCE | GRYPE_VERSION | GRYPE_ASSET | GRYPE_SHA256 | GRYPE_DARWIN_ARM64_ASSET | GRYPE_DARWIN_ARM64_SHA256 | GRYPE_RELEASE_BASE_URL | GRYPE_CHECKSUM_SOURCE)
        case "$value" in
          *[!A-Za-z0-9._:/=-]*)
            fail "unsafe value in versions metadata for $key"
            ;;
        esac
        printf -v "$key" '%s' "$value"
        ;;
      *)
        fail "unexpected versions metadata key: $key"
        ;;
    esac
  done <"$VERSIONS_FILE"
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{ print $1 }'
  else
    fail "required checksum tool missing: sha256sum or shasum"
  fi
}

verify_checksum() {
  local file="$1"
  local expected="$2"

  case "$expected" in
    *[!0-9a-f]*)
      fail "malformed expected SHA-256"
      ;;
  esac
  [ "${#expected}" -eq 64 ] || fail "malformed expected SHA-256"
  [ -f "$file" ] || fail "downloaded file missing: $file"

  actual="$(sha256_file "$file")"
  if [ "$actual" != "$expected" ]; then
    fail "checksum mismatch for $(basename "$file")"
  fi
}

host_suffix() {
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os:$arch" in
    Linux:x86_64 | Linux:amd64)
      printf 'LINUX_AMD64\n'
      ;;
    Darwin:arm64)
      printf 'DARWIN_ARM64\n'
      ;;
    *)
      fail "unsupported tool host: $os/$arch"
      ;;
  esac
}

metadata_for() {
  local tool="$1"
  local field="$2"
  local suffix="$3"

  case "$tool:$field:$suffix" in
    syft:asset:LINUX_AMD64) printf '%s\n' "$SYFT_ASSET" ;;
    syft:sha:LINUX_AMD64) printf '%s\n' "$SYFT_SHA256" ;;
    syft:asset:DARWIN_ARM64) printf '%s\n' "$SYFT_DARWIN_ARM64_ASSET" ;;
    syft:sha:DARWIN_ARM64) printf '%s\n' "$SYFT_DARWIN_ARM64_SHA256" ;;
    grype:asset:LINUX_AMD64) printf '%s\n' "$GRYPE_ASSET" ;;
    grype:sha:LINUX_AMD64) printf '%s\n' "$GRYPE_SHA256" ;;
    grype:asset:DARWIN_ARM64) printf '%s\n' "$GRYPE_DARWIN_ARM64_ASSET" ;;
    grype:sha:DARWIN_ARM64) printf '%s\n' "$GRYPE_DARWIN_ARM64_SHA256" ;;
    *)
      fail "missing metadata for $tool $field $suffix"
      ;;
  esac
}

base_url_for() {
  case "$1" in
    syft) printf '%s\n' "$SYFT_RELEASE_BASE_URL" ;;
    grype) printf '%s\n' "$GRYPE_RELEASE_BASE_URL" ;;
    *) fail "unknown tool: $1" ;;
  esac
}

install_tool() {
  local tool="$1"
  local suffix="$2"
  local asset=""
  local expected=""
  local base_url=""
  local archive=""
  local staging=""

  asset="$(metadata_for "$tool" asset "$suffix")"
  expected="$(metadata_for "$tool" sha "$suffix")"
  base_url="$(base_url_for "$tool")"
  archive="$TOOLS_DIR/downloads/$asset"
  staging="$TOOLS_DIR/staging/$tool"

  mkdir -p "$TOOLS_DIR/bin" "$TOOLS_DIR/downloads" "$staging"
  if [ ! -f "$archive" ]; then
    curl -fsSL "$base_url/$asset" -o "$archive"
  fi

  verify_checksum "$archive" "$expected"
  rm -rf "$staging"
  mkdir -p "$staging"
  tar -xzf "$archive" -C "$staging"
  [ -x "$staging/$tool" ] || fail "extracted binary missing: $tool"
  cp "$staging/$tool" "$TOOLS_DIR/bin/$tool"
  chmod 0755 "$TOOLS_DIR/bin/$tool"
  verify_checksum "$archive" "$expected"
  printf '[ok] installed %s from %s\n' "$tool" "$asset"
}

install_all() {
  require_tool curl
  require_tool tar
  require_tool awk
  load_versions
  suffix="$(host_suffix)"
  install_tool syft "$suffix"
  install_tool grype "$suffix"
  printf '[ok] evidence tools installed in %s\n' ".tmp/supply-chain-tools"
}

case "${1:-install}" in
  install)
    install_all
    ;;
  verify-checksum)
    [ "$#" -eq 3 ] || fail "usage: $0 verify-checksum <file> <expected-sha256>"
    verify_checksum "$2" "$3"
    ;;
  *)
    fail "usage: $0 {install|verify-checksum}"
    ;;
esac
