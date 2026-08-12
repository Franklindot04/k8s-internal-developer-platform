#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
CHART_DIR="$ROOT/platform/helm-charts/golden-path"
FIXTURE_DIR="$ROOT/tools/platformctl/tests/fixtures/values"
RENDER_DIR="${RENDER_DIR:-${TMPDIR:-/tmp}/service-values-render}"
NAMESPACE="service-values-review"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '[error] Required command not found: %s\n' "$1" >&2
    exit 1
  }
}

verify_tools() {
  require_command helm
  require_command ruby
  bash "$ROOT/scripts/helm/validate-golden-path.sh" verify-tools
}

render_fixture() {
  fixture="$1"
  values="$FIXTURE_DIR/$fixture/expected-values.yaml"
  output="$RENDER_DIR/$fixture.yaml"

  helm lint --strict "$CHART_DIR" -f "$values"
  helm template "$fixture" "$CHART_DIR" --namespace "$NAMESPACE" --values "$values" >"$output"
  ruby "$ROOT/scripts/helm/assert-service-values-render.rb" "$output" "$fixture"
}

validate_all() {
  verify_tools
  mkdir -p "$RENDER_DIR"
  for fixture in large-profile minimal-single standard-config standard-secrets; do
    render_fixture "$fixture"
  done
  printf '[ok] PlatformService generated values are Helm-compatible with the golden-path chart.\n'
}

case "${1:-validate}" in
  validate)
    validate_all
    ;;
  *)
    printf 'Usage: %s {validate}\n' "$0" >&2
    exit 2
    ;;
esac
