#!/usr/bin/env bash
set -euo pipefail

readonly IMAGE_TAG="idp/supply-chain-fixture:test"
readonly PLATFORM="linux/amd64"

SMOKE_CONTAINER_ID=""
SMOKE_RESPONSE_FILE=""

repo_root() {
  git rev-parse --show-toplevel
}

fixture_dir() {
  printf '%s/tests/fixtures/supply-chain-fixture\n' "$(repo_root)"
}

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf '[error] required tool missing: %s\n' "$tool" >&2
    exit 1
  fi
}

require_docker() {
  require_tool docker
  if ! docker info >/dev/null 2>&1; then
    printf '[error] Docker is required and must be running for this Stage 6B fixture command\n' >&2
    exit 1
  fi
}

source_test() {
  require_docker
  docker build \
    --platform "$PLATFORM" \
    --provenance=false \
    --sbom=false \
    --target test \
    "$(fixture_dir)"
}

image_build() {
  require_docker
  docker build \
    --platform "$PLATFORM" \
    --provenance=false \
    --sbom=false \
    --target runtime \
    --tag "$IMAGE_TAG" \
    "$(fixture_dir)"

  printf '[ok] local image ID: '
  docker image inspect "$IMAGE_TAG" --format '{{.Id}}'
}

container_logs() {
  local container_id="$1"
  if [ -n "$container_id" ] && docker container inspect "$container_id" >/dev/null 2>&1; then
    printf '\n==> Container logs\n' >&2
    docker logs "$container_id" >&2 || true
  fi
}

cleanup_smoke() {
  rm -f "${SMOKE_RESPONSE_FILE:-}"
  if [ -n "${SMOKE_CONTAINER_ID:-}" ] && docker container inspect "$SMOKE_CONTAINER_ID" >/dev/null 2>&1; then
    docker rm -f "$SMOKE_CONTAINER_ID" >/dev/null 2>&1 || true
  fi
}

smoke_test() {
  require_docker
  require_tool curl

  if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    image_build
  fi

  local container_name="idp-supply-chain-fixture-smoke-$$"
  trap cleanup_smoke EXIT INT TERM

  SMOKE_CONTAINER_ID="$(docker run \
    --detach \
    --name "$container_name" \
    --platform "$PLATFORM" \
    --publish 127.0.0.1::8080 \
    "$IMAGE_TAG")"

  local port=""
  SMOKE_RESPONSE_FILE="$(mktemp)"

  local ready=0
  for _ in $(seq 1 30); do
    port="$(docker port "$SMOKE_CONTAINER_ID" 8080/tcp | awk -F: 'NR == 1 { print $NF }')"
    if [ -n "$port" ] && curl -fsS -o "$SMOKE_RESPONSE_FILE" -w '%{http_code}' "http://127.0.0.1:$port/healthz" 2>/dev/null | grep -qx '200'; then
      ready=1
      break
    fi
    sleep 1
  done

  if [ "$ready" -ne 1 ]; then
    container_logs "$SMOKE_CONTAINER_ID"
    printf '[error] fixture did not become ready on /healthz within the timeout\n' >&2
    exit 1
  fi

  if ! printf 'ok\n' | cmp -s "$SMOKE_RESPONSE_FILE" -; then
    container_logs "$SMOKE_CONTAINER_ID"
    printf '[error] /healthz body did not exactly match ok\\n\n' >&2
    exit 1
  fi

  local runtime_user=""
  runtime_user="$(docker inspect "$SMOKE_CONTAINER_ID" --format '{{.Config.User}}')"
  if [ "$runtime_user" != "65532:65532" ]; then
    container_logs "$SMOKE_CONTAINER_ID"
    printf '[error] runtime user = %s, want 65532:65532\n' "$runtime_user" >&2
    exit 1
  fi

  docker stop --time 10 "$SMOKE_CONTAINER_ID" >/dev/null

  local exit_code=""
  exit_code="$(docker inspect "$SMOKE_CONTAINER_ID" --format '{{.State.ExitCode}}')"
  if [ "$exit_code" != "0" ]; then
    container_logs "$SMOKE_CONTAINER_ID"
    printf '[error] container exit code after docker stop = %s, want 0\n' "$exit_code" >&2
    exit 1
  fi

  docker rm "$SMOKE_CONTAINER_ID" >/dev/null
  SMOKE_CONTAINER_ID=""
  rm -f "$SMOKE_RESPONSE_FILE"
  SMOKE_RESPONSE_FILE=""

  printf '[ok] runtime smoke passed on %s with non-root user 65532:65532 and graceful shutdown exit code 0\n' "$PLATFORM"
}

validate() {
  source_test
  image_build
  smoke_test
}

usage() {
  printf 'Usage: %s {test|build|smoke|validate}\n' "$0" >&2
}

case "${1:-}" in
  test)
    source_test
    ;;
  build)
    image_build
    ;;
  smoke)
    smoke_test
    ;;
  validate)
    validate
    ;;
  *)
    usage
    exit 2
    ;;
esac
