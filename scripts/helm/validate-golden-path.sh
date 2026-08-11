#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
CHART_DIR="$ROOT/platform/helm-charts/golden-path"
VERSION_FILE="$ROOT/platform/helm-charts/versions.env"
KIND_VERSION_FILE="$ROOT/infra/kubernetes/kind/versions.env"
RENDER_DIR="${RENDER_DIR:-${TMPDIR:-/tmp}/golden-path-render}"
RELEASE_NAME="golden-path-demo"
NAMESPACE="golden-path-demo"

# shellcheck disable=SC1090
. "$VERSION_FILE"
# shellcheck disable=SC1090
. "$KIND_VERSION_FILE"

fail() {
  printf '[error] %s\n' "$1" >&2
  exit 1
}

info() {
  printf '[info] %s\n' "$1"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

helm_version() {
  helm version --short 2>/dev/null | sed 's/+.*//'
}

kubeconform_version() {
  kubeconform -v 2>/dev/null | awk '{print $NF}'
}

verify_tools() {
  require_command helm
  require_command kubeconform
  require_command ruby

  actual_helm="$(helm_version)"
  [ "$actual_helm" = "$HELM_VERSION" ] || fail "Helm $actual_helm found; expected $HELM_VERSION."

  actual_kubeconform="$(kubeconform_version)"
  [ "$actual_kubeconform" = "$KUBECONFORM_VERSION" ] || fail "kubeconform $actual_kubeconform found; expected $KUBECONFORM_VERSION."

  info "Helm $HELM_VERSION and kubeconform $KUBECONFORM_VERSION are available."
}

lint_chart() {
  verify_tools
  helm lint --strict "$CHART_DIR" -f "$CHART_DIR/tests/values/runtime-kind.yaml"
  helm lint --strict "$CHART_DIR" -f "$CHART_DIR/tests/values/feature-complete.yaml"

  if helm lint --strict "$CHART_DIR" -f "$CHART_DIR/tests/values/invalid-image.yaml" >/tmp/golden-path-invalid-lint.log 2>&1; then
    cat /tmp/golden-path-invalid-lint.log >&2
    fail "Invalid values fixture unexpectedly passed Helm schema validation."
  fi

  info "Helm lint and invalid fixture rejection passed."
}

render_profile() {
  profile="$1"
  output="$2"
  helm template "$RELEASE_NAME" "$CHART_DIR" \
    --namespace "$NAMESPACE" \
    --values "$CHART_DIR/tests/values/${profile}.yaml" >"$output"
}

render_chart() {
  verify_tools
  mkdir -p "$RENDER_DIR"
  render_profile runtime-kind "$RENDER_DIR/runtime-kind.yaml"
  render_profile feature-complete "$RENDER_DIR/feature-complete.yaml"
  info "Rendered golden-path chart profiles into $RENDER_DIR."
}

schema_validate() {
  render_chart
  kubeconform \
    -strict \
    -summary \
    -kubernetes-version "$KUBECONFORM_KUBERNETES_VERSION" \
    "$RENDER_DIR/runtime-kind.yaml" \
    "$RENDER_DIR/feature-complete.yaml"
}

assert_rendered_contract() {
  render_chart
  ruby "$ROOT/scripts/helm/assert-golden-path-render.rb" "$RENDER_DIR/runtime-kind.yaml" "$RENDER_DIR/feature-complete.yaml"
}

server_dry_run() {
  require_command kubectl
  verify_tools

  current_context="$(kubectl config current-context 2>/dev/null || true)"
  [ "$current_context" = "$KIND_CONTEXT" ] || fail "Refusing to continue on Kubernetes context '${current_context:-unset}'; expected '$KIND_CONTEXT'."

  kubectl create namespace "$NAMESPACE" --context "$KIND_CONTEXT" --dry-run=client -o yaml |
    kubectl apply --context "$KIND_CONTEXT" -f -

  mkdir -p "$RENDER_DIR"
  render_profile runtime-kind "$RENDER_DIR/runtime-kind.yaml"
  kubectl apply --context "$KIND_CONTEXT" --namespace "$NAMESPACE" --dry-run=server -f "$RENDER_DIR/runtime-kind.yaml"
  info "Golden-path runtime render passed Kubernetes server-side dry-run."
}

validate_all() {
  lint_chart
  schema_validate
  assert_rendered_contract
  info "Golden-path Helm validation passed."
}

usage() {
  printf 'Usage: %s {verify-tools|lint|render|schema|assert|server-dry-run|validate}\n' "$0" >&2
}

case "${1:-}" in
  verify-tools)
    verify_tools
    ;;
  lint)
    lint_chart
    ;;
  render)
    render_chart
    ;;
  schema)
    schema_validate
    ;;
  assert)
    assert_rendered_contract
    ;;
  server-dry-run)
    server_dry_run
    ;;
  validate)
    validate_all
    ;;
  *)
    usage
    exit 2
    ;;
esac
