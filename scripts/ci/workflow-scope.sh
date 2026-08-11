#!/usr/bin/env bash
set -euo pipefail

scope="${1:-}"
path_file="${2:-/dev/stdin}"

usage() {
  printf 'Usage: %s {kind|gitops|golden-path} [changed-path-file]\n' "$0" >&2
}

case "$scope" in
  kind | gitops | golden-path)
    ;;
  *)
    usage
    exit 2
    ;;
esac

matches_any() {
  path="$1"
  shift

  for pattern in "$@"; do
    # Repository-owned patterns are intentionally expanded as dynamic shell globs.
    # shellcheck disable=SC2254
    case "$path" in
      $pattern)
        return 0
        ;;
    esac
  done

  return 1
}

kind_patterns=(
  ".github/workflows/local-kubernetes.yml"
  "infra/kubernetes/kind/*"
  "scripts/kubernetes/*"
  "scripts/ci/install-local-kubernetes-tools.sh"
  "scripts/ci/workflow-scope.sh"
  "scripts/ci/test-workflow-scope.sh"
  "scripts/validate-workflow-governance.rb"
  "Makefile"
)

gitops_patterns=(
  "${kind_patterns[@]}"
  ".github/workflows/gitops-control-plane.yml"
  "infra/gitops/*"
  "platform/gitops/*"
  "scripts/gitops/*"
)

golden_path_patterns=(
  "${gitops_patterns[@]}"
  ".github/workflows/golden-path-helm.yml"
  "infra/gitops/golden-path/*"
  "platform/helm-charts/*"
  "scripts/ci/install-helm-tools.sh"
  "scripts/helm/*"
  "scripts/golden-path/*"
)

relevant=false

while IFS= read -r path; do
  [ -n "$path" ] || continue

  case "$scope" in
    kind)
      if matches_any "$path" "${kind_patterns[@]}"; then
        relevant=true
        break
      fi
      ;;
    gitops)
      if matches_any "$path" "${gitops_patterns[@]}"; then
        relevant=true
        break
      fi
      ;;
    golden-path)
      if matches_any "$path" "${golden_path_patterns[@]}"; then
        relevant=true
        break
      fi
      ;;
  esac
done <"$path_file"

printf '%s\n' "$relevant"
