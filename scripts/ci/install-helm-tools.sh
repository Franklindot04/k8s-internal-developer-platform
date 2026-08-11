#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION_FILE="$ROOT/platform/helm-charts/versions.env"
BIN_DIR="${RUNNER_TEMP:-/tmp}/idp-helm-bin"

# shellcheck disable=SC1090
. "$VERSION_FILE"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    os=linux
    arch=amd64
    ;;
  *)
    printf '[error] CI installer supports Linux amd64 runners only.\n' >&2
    exit 1
    ;;
esac

mkdir -p "$BIN_DIR"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

sha256_file() {
  file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

download_and_verify() {
  name="$1"
  url="$2"
  expected_sha="$3"
  output="$tmp_dir/$name"

  curl -fsSL "$url" -o "$output"
  actual_sha="$(sha256_file "$output")"
  if [ "$actual_sha" != "$expected_sha" ]; then
    printf '[error] checksum mismatch for %s\n' "$name" >&2
    exit 1
  fi
  printf '%s\n' "$output"
}

helm_archive="$(download_and_verify "helm.tar.gz" "https://get.helm.sh/helm-${HELM_VERSION}-${os}-${arch}.tar.gz" "$HELM_LINUX_AMD64_SHA256")"
tar -xzf "$helm_archive" -C "$tmp_dir"
install -m 0755 "$tmp_dir/${os}-${arch}/helm" "$BIN_DIR/helm"

kubeconform_archive="$(download_and_verify "kubeconform.tar.gz" "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-${os}-${arch}.tar.gz" "$KUBECONFORM_LINUX_AMD64_SHA256")"
tar -xzf "$kubeconform_archive" -C "$tmp_dir" kubeconform
install -m 0755 "$tmp_dir/kubeconform" "$BIN_DIR/kubeconform"

if [ -n "${GITHUB_PATH:-}" ]; then
  printf '%s\n' "$BIN_DIR" >>"$GITHUB_PATH"
else
  printf '[info] Add %s to PATH for Helm and kubeconform.\n' "$BIN_DIR"
fi

printf '[ok] Installed Helm %s and kubeconform %s into %s\n' "$HELM_VERSION" "$KUBECONFORM_VERSION" "$BIN_DIR"
