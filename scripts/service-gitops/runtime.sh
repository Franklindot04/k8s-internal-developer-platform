#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
KIND_VERSION_FILE="$ROOT/infra/kubernetes/kind/versions.env"
ARGOCD_VERSION_FILE="$ROOT/infra/gitops/argocd/versions.env"
APP_PROJECT_FILE="$ROOT/infra/gitops/self-service/appproject.yaml"
TEST_SERVICE_FILE="$ROOT/tools/platformctl/tests/fixtures/values/minimal-single/services/minimal-api/service.yaml"
TEST_VALUES_FILE="$ROOT/tools/platformctl/tests/fixtures/values/minimal-single/expected-values.yaml"

# shellcheck disable=SC1090
. "$KIND_VERSION_FILE"
# shellcheck disable=SC1090
. "$ARGOCD_VERSION_FILE"

SERVICE_GITOPS_APPLICATION="minimal-api"
SERVICE_GITOPS_NAMESPACE="svc-minimal-api"
SERVICE_GITOPS_FORBIDDEN_APPLICATION="minimal-api-forbidden"
SERVICE_GITOPS_SYNC_TIMEOUT_SECONDS="${SERVICE_GITOPS_SYNC_TIMEOUT_SECONDS:-300}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-180s}"
PYTHON_BIN="${PYTHON:-python3}"

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

require_cluster() {
  require_command kubectl

  current_context="$(kubectl config current-context 2>/dev/null || true)"
  [ "$current_context" = "$KIND_CONTEXT" ] || fail "Refusing to continue on Kubernetes context '${current_context:-unset}'; expected '$KIND_CONTEXT'."

  kubectl cluster-info --context "$KIND_CONTEXT" >/dev/null
  kubectl get --raw='/readyz' --context "$KIND_CONTEXT" >/dev/null
}

validate_argocd_control_plane() {
  require_cluster

  kubectl get namespace "$ARGOCD_NAMESPACE" --context "$KIND_CONTEXT" >/dev/null
  kubectl wait --context "$KIND_CONTEXT" --for=condition=Established crd/applications.argoproj.io --timeout="$WAIT_TIMEOUT" >/dev/null
  kubectl wait --context "$KIND_CONTEXT" --for=condition=Established crd/appprojects.argoproj.io --timeout="$WAIT_TIMEOUT" >/dev/null

  for deployment in argocd-applicationset-controller argocd-dex-server argocd-notifications-controller argocd-redis argocd-repo-server argocd-server; do
    kubectl -n "$ARGOCD_NAMESPACE" get "deployment/$deployment" --context "$KIND_CONTEXT" >/dev/null
    kubectl -n "$ARGOCD_NAMESPACE" rollout status "deployment/$deployment" --context "$KIND_CONTEXT" --timeout="$WAIT_TIMEOUT" >/dev/null
  done

  kubectl -n "$ARGOCD_NAMESPACE" get statefulset/argocd-application-controller --context "$KIND_CONTEXT" >/dev/null
  kubectl -n "$ARGOCD_NAMESPACE" rollout status statefulset/argocd-application-controller --context "$KIND_CONTEXT" --timeout="$WAIT_TIMEOUT" >/dev/null
  kubectl -n "$ARGOCD_NAMESPACE" wait --for=condition=Ready pods --all --context "$KIND_CONTEXT" --timeout="$WAIT_TIMEOUT" >/dev/null
  info "Argo CD control plane is ready for isolated Service GitOps validation."
}

validate_revision() {
  revision="$1"
  case "$revision" in
    main)
      return 0
      ;;
  esac

  if printf '%s' "$revision" | grep -Eq '^[0-9a-f]{40}$'; then
    return 0
  fi

  fail "Invalid Service GitOps target revision '$revision'. Use 'main' or a full lowercase 40-character commit SHA."
}

render_application() {
  revision="$1"
  destination_namespace="$2"
  name="$3"
  output="$4"
  validate_revision "$revision"

  PYTHONPATH="$ROOT/tools/platformctl/src" "$PYTHON_BIN" - "$TEST_SERVICE_FILE" "$TEST_VALUES_FILE" "$revision" "$destination_namespace" "$name" "$output" <<'PY'
from __future__ import annotations

import sys
import os
from pathlib import Path

from platformctl.service_gitops import compile_application, load_gitops_policy, render_application_yaml
from platformctl.service_values import ROOT, normalize_service
from platformctl.validation import load_service_yaml, validate_service_document

service_file = Path(sys.argv[1])
test_values_file = Path(sys.argv[2])
revision = sys.argv[3]
destination_namespace = sys.argv[4]
name = sys.argv[5]
output = Path(sys.argv[6])

document = load_service_yaml(service_file)
validate_service_document(document)
policy = load_gitops_policy()
application = compile_application(normalize_service(document), policy)

chart_root = (ROOT / policy.chart_path).resolve()
values_path = test_values_file.resolve()
repo_root = ROOT.resolve()
if repo_root not in [values_path, *values_path.parents]:
    raise SystemExit("test values path escapes the repository")
relative_values = Path(os.path.relpath(values_path, chart_root))
if relative_values.is_absolute() or (chart_root / relative_values).resolve() != values_path:
    raise SystemExit("test values path does not resolve from the chart root")

application["metadata"]["name"] = name
application["spec"]["source"]["targetRevision"] = revision
application["spec"]["source"]["helm"]["valueFiles"] = [relative_values.as_posix()]
application["spec"]["destination"]["namespace"] = destination_namespace

output.write_text(render_application_yaml(application), encoding="utf-8")
PY
}

application_jsonpath() {
  app="$1"
  path="$2"
  kubectl -n "$ARGOCD_NAMESPACE" get application "$app" --context "$KIND_CONTEXT" -o "jsonpath=$path" 2>/dev/null || true
}

positive_application_conditions() {
  application_jsonpath "$SERVICE_GITOPS_APPLICATION" '{range .status.conditions[*]}{.type}{" "}{.message}{"\n"}{end}'
}

status_field() {
  kind="$1"
  name="$2"
  path="$3"
  kubectl -n "$SERVICE_GITOPS_NAMESPACE" get "$kind" "$name" --context "$KIND_CONTEXT" -o "jsonpath=$path" 2>/dev/null || true
}

wait_for_application() {
  deadline="$(( $(date +%s) + SERVICE_GITOPS_SYNC_TIMEOUT_SECONDS ))"

  while [ "$(date +%s)" -le "$deadline" ]; do
    sync_status="$(application_jsonpath "$SERVICE_GITOPS_APPLICATION" '{.status.sync.status}')"
    health_status="$(application_jsonpath "$SERVICE_GITOPS_APPLICATION" '{.status.health.status}')"
    operation_phase="$(application_jsonpath "$SERVICE_GITOPS_APPLICATION" '{.status.operationState.phase}')"
    resolved_revision="$(application_jsonpath "$SERVICE_GITOPS_APPLICATION" '{.status.sync.revision}')"
    conditions="$(positive_application_conditions)"

    if [ -n "$conditions" ]; then
      printf '[info] Service GitOps Application conditions:\n%s\n' "$conditions"
    fi
    printf '[info] Service GitOps sync=%s health=%s operation=%s revision=%s\n' "${sync_status:-unknown}" "${health_status:-unknown}" "${operation_phase:-unknown}" "${resolved_revision:-unknown}"

    revision_ok=false
    if [ "${SERVICE_GITOPS_EFFECTIVE_REVISION:-main}" = "main" ] && [ -n "$resolved_revision" ]; then
      revision_ok=true
    elif [ "$resolved_revision" = "${SERVICE_GITOPS_EFFECTIVE_REVISION:-}" ]; then
      revision_ok=true
    fi

    if [ "$sync_status" = "Synced" ] && [ "$operation_phase" = "Succeeded" ] && [ "$revision_ok" = "true" ] && [ -z "$conditions" ]; then
      return 0
    fi

    sleep 5
  done

  status_runtime || true
  fail "Service GitOps Application did not become Synced with a successful operation before timeout."
}

wait_for_forbidden_destination() {
  deadline="$(( $(date +%s) + 120 ))"

  while [ "$(date +%s)" -le "$deadline" ]; do
    condition_text="$(kubectl -n "$ARGOCD_NAMESPACE" get application "$SERVICE_GITOPS_FORBIDDEN_APPLICATION" --context "$KIND_CONTEXT" -o jsonpath='{range .status.conditions[*]}{.type}{" "}{.message}{"\n"}{end}' 2>/dev/null || true)"
    if printf '%s\n' "$condition_text" | grep -Fq 'InvalidSpecError' &&
      printf '%s\n' "$condition_text" | grep -Fq 'destination' &&
      printf '%s\n' "$condition_text" | grep -Fq 'allowed destinations' &&
      printf '%s\n' "$condition_text" | grep -Fq "project 'self-service'"; then
      printf '[info] Forbidden destination rejected by self-service AppProject:\n%s\n' "$condition_text"
      return 0
    fi
    sleep 5
  done

  printf '[error] Expected forbidden destination policy rejection was not observed.\n' >&2
  printf '[error] Conditions:\n%s\n' "${condition_text:-none}" >&2
  kubectl -n "$ARGOCD_NAMESPACE" get application "$SERVICE_GITOPS_FORBIDDEN_APPLICATION" --context "$KIND_CONTEXT" -o jsonpath='[error] Project: {.spec.project}{"\n"}[error] Destination server: {.spec.destination.server}{"\n"}[error] Destination namespace: {.spec.destination.namespace}{"\n"}[error] Sync status: {.status.sync.status}{"\n"}' >&2 || true
  kubectl -n "$ARGOCD_NAMESPACE" get application "$SERVICE_GITOPS_FORBIDDEN_APPLICATION" --context "$KIND_CONTEXT" -o yaml || true
  fail "Forbidden destination Application was not rejected by the self-service AppProject."
}

validate_runtime() {
  revision="${SERVICE_GITOPS_TARGET_REVISION:-main}"
  SERVICE_GITOPS_EFFECTIVE_REVISION="$revision"
  validate_revision "$revision"
  require_command "$PYTHON_BIN"
  validate_argocd_control_plane

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  application="$tmp_dir/application.yaml"
  forbidden_application="$tmp_dir/application-forbidden.yaml"

  render_application "$revision" "$SERVICE_GITOPS_NAMESPACE" "$SERVICE_GITOPS_APPLICATION" "$application"
  render_application "$revision" default "$SERVICE_GITOPS_FORBIDDEN_APPLICATION" "$forbidden_application"

  kubectl apply --context "$KIND_CONTEXT" --server-side --dry-run=server -f "$APP_PROJECT_FILE" >/dev/null
  kubectl apply --context "$KIND_CONTEXT" -f "$APP_PROJECT_FILE"
  kubectl apply --context "$KIND_CONTEXT" --server-side --dry-run=server -f "$application" >/dev/null
  kubectl apply --context "$KIND_CONTEXT" -f "$application"

  wait_for_application

  kubectl get namespace "$SERVICE_GITOPS_NAMESPACE" --context "$KIND_CONTEXT" >/dev/null
  kubectl -n "$SERVICE_GITOPS_NAMESPACE" get deployment "$SERVICE_GITOPS_APPLICATION" --context "$KIND_CONTEXT" >/dev/null
  kubectl -n "$SERVICE_GITOPS_NAMESPACE" get service "$SERVICE_GITOPS_APPLICATION" --context "$KIND_CONTEXT" >/dev/null
  kubectl -n "$SERVICE_GITOPS_NAMESPACE" get serviceaccount "$SERVICE_GITOPS_APPLICATION" --context "$KIND_CONTEXT" >/dev/null

  spec_contract="$(application_jsonpath "$SERVICE_GITOPS_APPLICATION" '{.spec.project}{" "}{.spec.source.repoURL}{" "}{.spec.source.targetRevision}{" "}{.spec.source.path}{" "}{.spec.destination.server}{" "}{.spec.destination.namespace}')"
  expected_contract="self-service $GITOPS_REPOSITORY_URL $revision platform/helm-charts/golden-path https://kubernetes.default.svc $SERVICE_GITOPS_NAMESPACE"
  [ "$spec_contract" = "$expected_contract" ] || fail "Service GitOps Application spec contract drifted: $spec_contract"

  deployment_fields="$(status_field deployment "$SERVICE_GITOPS_APPLICATION" '{.spec.replicas}{" "}{.spec.template.spec.containers[0].image}{" "}{.spec.template.spec.containers[0].ports[0].containerPort}{" "}{.spec.template.spec.containers[0].startupProbe.httpGet.path}{" "}{.spec.template.spec.containers[0].readinessProbe.httpGet.path}{" "}{.spec.template.spec.containers[0].livenessProbe.httpGet.path}{" "}{.spec.template.spec.containers[0].resources.requests.cpu}{" "}{.spec.template.spec.containers[0].resources.requests.memory}{" "}{.spec.template.spec.containers[0].resources.limits.cpu}{" "}{.spec.template.spec.containers[0].resources.limits.memory}')"
  expected_fields="1 registry.test/platform/minimal-api@sha256:1111111111111111111111111111111111111111111111111111111111111111 8080 /healthz /healthz /healthz 50m 64Mi 250m 128Mi"
  [ "$deployment_fields" = "$expected_fields" ] || fail "Deployment fields do not match compiler-backed values: $deployment_fields"

  kubectl apply --context "$KIND_CONTEXT" --server-side --dry-run=server -f "$forbidden_application" >/dev/null
  kubectl apply --context "$KIND_CONTEXT" -f "$forbidden_application"
  wait_for_forbidden_destination

  info "Service GitOps runtime proof passed for revision $revision."
}

status_runtime() {
  require_cluster
  kubectl -n "$ARGOCD_NAMESPACE" get application "$SERVICE_GITOPS_APPLICATION" "$SERVICE_GITOPS_FORBIDDEN_APPLICATION" --context "$KIND_CONTEXT" 2>/dev/null || true
  kubectl -n "$SERVICE_GITOPS_NAMESPACE" get deployment,service,serviceaccount,configmap,poddisruptionbudget,pods --context "$KIND_CONTEXT" 2>/dev/null || true
}

delete_runtime() {
  require_cluster

  for application in "$SERVICE_GITOPS_FORBIDDEN_APPLICATION" "$SERVICE_GITOPS_APPLICATION"; do
    kubectl -n "$ARGOCD_NAMESPACE" delete application "$application" --context "$KIND_CONTEXT" --ignore-not-found=true --wait=true --timeout="$WAIT_TIMEOUT" || true
  done

  kubectl delete namespace "$SERVICE_GITOPS_NAMESPACE" --context "$KIND_CONTEXT" --ignore-not-found=true --wait=true --timeout="$WAIT_TIMEOUT" || true
  kubectl -n "$ARGOCD_NAMESPACE" delete appproject self-service --context "$KIND_CONTEXT" --ignore-not-found=true --wait=true --timeout="$WAIT_TIMEOUT" || true
  info "Deleted Service GitOps runtime state."
}

usage() {
  printf 'Usage: %s {validate|status|delete}\n' "$0" >&2
}

case "${1:-}" in
  validate)
    validate_runtime
    ;;
  status)
    status_runtime
    ;;
  delete)
    delete_runtime
    ;;
  *)
    usage
    exit 2
    ;;
esac
