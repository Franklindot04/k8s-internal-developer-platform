#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
KIND_VERSION_FILE="$ROOT/infra/kubernetes/kind/versions.env"
APP_PROJECT_FILE="$ROOT/infra/gitops/golden-path/appproject.yaml"
APPLICATION_FILE="$ROOT/infra/gitops/golden-path/application.yaml"

# shellcheck disable=SC1090
. "$KIND_VERSION_FILE"

ARGOCD_NAMESPACE="argocd"
GOLDEN_PATH_PROJECT="golden-path"
GOLDEN_PATH_APPLICATION="golden-path-demo"
GOLDEN_PATH_NAMESPACE="golden-path-demo"
GOLDEN_PATH_DEPLOYMENT="golden-path-demo-golden-path"
GOLDEN_PATH_SERVICE="golden-path-demo-golden-path"
GOLDEN_PATH_CONFIGMAP="golden-path-demo-golden-path-config"
GOLDEN_PATH_EXPECTED_IMAGE="registry.k8s.io/e2e-test-images/agnhost:2.53@sha256:99c6b4bb4a1e1df3f0b3752168c89358794d02258ebebc26bf21c29399011a85"
GOLDEN_PATH_EXPECTED_CONFIG_VALUE="golden-path-runtime"
GOLDEN_PATH_DEFAULT_TARGET_REVISION="main"
GOLDEN_PATH_SYNC_TIMEOUT_SECONDS="${GOLDEN_PATH_SYNC_TIMEOUT_SECONDS:-300}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-180s}"
PORT_FORWARD_PORT="${GOLDEN_PATH_PORT_FORWARD_PORT:-18080}"

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

  fail "Invalid golden-path target revision '$revision'. Use 'main' or a full lowercase 40-character commit SHA."
}

render_application() {
  revision="$1"
  output="$2"
  validate_revision "$revision"
  awk -v revision="$revision" '
    /^    targetRevision: / {
      print "    targetRevision: " revision
      next
    }
    { print }
  ' "$APPLICATION_FILE" >"$output"
}

application_jsonpath() {
  path="$1"
  kubectl -n "$ARGOCD_NAMESPACE" get application "$GOLDEN_PATH_APPLICATION" --context "$KIND_CONTEXT" -o "jsonpath=$path" 2>/dev/null || true
}

wait_for_application() {
  require_cluster
  deadline="$(( $(date +%s) + GOLDEN_PATH_SYNC_TIMEOUT_SECONDS ))"

  while [ "$(date +%s)" -le "$deadline" ]; do
    sync_status="$(application_jsonpath '{.status.sync.status}')"
    health_status="$(application_jsonpath '{.status.health.status}')"
    ready_replicas="$(kubectl -n "$GOLDEN_PATH_NAMESPACE" get deployment "$GOLDEN_PATH_DEPLOYMENT" --context "$KIND_CONTEXT" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
    config_value="$(kubectl -n "$GOLDEN_PATH_NAMESPACE" get configmap "$GOLDEN_PATH_CONFIGMAP" --context "$KIND_CONTEXT" -o jsonpath='{.data.PLATFORM_PROFILE}' 2>/dev/null || true)"

    if [ "$sync_status" = "Synced" ] && [ "$health_status" = "Healthy" ] && [ "${ready_replicas:-0}" -ge 1 ] && [ "$config_value" = "$GOLDEN_PATH_EXPECTED_CONFIG_VALUE" ]; then
      return 0
    fi

    sleep 5
  done

  status_golden_path || true
  fail "Golden-path Application did not become Healthy and Synced before timeout."
}

bootstrap_golden_path() {
  revision="${GOLDEN_PATH_TARGET_REVISION:-$GOLDEN_PATH_DEFAULT_TARGET_REVISION}"
  validate_revision "$revision"

  require_cluster
  bash "$ROOT/scripts/gitops/argocd.sh" validate

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  rendered_application="$tmp_dir/application.yaml"
  render_application "$revision" "$rendered_application"

  kubectl apply --context "$KIND_CONTEXT" -f "$APP_PROJECT_FILE"
  kubectl apply --context "$KIND_CONTEXT" -f "$rendered_application"

  wait_for_application
  info "Golden-path Application is synchronized at target revision $revision."
}

status_golden_path() {
  require_cluster

  if kubectl -n "$ARGOCD_NAMESPACE" get application "$GOLDEN_PATH_APPLICATION" --context "$KIND_CONTEXT" >/dev/null 2>&1; then
    sync_status="$(application_jsonpath '{.status.sync.status}')"
    health_status="$(application_jsonpath '{.status.health.status}')"
    revision="$(application_jsonpath '{.status.sync.revision}')"
    info "Application sync: ${sync_status:-unknown}"
    info "Application health: ${health_status:-unknown}"
    info "Application resolved revision: ${revision:-unknown}"
  else
    info "Application $GOLDEN_PATH_APPLICATION is not installed."
  fi

  kubectl -n "$GOLDEN_PATH_NAMESPACE" get deployment,service,poddisruptionbudget,endpointslice,pods --context "$KIND_CONTEXT" 2>/dev/null || true
}

pod_names() {
  kubectl -n "$GOLDEN_PATH_NAMESPACE" get pods \
    --context "$KIND_CONTEXT" \
    -l "app.kubernetes.io/name=golden-path,app.kubernetes.io/instance=$GOLDEN_PATH_APPLICATION" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
}

validate_security_contexts() {
  pod_security="$(kubectl -n "$GOLDEN_PATH_NAMESPACE" get deployment "$GOLDEN_PATH_DEPLOYMENT" --context "$KIND_CONTEXT" -o jsonpath='{.spec.template.spec.securityContext.runAsNonRoot} {.spec.template.spec.securityContext.seccompProfile.type}')"
  [ "$pod_security" = "true RuntimeDefault" ] || fail "Deployment pod security context is not locked down."

  container_security="$(kubectl -n "$GOLDEN_PATH_NAMESPACE" get deployment "$GOLDEN_PATH_DEPLOYMENT" --context "$KIND_CONTEXT" -o jsonpath='{.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation} {.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem} {.spec.template.spec.containers[0].securityContext.runAsNonRoot} {.spec.template.spec.containers[0].securityContext.capabilities.drop[0]}')"
  [ "$container_security" = "false true true ALL" ] || fail "Deployment container security context is not locked down."
}

validate_service_routing() {
  selector="$(kubectl -n "$GOLDEN_PATH_NAMESPACE" get service "$GOLDEN_PATH_SERVICE" --context "$KIND_CONTEXT" -o jsonpath='{.spec.selector.app\.kubernetes\.io/name} {.spec.selector.app\.kubernetes\.io/instance}')"
  [ "$selector" = "golden-path $GOLDEN_PATH_APPLICATION" ] || fail "Service selector is not the expected golden-path selector."

  endpoints="$(kubectl -n "$GOLDEN_PATH_NAMESPACE" get endpointslice --context "$KIND_CONTEXT" -l "kubernetes.io/service-name=$GOLDEN_PATH_SERVICE" -o jsonpath='{range .items[*].endpoints[*]}{.conditions.ready}{"\n"}{end}' | grep -c '^true$' || true)"
  [ "$endpoints" -ge 1 ] || fail "Service does not have ready EndpointSlice endpoints."
}

validate_http_response() {
  require_command curl

  kubectl -n "$GOLDEN_PATH_NAMESPACE" port-forward --context "$KIND_CONTEXT" "service/$GOLDEN_PATH_SERVICE" "$PORT_FORWARD_PORT:80" >/tmp/golden-path-port-forward.log 2>&1 &
  port_forward_pid="$!"
  trap 'kill "$port_forward_pid" >/dev/null 2>&1 || true' RETURN

  deadline="$(( $(date +%s) + 60 ))"
  while [ "$(date +%s)" -le "$deadline" ]; do
    if curl -fsS "http://127.0.0.1:$PORT_FORWARD_PORT/healthz" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  cat /tmp/golden-path-port-forward.log >&2 || true
  fail "Golden-path Service did not return a healthy HTTP response."
}

validate_golden_path() {
  require_cluster
  bash "$ROOT/scripts/gitops/argocd.sh" validate
  wait_for_application

  kubectl -n "$GOLDEN_PATH_NAMESPACE" rollout status "deployment/$GOLDEN_PATH_DEPLOYMENT" --context "$KIND_CONTEXT" --timeout="$WAIT_TIMEOUT" >/dev/null
  kubectl -n "$GOLDEN_PATH_NAMESPACE" wait --for=condition=Ready pods --all --context "$KIND_CONTEXT" --timeout="$WAIT_TIMEOUT" >/dev/null

  deployment_image="$(kubectl -n "$GOLDEN_PATH_NAMESPACE" get deployment "$GOLDEN_PATH_DEPLOYMENT" --context "$KIND_CONTEXT" -o jsonpath='{.spec.template.spec.containers[0].image}')"
  [ "$deployment_image" = "$GOLDEN_PATH_EXPECTED_IMAGE" ] || fail "Deployment image is '$deployment_image'; expected '$GOLDEN_PATH_EXPECTED_IMAGE'."

  while IFS= read -r pod; do
    [ -n "$pod" ] || continue
    pod_image="$(kubectl -n "$GOLDEN_PATH_NAMESPACE" get pod "$pod" --context "$KIND_CONTEXT" -o jsonpath='{.spec.containers[0].image}')"
    [ "$pod_image" = "$GOLDEN_PATH_EXPECTED_IMAGE" ] || fail "Pod $pod image is '$pod_image'; expected '$GOLDEN_PATH_EXPECTED_IMAGE'."
  done <<EOF
$(pod_names)
EOF

  validate_security_contexts
  validate_service_routing
  validate_http_response

  config_value="$(kubectl -n "$GOLDEN_PATH_NAMESPACE" get configmap "$GOLDEN_PATH_CONFIGMAP" --context "$KIND_CONTEXT" -o jsonpath='{.data.PLATFORM_PROFILE}')"
  [ "$config_value" = "$GOLDEN_PATH_EXPECTED_CONFIG_VALUE" ] || fail "ConfigMap PLATFORM_PROFILE is '$config_value'."

  kubectl -n "$GOLDEN_PATH_NAMESPACE" get poddisruptionbudget "$GOLDEN_PATH_DEPLOYMENT" --context "$KIND_CONTEXT" >/dev/null
  info "Golden-path runtime reconciliation is valid."
}

delete_golden_path() {
  require_cluster

  if kubectl -n "$ARGOCD_NAMESPACE" get application "$GOLDEN_PATH_APPLICATION" --context "$KIND_CONTEXT" >/dev/null 2>&1; then
    kubectl -n "$ARGOCD_NAMESPACE" delete application "$GOLDEN_PATH_APPLICATION" --context "$KIND_CONTEXT" --wait=true --timeout="$WAIT_TIMEOUT"
  fi

  kubectl delete namespace "$GOLDEN_PATH_NAMESPACE" --context "$KIND_CONTEXT" --ignore-not-found=true --wait=true --timeout="$WAIT_TIMEOUT"
  kubectl -n "$ARGOCD_NAMESPACE" delete appproject "$GOLDEN_PATH_PROJECT" --context "$KIND_CONTEXT" --ignore-not-found=true --wait=true --timeout="$WAIT_TIMEOUT"

  bash "$ROOT/scripts/gitops/argocd.sh" validate
  bash "$ROOT/scripts/kubernetes/cluster.sh" validate
  info "Deleted only Stage 4 golden-path runtime state."
}

usage() {
  printf 'Usage: %s {bootstrap|status|validate|delete}\n' "$0" >&2
}

case "${1:-}" in
  bootstrap)
    bootstrap_golden_path
    ;;
  status)
    status_golden_path
    ;;
  validate)
    validate_golden_path
    ;;
  delete)
    delete_golden_path
    ;;
  *)
    usage
    exit 2
    ;;
esac
