#!/usr/bin/env bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"

run() {
  printf '\n==> %s\n' "$1"
  shift
  "$@"
}

run "Verify required tools" bash scripts/verify-tools.sh
run "Validate repository structure" bash scripts/validate-structure.sh
run "Validate Markdown" ruby scripts/validate-markdown.rb
run "Validate YAML" ruby scripts/validate-yaml.rb
run "Validate shell syntax" bash scripts/validate-shell.sh
run "Test workflow scope classifier" bash scripts/ci/test-workflow-scope.sh
run "Validate workflow governance" ruby scripts/validate-workflow-governance.rb
run "Validate supply-chain evidence tooling" ruby scripts/supply-chain/validate-evidence-tooling.rb
run "Test supply-chain vulnerability policy" ruby scripts/supply-chain/evaluate-vulnerabilities.rb --self-test tests/fixtures/supply-chain-policy
run "Test supply-chain policy-failure evidence retention" bash scripts/supply-chain/test-evidence-policy-retention.sh

if command -v shellcheck >/dev/null 2>&1; then
  run "Run ShellCheck" shellcheck scripts/*.sh scripts/kubernetes/*.sh scripts/ci/*.sh scripts/gitops/*.sh scripts/helm/*.sh scripts/golden-path/*.sh
else
  printf '\n==> ShellCheck not installed; optional local check not executed\n'
fi

if command -v actionlint >/dev/null 2>&1; then
  run "Run actionlint" actionlint
else
  printf '\n==> actionlint not installed; optional local check not executed\n'
fi

printf '\nAll required repository validation checks passed.\n'
