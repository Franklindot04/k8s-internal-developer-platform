.PHONY: help verify-tools verify-cluster-tools validate cluster-create cluster-status cluster-validate cluster-delete gitops-install gitops-bootstrap gitops-status gitops-validate gitops-test-reconciliation gitops-delete

help:
	@printf '%s\n' 'Available targets:'
	@printf '%s\n' '  make verify-tools          Check repository validation tools'
	@printf '%s\n' '  make verify-cluster-tools  Check local Kubernetes lifecycle tools'
	@printf '%s\n' '  make validate              Run repository validation'
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

verify-tools:
	@bash scripts/verify-tools.sh

verify-cluster-tools:
	@bash scripts/kubernetes/cluster.sh verify-tools

validate:
	@bash scripts/validate.sh

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
