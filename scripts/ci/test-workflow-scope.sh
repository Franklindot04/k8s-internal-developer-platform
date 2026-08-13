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

unrelated_docs="CONTRIBUTING.md"
kind_change="infra/kubernetes/kind/cluster.yaml"
gitops_change="infra/gitops/argocd/application.yaml"
golden_path_change="platform/helm-charts/golden-path/values.yaml"
service_gitops_change="tools/platformctl/src/platformctl/service_gitops.py"
service_contract_change="platform/self-service/service.schema.json"
service_gitops_workflow_change=".github/workflows/service-gitops.yml"
service_gitops_script_change="scripts/service-gitops/runtime.sh"
scope_change="scripts/ci/workflow-scope.sh"
kind_workflow_change=".github/workflows/local-kubernetes.yml"
gitops_workflow_change=".github/workflows/gitops-control-plane.yml"
golden_path_workflow_change=".github/workflows/golden-path-helm.yml"
supply_chain_fixture_source_change="tests/fixtures/supply-chain-fixture/cmd/server/main.go"
supply_chain_fixture_dockerfile_change="tests/fixtures/supply-chain-fixture/Dockerfile"
supply_chain_script_change="scripts/supply-chain/evidence.sh"
supply_chain_policy_fixture_change="tests/fixtures/supply-chain-policy/critical.json"
supply_chain_workflow_change=".github/workflows/supply-chain-pr.yml"
supply_chain_doc_change="docs/supply-chain-architecture.md"
workflow_governance_change="scripts/validate-workflow-governance.rb"
makefile_change="Makefile"

assert_scope "unrelated documentation" kind false "$unrelated_docs"
assert_scope "unrelated documentation" gitops false "$unrelated_docs"
assert_scope "unrelated documentation" golden-path false "$unrelated_docs"
assert_scope "unrelated documentation" service-gitops false "$unrelated_docs"
assert_scope "unrelated documentation" supply-chain-pr false "$unrelated_docs"

assert_scope "kind foundation" kind true "$kind_change"
assert_scope "kind foundation" gitops true "$kind_change"
assert_scope "kind foundation" golden-path true "$kind_change"
assert_scope "kind foundation" service-gitops true "$kind_change"

assert_scope "gitops dependency" kind false "$gitops_change"
assert_scope "gitops dependency" gitops true "$gitops_change"
assert_scope "gitops dependency" golden-path true "$gitops_change"
assert_scope "gitops dependency" service-gitops true "$gitops_change"

assert_scope "golden-path chart" kind false "$golden_path_change"
assert_scope "golden-path chart" gitops false "$golden_path_change"
assert_scope "golden-path chart" golden-path true "$golden_path_change"
assert_scope "golden-path chart" service-gitops true "$golden_path_change"

assert_scope "service gitops compiler" kind false "$service_gitops_change"
assert_scope "service gitops compiler" gitops false "$service_gitops_change"
assert_scope "service gitops compiler" golden-path false "$service_gitops_change"
assert_scope "service gitops compiler" service-gitops true "$service_gitops_change"

assert_scope "service contract" kind false "$service_contract_change"
assert_scope "service contract" gitops false "$service_contract_change"
assert_scope "service contract" golden-path false "$service_contract_change"
assert_scope "service contract" service-gitops true "$service_contract_change"

assert_scope "service gitops runtime script" kind false "$service_gitops_script_change"
assert_scope "service gitops runtime script" gitops false "$service_gitops_script_change"
assert_scope "service gitops runtime script" golden-path false "$service_gitops_script_change"
assert_scope "service gitops runtime script" service-gitops true "$service_gitops_script_change"

assert_scope "shared governance classifier" kind true "$scope_change"
assert_scope "shared governance classifier" gitops true "$scope_change"
assert_scope "shared governance classifier" golden-path true "$scope_change"
assert_scope "shared governance classifier" service-gitops true "$scope_change"

assert_scope "kind workflow" kind true "$kind_workflow_change"
assert_scope "kind workflow" gitops true "$kind_workflow_change"
assert_scope "kind workflow" golden-path true "$kind_workflow_change"
assert_scope "kind workflow" service-gitops true "$kind_workflow_change"

assert_scope "gitops workflow" kind false "$gitops_workflow_change"
assert_scope "gitops workflow" gitops true "$gitops_workflow_change"
assert_scope "gitops workflow" golden-path true "$gitops_workflow_change"
assert_scope "gitops workflow" service-gitops true "$gitops_workflow_change"

assert_scope "golden-path workflow" kind false "$golden_path_workflow_change"
assert_scope "golden-path workflow" gitops false "$golden_path_workflow_change"
assert_scope "golden-path workflow" golden-path true "$golden_path_workflow_change"
assert_scope "golden-path workflow" service-gitops true "$golden_path_workflow_change"

assert_scope "service gitops workflow" kind false "$service_gitops_workflow_change"
assert_scope "service gitops workflow" gitops false "$service_gitops_workflow_change"
assert_scope "service gitops workflow" golden-path false "$service_gitops_workflow_change"
assert_scope "service gitops workflow" service-gitops true "$service_gitops_workflow_change"

assert_scope "supply-chain fixture source" supply-chain-pr true "$supply_chain_fixture_source_change"
assert_scope "supply-chain fixture Dockerfile" supply-chain-pr true "$supply_chain_fixture_dockerfile_change"
assert_scope "supply-chain script" supply-chain-pr true "$supply_chain_script_change"
assert_scope "supply-chain policy fixture" supply-chain-pr true "$supply_chain_policy_fixture_change"
assert_scope "supply-chain workflow" supply-chain-pr true "$supply_chain_workflow_change"
assert_scope "shared Makefile" supply-chain-pr true "$makefile_change"
assert_scope "shared scope classifier" supply-chain-pr true "$scope_change"
assert_scope "workflow governance validator" supply-chain-pr true "$workflow_governance_change"
assert_scope "supply-chain documentation" supply-chain-pr true "$supply_chain_doc_change"

printf '[ok] workflow scope classifier tests passed\n'
