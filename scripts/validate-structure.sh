#!/usr/bin/env bash
set -euo pipefail

required_paths=(
  README.md
  CONTRIBUTING.md
  CODE_OF_CONDUCT.md
  Makefile
  docs/architecture/platform-overview.md
  docs/adr/0001-use-kind-for-local-kubernetes.md
  docs/adr/0002-use-argo-cd-for-gitops.md
  docs/adr/0003-use-helm-for-application-packaging.md
  docs/adr/0004-use-kyverno-for-policy-as-code.md
  docs/adr/0005-repository-and-branch-strategy.md
  docs/adr/0006-historical-branch-recovery-strategy.md
  docs/recovery/historical-recovery.md
  docs/roadmap/implementation-roadmap.md
  docs/repository/structure-contract.md
  .github/workflows/validate.yml
  scripts/verify-tools.sh
  scripts/validate.sh
  scripts/validate-structure.sh
  scripts/validate-markdown.rb
  scripts/validate-yaml.rb
  scripts/validate-shell.sh
)

missing=0

for path in "${required_paths[@]}"; do
  if [ ! -f "$path" ]; then
    printf '[error] required repository path missing: %s\n' "$path" >&2
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  exit 1
fi

printf '[ok] repository structure contract files are present\n'
