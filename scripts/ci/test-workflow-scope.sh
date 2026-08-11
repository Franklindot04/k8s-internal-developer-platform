#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SCOPE_SCRIPT="$ROOT/scripts/ci/workflow-scope.sh"

fail() {
  printf '[error] %s\n' "$1" >&2
  exit 1
}

assert_scope() {
  name="$1"
  scope="$2"
  expected="$3"
  paths="$4"
  tmp_file="$(mktemp)"
  printf '%s\n' "$paths" >"$tmp_file"

  actual="$("$SCOPE_SCRIPT" "$scope" "$tmp_file")"
  rm -f "$tmp_file"

  if [ "$actual" != "$expected" ]; then
    fail "$name: expected $scope=$expected, got $actual"
  fi
}

unrelated_docs="docs/roadmap/implementation-roadmap.md"
kind_change="infra/kubernetes/kind/cluster.yaml"
gitops_change="infra/gitops/argocd/application.yaml"
golden_path_change="platform/helm-charts/golden-path/values.yaml"
scope_change="scripts/ci/workflow-scope.sh"
kind_workflow_change=".github/workflows/local-kubernetes.yml"
gitops_workflow_change=".github/workflows/gitops-control-plane.yml"
golden_path_workflow_change=".github/workflows/golden-path-helm.yml"

assert_scope "unrelated documentation" kind false "$unrelated_docs"
assert_scope "unrelated documentation" gitops false "$unrelated_docs"
assert_scope "unrelated documentation" golden-path false "$unrelated_docs"

assert_scope "kind foundation" kind true "$kind_change"
assert_scope "kind foundation" gitops true "$kind_change"
assert_scope "kind foundation" golden-path true "$kind_change"

assert_scope "gitops dependency" kind false "$gitops_change"
assert_scope "gitops dependency" gitops true "$gitops_change"
assert_scope "gitops dependency" golden-path true "$gitops_change"

assert_scope "golden-path chart" kind false "$golden_path_change"
assert_scope "golden-path chart" gitops false "$golden_path_change"
assert_scope "golden-path chart" golden-path true "$golden_path_change"

assert_scope "shared governance classifier" kind true "$scope_change"
assert_scope "shared governance classifier" gitops true "$scope_change"
assert_scope "shared governance classifier" golden-path true "$scope_change"

assert_scope "kind workflow" kind true "$kind_workflow_change"
assert_scope "kind workflow" gitops true "$kind_workflow_change"
assert_scope "kind workflow" golden-path true "$kind_workflow_change"

assert_scope "gitops workflow" kind false "$gitops_workflow_change"
assert_scope "gitops workflow" gitops true "$gitops_workflow_change"
assert_scope "gitops workflow" golden-path true "$gitops_workflow_change"

assert_scope "golden-path workflow" kind false "$golden_path_workflow_change"
assert_scope "golden-path workflow" gitops false "$golden_path_workflow_change"
assert_scope "golden-path workflow" golden-path true "$golden_path_workflow_change"

printf '[ok] workflow scope classifier tests passed\n'
