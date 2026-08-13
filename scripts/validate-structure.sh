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
  docs/self-service-contract.md
  docs/ci-required-checks.md
  docs/adr/0007-bootstrap-gitops-control-plane.md
  docs/adr/0008-use-opinionated-helm-golden-path.md
  docs/adr/0009-use-always-reporting-required-check-gates.md
  docs/adr/0010-adopt-platformservice-contract.md
  docs/adr/0011-compile-platformservice-into-golden-path-values.md
  docs/adr/0012-generate-platformservice-gitops-applications.md
  docs/adr/0013-safely-generate-and-verify-platformservice-artifacts.md
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
  platform/self-service/service.schema.json
  tools/platformctl/pyproject.toml
  tools/platformctl/requirements.lock
  tools/platformctl/src/platformctl/__init__.py
  tools/platformctl/src/platformctl/__main__.py
  tools/platformctl/src/platformctl/cli.py
  tools/platformctl/src/platformctl/service_generation.py
  tools/platformctl/src/platformctl/validation.py
  tools/platformctl/tests/test_service_generation.py
  tools/platformctl/tests/test_validation.py
  .github/workflows/validate.yml
  .github/workflows/local-kubernetes.yml
  .github/workflows/gitops-control-plane.yml
  .github/workflows/golden-path-helm.yml
  scripts/verify-tools.sh
  scripts/validate.sh
  scripts/validate-generated-structure.sh
  scripts/validate-structure.sh
  scripts/validate-markdown.rb
  scripts/validate-yaml.rb
  scripts/validate-shell.sh
  scripts/kubernetes/cluster.sh
  scripts/gitops/argocd.sh
  scripts/ci/workflow-scope.sh
  scripts/ci/test-workflow-scope.sh
  scripts/ci/test-generated-structure.sh
  scripts/validate-workflow-governance.rb
  scripts/helm/validate-golden-path.sh
  scripts/helm/assert-golden-path-render.rb
  scripts/golden-path/lifecycle.sh
  scripts/supply-chain/fixture.sh
  tests/fixtures/supply-chain-fixture/README.md
  tests/fixtures/supply-chain-fixture/go.mod
  tests/fixtures/supply-chain-fixture/cmd/server/main.go
  tests/fixtures/supply-chain-fixture/internal/health/handler.go
  tests/fixtures/supply-chain-fixture/internal/health/handler_test.go
  tests/fixtures/supply-chain-fixture/Dockerfile
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

bash scripts/validate-generated-structure.sh

fixture_path="tests/fixtures/supply-chain-fixture"
dockerfile="$fixture_path/Dockerfile"

if [ -d "services/supply-chain-fixture" ]; then
  printf '[error] supply-chain fixture must not live under services/\n' >&2
  missing=1
fi

if ! grep -Eq '^ARG TARGETPLATFORM=linux/amd64$' "$dockerfile" || ! grep -Eq '^FROM golang:1\.26\.6-bookworm@sha256:[0-9a-f]{64} AS test$' "$dockerfile"; then
  printf '[error] supply-chain fixture builder image must be immutable-digest pinned\n' >&2
  missing=1
fi

if ! grep -Fqx "RUN test \"\$TARGETPLATFORM\" = \"linux/amd64\"" "$dockerfile"; then
  printf '[error] supply-chain fixture must assert linux/amd64 as the canonical target platform\n' >&2
  missing=1
fi

if grep -Eq '(^|[^[:alnum:]_])latest([^[:alnum:]_]|$)' "$dockerfile"; then
  printf '[error] supply-chain fixture Dockerfile must not use latest\n' >&2
  missing=1
fi

if ! grep -Eq '^FROM scratch AS runtime$' "$dockerfile"; then
  printf '[error] supply-chain fixture runtime image must be scratch\n' >&2
  missing=1
fi

if ! grep -Eq '^USER 65532:65532$' "$dockerfile"; then
  printf '[error] supply-chain fixture runtime must use numeric non-root USER\n' >&2
  missing=1
fi

if ! grep -Eq '^EXPOSE 8080$' "$dockerfile"; then
  printf '[error] supply-chain fixture must expose port 8080\n' >&2
  missing=1
fi

if grep -Eiq 'apt-get|apk |yum |dnf |microdnf|brew |pip install|npm install|go get' "$dockerfile" "$fixture_path/go.mod" scripts/supply-chain/fixture.sh; then
  printf '[error] supply-chain fixture must not install packages during build or runtime\n' >&2
  missing=1
fi

if grep -Eiq 'docker (login|push)|packages:[[:space:]]*write|cosign|syft|grype|trivy|attestation|signing|admission|promotion|--provenance(=true|[[:space:]]+true)|--sbom(=true|[[:space:]]+true)' "$dockerfile" scripts/supply-chain/fixture.sh; then
  printf '[error] supply-chain fixture must not introduce Stage 6C+ tooling or registry mutation\n' >&2
  missing=1
fi

if [ "$missing" -ne 0 ]; then
  exit 1
fi

printf '[ok] repository structure contract files are present\n'
