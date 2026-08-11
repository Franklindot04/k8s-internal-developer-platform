#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION_FILE="$ROOT/infra/kubernetes/kind/versions.env"
KIND_CONFIG="$ROOT/infra/kubernetes/kind/cluster.yaml"

# shellcheck disable=SC1090
. "$VERSION_FILE"

EXPECTED_NODE_COUNT=3
EXPECTED_CONTROL_PLANE_COUNT=1
EXPECTED_WORKER_COUNT=2
WAIT_TIMEOUT="${WAIT_TIMEOUT:-180s}"

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

kind_version() {
  kind version 2>/dev/null | awk '{print $2}'
}

kubectl_client_version_field() {
  field="$1"
  kubectl version --client --output=json 2>/dev/null |
    sed -n "s/.*\"$field\":[[:space:]]*\"\([0-9][0-9]*\).*/\1/p" |
    head -n 1
}

cluster_exists() {
  kind get clusters 2>/dev/null | grep -Fx "$KIND_CLUSTER_NAME" >/dev/null 2>&1
}

context_exists() {
  kubectl config get-contexts "$KIND_CONTEXT" >/dev/null 2>&1
}

verify_tools() {
  missing=0

  if ! command -v docker >/dev/null 2>&1; then
    printf '[error] Required command not found: docker\n' >&2
    missing=1
  elif docker info >/dev/null 2>&1; then
    info "Docker daemon is reachable."
  else
    printf '[error] Docker is installed, but the Docker daemon is not reachable.\n' >&2
    missing=1
  fi

  if ! command -v kind >/dev/null 2>&1; then
    printf '[error] Required command not found: kind\n' >&2
    missing=1
  else
    actual_kind_version="$(kind_version)"
    if [ "$actual_kind_version" != "$KIND_VERSION" ]; then
      printf '[error] Kind version %s found; expected %s.\n' "$actual_kind_version" "$KIND_VERSION" >&2
      missing=1
    else
      info "Kind $KIND_VERSION is installed."
    fi
  fi

  if ! command -v kubectl >/dev/null 2>&1; then
    printf '[error] Required command not found: kubectl\n' >&2
    missing=1
  else
    kubectl_major="$(kubectl_client_version_field major)"
    kubectl_minor="$(kubectl_client_version_field minor)"
    if [ -z "$kubectl_major" ] || [ -z "$kubectl_minor" ]; then
      printf '[error] Could not determine kubectl client major/minor version.\n' >&2
      missing=1
    elif [ "$kubectl_major" -ne "$KUBECTL_SUPPORTED_MAJOR" ]; then
      printf '[error] kubectl major version %s is outside supported major version %s.\n' "$kubectl_major" "$KUBECTL_SUPPORTED_MAJOR" >&2
      missing=1
    elif [ "$kubectl_minor" -lt "$KUBECTL_SUPPORTED_MIN_MINOR" ] || [ "$kubectl_minor" -gt "$KUBECTL_SUPPORTED_MAX_MINOR" ]; then
      printf '[error] kubectl minor version %s is outside supported range %s-%s for Kubernetes %s.\n' "$kubectl_minor" "$KUBECTL_SUPPORTED_MIN_MINOR" "$KUBECTL_SUPPORTED_MAX_MINOR" "$KUBERNETES_VERSION" >&2
      missing=1
    else
      info "kubectl client version is compatible with Kubernetes $KUBERNETES_VERSION."
    fi
  fi

  if [ "$missing" -ne 0 ]; then
    fail "Local Kubernetes tool verification failed."
  fi
}

create_cluster() {
  verify_tools

  if cluster_exists; then
    info "Kind cluster $KIND_CLUSTER_NAME already exists; leaving it unchanged."
    validate_cluster
    return
  fi

  info "Creating Kind cluster $KIND_CLUSTER_NAME with Kubernetes $KUBERNETES_VERSION."
  kind create cluster \
    --name "$KIND_CLUSTER_NAME" \
    --config "$KIND_CONFIG" \
    --image "$KIND_NODE_IMAGE" \
    --wait "$WAIT_TIMEOUT"

  validate_cluster
}

status_cluster() {
  require_command kind
  require_command kubectl

  if ! cluster_exists; then
    fail "Kind cluster $KIND_CLUSTER_NAME does not exist."
  fi

  context_exists || fail "Expected kubeconfig context $KIND_CONTEXT does not exist."

  info "Cluster: $KIND_CLUSTER_NAME"
  info "Context: $KIND_CONTEXT"
  kubectl cluster-info --context "$KIND_CONTEXT"
  kubectl get nodes --context "$KIND_CONTEXT" -o wide
}

validate_cluster() {
  require_command kind
  require_command kubectl

  cluster_exists || fail "Expected Kind cluster $KIND_CLUSTER_NAME does not exist."
  context_exists || fail "Expected kubeconfig context $KIND_CONTEXT does not exist."

  kubectl cluster-info --context "$KIND_CONTEXT" >/dev/null

  kubectl wait --context "$KIND_CONTEXT" --for=condition=Ready nodes --all --timeout="$WAIT_TIMEOUT"

  node_count="$(kubectl get nodes --context "$KIND_CONTEXT" --no-headers | wc -l | tr -d ' ')"
  if [ "$node_count" -ne "$EXPECTED_NODE_COUNT" ]; then
    fail "Expected $EXPECTED_NODE_COUNT nodes, found $node_count."
  fi

  control_plane_count="$(kubectl get nodes --context "$KIND_CONTEXT" -l node-role.kubernetes.io/control-plane --no-headers | wc -l | tr -d ' ')"
  if [ "$control_plane_count" -ne "$EXPECTED_CONTROL_PLANE_COUNT" ]; then
    fail "Expected $EXPECTED_CONTROL_PLANE_COUNT control-plane node, found $control_plane_count."
  fi

  worker_count="$(kubectl get nodes --context "$KIND_CONTEXT" -l '!node-role.kubernetes.io/control-plane' --no-headers | wc -l | tr -d ' ')"
  if [ "$worker_count" -ne "$EXPECTED_WORKER_COUNT" ]; then
    fail "Expected $EXPECTED_WORKER_COUNT worker nodes, found $worker_count."
  fi

  kubectl -n kube-system wait --context "$KIND_CONTEXT" --for=condition=Ready pods --all --timeout="$WAIT_TIMEOUT"
  kubectl get --raw='/readyz' --context "$KIND_CONTEXT" >/dev/null

  info "Kind cluster $KIND_CLUSTER_NAME is valid and ready."
}

delete_cluster() {
  require_command kind

  if ! cluster_exists; then
    info "Kind cluster $KIND_CLUSTER_NAME is already absent."
    return
  fi

  info "Deleting Kind cluster $KIND_CLUSTER_NAME."
  kind delete cluster --name "$KIND_CLUSTER_NAME"

  if cluster_exists; then
    fail "Kind cluster $KIND_CLUSTER_NAME still exists after deletion."
  fi

  info "Kind cluster $KIND_CLUSTER_NAME has been deleted."
}

usage() {
  printf 'Usage: %s {verify-tools|create|status|validate|delete}\n' "$0" >&2
}

case "${1:-}" in
  verify-tools)
    verify_tools
    ;;
  create)
    create_cluster
    ;;
  status)
    status_cluster
    ;;
  validate)
    validate_cluster
    ;;
  delete)
    delete_cluster
    ;;
  *)
    usage
    exit 2
    ;;
esac
