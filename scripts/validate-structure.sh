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
  docs/local-kubernetes.md
  docs/gitops.md
  docs/golden-path.md
  docs/adr/0007-bootstrap-gitops-control-plane.md
  docs/adr/0008-use-opinionated-helm-golden-path.md
  infra/kubernetes/kind/cluster.yaml
  infra/kubernetes/kind/versions.env
  infra/gitops/argocd/versions.env
  infra/gitops/argocd/appproject.yaml
  infra/gitops/argocd/application.yaml
  infra/gitops/golden-path/appproject.yaml
  infra/gitops/golden-path/application.yaml
  platform/gitops/bootstrap/namespace.yaml
  platform/gitops/bootstrap/configmap.yaml
  platform/helm-charts/versions.env
  platform/helm-charts/golden-path/Chart.yaml
  platform/helm-charts/golden-path/values.yaml
  platform/helm-charts/golden-path/values.schema.json
  platform/helm-charts/golden-path/tests/values/runtime-kind.yaml
  platform/helm-charts/golden-path/tests/values/feature-complete.yaml
  platform/helm-charts/golden-path/tests/values/invalid-image.yaml
  .github/workflows/validate.yml
  .github/workflows/local-kubernetes.yml
  .github/workflows/gitops-control-plane.yml
  .github/workflows/golden-path-helm.yml
  scripts/verify-tools.sh
  scripts/validate.sh
  scripts/validate-structure.sh
  scripts/validate-markdown.rb
  scripts/validate-yaml.rb
  scripts/validate-shell.sh
  scripts/kubernetes/cluster.sh
  scripts/gitops/argocd.sh
  scripts/helm/validate-golden-path.sh
  scripts/helm/assert-golden-path-render.rb
  scripts/golden-path/lifecycle.sh
  scripts/ci/install-local-kubernetes-tools.sh
  scripts/ci/install-helm-tools.sh
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
