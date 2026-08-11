#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION_FILE="$ROOT/infra/kubernetes/kind/versions.env"
BIN_DIR="${RUNNER_TEMP:-/tmp}/idp-local-bin"

# shellcheck disable=SC1090
. "$VERSION_FILE"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    os=linux
    arch=amd64
    kind_sha="$KIND_LINUX_AMD64_SHA256"
    kubectl_sha="$KUBECTL_LINUX_AMD64_SHA256"
    ;;
  *)
    printf '[error] CI installer supports Linux amd64 runners only.\n' >&2
    exit 1
    ;;
esac

mkdir -p "$BIN_DIR"

download_and_verify() {
  name="$1"
  url="$2"
  expected_sha="$3"
  output="$BIN_DIR/$name"

  curl -fsSL "$url" -o "$output"
  actual_sha="$(sha256sum "$output" | awk '{print $1}')"
  if [ "$actual_sha" != "$expected_sha" ]; then
    printf '[error] checksum mismatch for %s\n' "$name" >&2
    exit 1
  fi
  chmod +x "$output"
}

download_and_verify kind "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-${os}-${arch}" "$kind_sha"
download_and_verify kubectl "https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/${os}/${arch}/kubectl" "$kubectl_sha"

printf '%s\n' "$BIN_DIR" >> "$GITHUB_PATH"
printf '[ok] Installed Kind %s and kubectl %s into %s\n' "$KIND_VERSION" "$KUBERNETES_VERSION" "$BIN_DIR"
