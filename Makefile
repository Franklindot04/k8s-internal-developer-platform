PYTHON ?= python3

.PHONY: help verify-tools verify-cluster-tools verify-helm-tools validate service-contract-test service-values-test service-gitops-test service-generation-test service-values-helm-validate service-gitops-runtime-validate supply-chain-fixture-test supply-chain-fixture-image-build supply-chain-fixture-smoke-test supply-chain-fixture-validate supply-chain-evidence-tools supply-chain-evidence-build supply-chain-evidence-verify supply-chain-evidence supply-chain-publication-test supply-chain-publication-validate trusted-publication-test trusted-publication-validate cluster-create cluster-status cluster-validate cluster-delete gitops-install gitops-bootstrap gitops-status gitops-validate gitops-test-reconciliation gitops-delete helm-lint helm-render helm-validate helm-server-dry-run golden-path-bootstrap golden-path-status golden-path-validate golden-path-delete

help:
	@printf '%s\n' 'Available targets:'
	@printf '%s\n' '  make verify-tools          Check repository validation tools'
	@printf '%s\n' '  make verify-cluster-tools  Check local Kubernetes lifecycle tools'
	@printf '%s\n' '  make verify-helm-tools     Check pinned Helm chart validation tools'
	@printf '%s\n' '  make validate              Run repository validation'
	@printf '%s\n' '  make service-contract-test Run PlatformService contract tests with installed Python dependencies'
	@printf '%s\n' '  make service-values-test   Run deterministic PlatformService values-generation tests'
	@printf '%s\n' '  make service-gitops-test   Run deterministic PlatformService GitOps-generation tests'
	@printf '%s\n' '  make service-generation-test  Run safe service artifact generation tests'
	@printf '%s\n' '  make service-values-helm-validate  Validate generated values against the golden-path chart'
	@printf '%s\n' '  make service-gitops-runtime-validate  Validate self-service GitOps runtime reconciliation'
	@printf '%s\n' '  make supply-chain-fixture-test  Run fixture source tests in the pinned Docker builder'
	@printf '%s\n' '  make supply-chain-fixture-image-build  Build the local fixture image'
	@printf '%s\n' '  make supply-chain-fixture-smoke-test  Smoke-test the local fixture image'
	@printf '%s\n' '  make supply-chain-fixture-validate  Run fixture source test, build, and smoke proof'
	@printf '%s\n' '  make supply-chain-evidence-tools  Install pinned local evidence tools'
	@printf '%s\n' '  make supply-chain-evidence-build  Build the exact local evidence image archive'
	@printf '%s\n' '  make supply-chain-evidence-verify  Validate generated evidence metadata'
	@printf '%s\n' '  make supply-chain-evidence  Run the complete local supply-chain evidence proof'
	@printf '%s\n' '  make supply-chain-publication-test  Run trusted publication contract tests'
	@printf '%s\n' '  make supply-chain-publication-validate  Validate trusted publication static contracts'
	@printf '%s\n' '  make trusted-publication-test  Run trusted publication workflow/runtime static tests'
	@printf '%s\n' '  make trusted-publication-validate  Validate trusted publication workflow/runtime static contracts'
	@printf '%s\n' '  make cluster-create        Create the idp-local Kind cluster'
	@printf '%s\n' '  make cluster-status        Show idp-local cluster status'
	@printf '%s\n' '  make cluster-validate      Validate idp-local cluster readiness'
	@printf '%s\n' '  make cluster-delete        Delete only the idp-local Kind cluster'
	@printf '%s\n' '  make gitops-install        Install the Argo CD GitOps control plane'
	@printf '%s\n' '  make gitops-bootstrap      Bootstrap the platform GitOps Application'
	@printf '%s\n' '  make gitops-status         Show GitOps control-plane and Application status'
	@printf '%s\n' '  make gitops-validate       Validate Argo CD and bootstrap reconciliation'
	@printf '%s\n' '  make gitops-test-reconciliation  Prove drift correction and self-healing'
	@printf '%s\n' '  make gitops-delete         Delete only Stage 3 GitOps state'
	@printf '%s\n' '  make helm-lint             Run strict golden-path chart linting'
	@printf '%s\n' '  make helm-render           Render golden-path chart test profiles'
	@printf '%s\n' '  make helm-validate         Run static golden-path chart validation'
	@printf '%s\n' '  make helm-server-dry-run   Server-side dry-run the runtime chart render'
	@printf '%s\n' '  make golden-path-bootstrap Bootstrap the golden-path app through Argo CD'
	@printf '%s\n' '  make golden-path-status    Show golden-path runtime status'
	@printf '%s\n' '  make golden-path-validate  Validate golden-path runtime reconciliation'
	@printf '%s\n' '  make golden-path-delete    Delete only Stage 4 golden-path runtime state'

verify-tools:
	@bash scripts/verify-tools.sh

verify-cluster-tools:
	@bash scripts/kubernetes/cluster.sh verify-tools

verify-helm-tools:
	@bash scripts/helm/validate-golden-path.sh verify-tools

validate:
	@bash scripts/validate.sh

service-contract-test:
	@PYTHONPATH=tools/platformctl/src $(PYTHON) -m unittest discover -s tools/platformctl/tests

service-values-test:
	@PYTHONPATH=tools/platformctl/src $(PYTHON) -m unittest discover -s tools/platformctl/tests -p 'test_service_values.py'

service-gitops-test:
	@PYTHONPATH=tools/platformctl/src $(PYTHON) -m unittest discover -s tools/platformctl/tests -p 'test_service_gitops.py'

service-generation-test:
	@PYTHONPATH=tools/platformctl/src $(PYTHON) -m unittest discover -s tools/platformctl/tests -p 'test_service_generation.py'

service-values-helm-validate:
	@bash scripts/helm/validate-service-values.sh validate

service-gitops-runtime-validate:
	@bash scripts/service-gitops/runtime.sh validate

supply-chain-fixture-test:
	@bash scripts/supply-chain/fixture.sh test

supply-chain-fixture-image-build:
	@bash scripts/supply-chain/fixture.sh build

supply-chain-fixture-smoke-test:
	@bash scripts/supply-chain/fixture.sh smoke

supply-chain-fixture-validate:
	@bash scripts/supply-chain/fixture.sh validate

supply-chain-evidence-tools:
	@bash scripts/supply-chain/evidence.sh install-tools

supply-chain-evidence-build:
	@bash scripts/supply-chain/evidence.sh build

supply-chain-evidence-verify:
	@bash scripts/supply-chain/evidence.sh verify

supply-chain-evidence:
	@bash scripts/supply-chain/evidence.sh all

supply-chain-publication-test:
	@ruby scripts/supply-chain/test-publication.rb

supply-chain-publication-validate:
	@ruby scripts/supply-chain/validate-evidence-tooling.rb

trusted-publication-test:
	@ruby scripts/supply-chain/test-trusted-publication-workflow.rb

trusted-publication-validate:
	@ruby scripts/supply-chain/test-trusted-publication-workflow.rb

cluster-create:
	@bash scripts/kubernetes/cluster.sh create

cluster-status:
	@bash scripts/kubernetes/cluster.sh status

cluster-validate:
	@bash scripts/kubernetes/cluster.sh validate

cluster-delete:
	@bash scripts/kubernetes/cluster.sh delete

gitops-install:
	@bash scripts/gitops/argocd.sh install

gitops-bootstrap:
	@bash scripts/gitops/argocd.sh bootstrap

gitops-status:
	@bash scripts/gitops/argocd.sh status

gitops-validate:
	@bash scripts/gitops/argocd.sh validate

gitops-test-reconciliation:
	@bash scripts/gitops/argocd.sh test-reconciliation

gitops-delete:
	@bash scripts/gitops/argocd.sh delete

helm-lint:
	@bash scripts/helm/validate-golden-path.sh lint

helm-render:
	@bash scripts/helm/validate-golden-path.sh render

helm-validate:
	@bash scripts/helm/validate-golden-path.sh validate

helm-server-dry-run:
	@bash scripts/helm/validate-golden-path.sh server-dry-run

golden-path-bootstrap:
	@bash scripts/golden-path/lifecycle.sh bootstrap

golden-path-status:
	@bash scripts/golden-path/lifecycle.sh status

golden-path-validate:
	@bash scripts/golden-path/lifecycle.sh validate

golden-path-delete:
	@bash scripts/golden-path/lifecycle.sh delete
