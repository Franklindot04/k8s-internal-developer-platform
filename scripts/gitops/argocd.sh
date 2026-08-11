#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
KIND_VERSION_FILE="$ROOT/infra/kubernetes/kind/versions.env"
ARGOCD_VERSION_FILE="$ROOT/infra/gitops/argocd/versions.env"
APP_PROJECT_FILE="$ROOT/infra/gitops/argocd/appproject.yaml"
APPLICATION_FILE="$ROOT/infra/gitops/argocd/application.yaml"

# shellcheck disable=SC1090
. "$KIND_VERSION_FILE"
# shellcheck disable=SC1090
. "$ARGOCD_VERSION_FILE"

WAIT_TIMEOUT="${WAIT_TIMEOUT:-180s}"
GITOPS_SYNC_TIMEOUT_SECONDS="${GITOPS_SYNC_TIMEOUT_SECONDS:-240}"
BOOTSTRAP_CONFIGMAP="platform-bootstrap-metadata"

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

sha256_file() {
  file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

require_cluster() {
  require_command kubectl

  current_context="$(kubectl config current-context 2>/dev/null || true)"
  if [ "$current_context" != "$KIND_CONTEXT" ]; then
    fail "Refusing to continue on Kubernetes context '${current_context:-unset}'; expected '$KIND_CONTEXT'."
  fi

  kubectl cluster-info --context "$KIND_CONTEXT" >/dev/null
  kubectl get --raw='/readyz' --context "$KIND_CONTEXT" >/dev/null
}

validate_cluster_shape() {
  require_cluster

  kubectl wait --context "$KIND_CONTEXT" --for=condition=Ready nodes --all --timeout="$WAIT_TIMEOUT"

  node_count="$(kubectl get nodes --context "$KIND_CONTEXT" --no-headers | wc -l | tr -d ' ')"
  [ "$node_count" -eq 3 ] || fail "Expected 3 Kind nodes, found $node_count."

  control_plane_count="$(kubectl get nodes --context "$KIND_CONTEXT" -l node-role.kubernetes.io/control-plane --no-headers | wc -l | tr -d ' ')"
  [ "$control_plane_count" -eq 1 ] || fail "Expected 1 control-plane node, found $control_plane_count."

  worker_count="$(kubectl get nodes --context "$KIND_CONTEXT" -l '!node-role.kubernetes.io/control-plane' --no-headers | wc -l | tr -d ' ')"
  [ "$worker_count" -eq 2 ] || fail "Expected 2 worker nodes, found $worker_count."
}

download_verified_manifest() {
  manifest="$1"
  require_command curl

  curl -fsSL "$ARGOCD_INSTALL_MANIFEST_URL" -o "$manifest"
  actual_sha="$(sha256_file "$manifest")"
  if [ "$actual_sha" != "$ARGOCD_INSTALL_MANIFEST_SHA256" ]; then
    fail "Checksum mismatch for Argo CD install manifest."
  fi
}

wait_for_control_plane() {
  kubectl wait --context "$KIND_CONTEXT" --for=condition=Established crd/applications.argoproj.io --timeout="$WAIT_TIMEOUT"
  kubectl wait --context "$KIND_CONTEXT" --for=condition=Established crd/appprojects.argoproj.io --timeout="$WAIT_TIMEOUT"
  kubectl wait --context "$KIND_CONTEXT" --for=condition=Established crd/applicationsets.argoproj.io --timeout="$WAIT_TIMEOUT"

  for deployment in argocd-applicationset-controller argocd-dex-server argocd-notifications-controller argocd-redis argocd-repo-server argocd-server; do
    kubectl -n "$ARGOCD_NAMESPACE" rollout status "deployment/$deployment" --context "$KIND_CONTEXT" --timeout="$WAIT_TIMEOUT"
  done

  kubectl -n "$ARGOCD_NAMESPACE" rollout status statefulset/argocd-application-controller --context "$KIND_CONTEXT" --timeout="$WAIT_TIMEOUT"
  kubectl -n "$ARGOCD_NAMESPACE" wait --for=condition=Ready pods --all --context "$KIND_CONTEXT" --timeout="$WAIT_TIMEOUT"
}

install_argocd() {
  require_cluster
  validate_cluster_shape

  kubectl create namespace "$ARGOCD_NAMESPACE" --context "$KIND_CONTEXT" --dry-run=client -o yaml |
    kubectl apply --context "$KIND_CONTEXT" -f -

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  manifest="$tmp_dir/argocd-install.yaml"
  download_verified_manifest "$manifest"

  info "Installing Argo CD $ARGOCD_VERSION from verified non-HA manifest."
  kubectl apply --context "$KIND_CONTEXT" -n "$ARGOCD_NAMESPACE" --server-side --force-conflicts -f "$manifest"
  wait_for_control_plane
  info "Argo CD control plane is ready in namespace $ARGOCD_NAMESPACE."
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

  fail "Invalid GitOps target revision '$revision'. Use 'main' or a full lowercase 40-character commit SHA."
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

bootstrap_gitops() {
  revision="${GITOPS_TARGET_REVISION:-$GITOPS_DEFAULT_TARGET_REVISION}"
  validate_revision "$revision"

  require_cluster
  wait_for_control_plane

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  rendered_application="$tmp_dir/application.yaml"
  render_application "$revision" "$rendered_application"

  kubectl apply --context "$KIND_CONTEXT" -f "$APP_PROJECT_FILE"
  kubectl apply --context "$KIND_CONTEXT" -f "$rendered_application"

  wait_for_application
  info "GitOps bootstrap Application is synchronized at target revision $revision."
}

application_jsonpath() {
  path="$1"
  kubectl -n "$ARGOCD_NAMESPACE" get application "$GITOPS_BOOTSTRAP_APPLICATION" --context "$KIND_CONTEXT" -o "jsonpath=$path" 2>/dev/null || true
}

wait_for_application() {
  require_cluster
  deadline="$(( $(date +%s) + GITOPS_SYNC_TIMEOUT_SECONDS ))"

  while [ "$(date +%s)" -le "$deadline" ]; do
    sync_status="$(application_jsonpath '{.status.sync.status}')"
    health_status="$(application_jsonpath '{.status.health.status}')"
    cm_value="$(kubectl -n "$GITOPS_BOOTSTRAP_NAMESPACE" get configmap "$BOOTSTRAP_CONFIGMAP" --context "$KIND_CONTEXT" -o jsonpath='{.data.expected-state}' 2>/dev/null || true)"

    if [ "$sync_status" = "Synced" ] && [ "$health_status" = "Healthy" ] && [ "$cm_value" = "git-declared" ]; then
      return 0
    fi

    sleep 5
  done

  status_gitops || true
  fail "GitOps bootstrap Application did not become Healthy and Synced before timeout."
}

status_gitops() {
  require_cluster
  validate_cluster_shape

  info "Argo CD namespace: $ARGOCD_NAMESPACE"
  kubectl get namespace "$ARGOCD_NAMESPACE" --context "$KIND_CONTEXT"
  kubectl -n "$ARGOCD_NAMESPACE" get deployment,statefulset,service --context "$KIND_CONTEXT"

  if kubectl -n "$ARGOCD_NAMESPACE" get application "$GITOPS_BOOTSTRAP_APPLICATION" --context "$KIND_CONTEXT" >/dev/null 2>&1; then
    sync_status="$(application_jsonpath '{.status.sync.status}')"
    health_status="$(application_jsonpath '{.status.health.status}')"
    revision="$(application_jsonpath '{.status.sync.revision}')"
    info "Application sync: ${sync_status:-unknown}"
    info "Application health: ${health_status:-unknown}"
    info "Application resolved revision: ${revision:-unknown}"
  else
    info "Application $GITOPS_BOOTSTRAP_APPLICATION is not installed."
  fi

  if kubectl -n "$GITOPS_BOOTSTRAP_NAMESPACE" get configmap "$BOOTSTRAP_CONFIGMAP" --context "$KIND_CONTEXT" >/dev/null 2>&1; then
    kubectl -n "$GITOPS_BOOTSTRAP_NAMESPACE" get configmap "$BOOTSTRAP_CONFIGMAP" --context "$KIND_CONTEXT" -o jsonpath='[info] Bootstrap ConfigMap expected-state: {.data.expected-state}{"\n"}'
  else
    info "Bootstrap ConfigMap is not present."
  fi
}

validate_gitops() {
  require_cluster
  validate_cluster_shape

  kubectl get namespace "$ARGOCD_NAMESPACE" --context "$KIND_CONTEXT" >/dev/null
  kubectl get crd applications.argoproj.io appprojects.argoproj.io applicationsets.argoproj.io --context "$KIND_CONTEXT" >/dev/null

  for deployment in argocd-applicationset-controller argocd-dex-server argocd-notifications-controller argocd-redis argocd-repo-server argocd-server; do
    kubectl -n "$ARGOCD_NAMESPACE" get "deployment/$deployment" --context "$KIND_CONTEXT" >/dev/null
    kubectl -n "$ARGOCD_NAMESPACE" rollout status "deployment/$deployment" --context "$KIND_CONTEXT" --timeout="$WAIT_TIMEOUT" >/dev/null
  done

  kubectl -n "$ARGOCD_NAMESPACE" get statefulset/argocd-application-controller --context "$KIND_CONTEXT" >/dev/null
  kubectl -n "$ARGOCD_NAMESPACE" rollout status statefulset/argocd-application-controller --context "$KIND_CONTEXT" --timeout="$WAIT_TIMEOUT" >/dev/null

  for service in argocd-applicationset-controller argocd-dex-server argocd-metrics argocd-notifications-controller-metrics argocd-redis argocd-repo-server argocd-server argocd-server-metrics; do
    kubectl -n "$ARGOCD_NAMESPACE" get "service/$service" --context "$KIND_CONTEXT" >/dev/null
  done

  kubectl -n "$ARGOCD_NAMESPACE" wait --for=condition=Ready pods --all --context "$KIND_CONTEXT" --timeout="$WAIT_TIMEOUT" >/dev/null
  kubectl -n "$ARGOCD_NAMESPACE" get appproject "$GITOPS_BOOTSTRAP_PROJECT" --context "$KIND_CONTEXT" >/dev/null
  kubectl -n "$ARGOCD_NAMESPACE" get application "$GITOPS_BOOTSTRAP_APPLICATION" --context "$KIND_CONTEXT" >/dev/null

  wait_for_application
  info "GitOps control plane and bootstrap state are valid."
}

test_reconciliation() {
  require_cluster
  validate_gitops

  info "Introducing harmless ConfigMap drift."
  kubectl -n "$GITOPS_BOOTSTRAP_NAMESPACE" patch configmap "$BOOTSTRAP_CONFIGMAP" --context "$KIND_CONTEXT" \
    --type merge -p '{"data":{"expected-state":"runtime-drift"}}' >/dev/null

  wait_for_application

  restored_value="$(kubectl -n "$GITOPS_BOOTSTRAP_NAMESPACE" get configmap "$BOOTSTRAP_CONFIGMAP" --context "$KIND_CONTEXT" -o jsonpath='{.data.expected-state}')"
  [ "$restored_value" = "git-declared" ] || fail "Argo CD did not restore ConfigMap drift."
  info "Argo CD restored the drifted ConfigMap field."

  info "Deleting managed ConfigMap to prove self-healing recreation."
  kubectl -n "$GITOPS_BOOTSTRAP_NAMESPACE" delete configmap "$BOOTSTRAP_CONFIGMAP" --context "$KIND_CONTEXT" --wait=true --timeout="$WAIT_TIMEOUT" >/dev/null

  wait_for_application

  recreated_value="$(kubectl -n "$GITOPS_BOOTSTRAP_NAMESPACE" get configmap "$BOOTSTRAP_CONFIGMAP" --context "$KIND_CONTEXT" -o jsonpath='{.data.expected-state}')"
  [ "$recreated_value" = "git-declared" ] || fail "Argo CD did not recreate the ConfigMap with Git-declared content."
  info "Argo CD recreated the managed ConfigMap with Git-declared content."
}

delete_gitops() {
  require_cluster

  if kubectl -n "$ARGOCD_NAMESPACE" get application "$GITOPS_BOOTSTRAP_APPLICATION" --context "$KIND_CONTEXT" >/dev/null 2>&1; then
    kubectl -n "$ARGOCD_NAMESPACE" patch application "$GITOPS_BOOTSTRAP_APPLICATION" --context "$KIND_CONTEXT" \
      --type merge -p '{"metadata":{"finalizers":null}}' >/dev/null || true
    kubectl -n "$ARGOCD_NAMESPACE" delete application "$GITOPS_BOOTSTRAP_APPLICATION" --context "$KIND_CONTEXT" --ignore-not-found --wait=true --timeout="$WAIT_TIMEOUT"
  fi

  kubectl delete namespace "$GITOPS_BOOTSTRAP_NAMESPACE" --context "$KIND_CONTEXT" --ignore-not-found --wait=true --timeout="$WAIT_TIMEOUT"

  if kubectl -n "$ARGOCD_NAMESPACE" get appproject "$GITOPS_BOOTSTRAP_PROJECT" --context "$KIND_CONTEXT" >/dev/null 2>&1; then
    kubectl -n "$ARGOCD_NAMESPACE" delete appproject "$GITOPS_BOOTSTRAP_PROJECT" --context "$KIND_CONTEXT" --ignore-not-found --wait=true --timeout="$WAIT_TIMEOUT"
  fi

  kubectl delete namespace "$ARGOCD_NAMESPACE" --context "$KIND_CONTEXT" --ignore-not-found --wait=true --timeout="$WAIT_TIMEOUT"
  kubectl get --raw='/readyz' --context "$KIND_CONTEXT" >/dev/null
  validate_cluster_shape
  info "Stage 3 GitOps state removed; Kind cluster $KIND_CLUSTER_NAME remains healthy."
}

usage() {
  printf 'Usage: %s {install|bootstrap|status|validate|test-reconciliation|delete}\n' "$0" >&2
}

case "${1:-}" in
  install)
    install_argocd
    ;;
  bootstrap)
    bootstrap_gitops
    ;;
  status)
    status_gitops
    ;;
  validate)
    validate_gitops
    ;;
  test-reconciliation)
    test_reconciliation
    ;;
  delete)
    delete_gitops
    ;;
  *)
    usage
    exit 2
    ;;
esac
