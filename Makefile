.PHONY: help verify-tools verify-cluster-tools validate cluster-create cluster-status cluster-validate cluster-delete

help:
	@printf '%s\n' 'Available targets:'
	@printf '%s\n' '  make verify-tools          Check repository validation tools'
	@printf '%s\n' '  make verify-cluster-tools  Check local Kubernetes lifecycle tools'
	@printf '%s\n' '  make validate              Run repository validation'
	@printf '%s\n' '  make cluster-create        Create the idp-local Kind cluster'
	@printf '%s\n' '  make cluster-status        Show idp-local cluster status'
	@printf '%s\n' '  make cluster-validate      Validate idp-local cluster readiness'
	@printf '%s\n' '  make cluster-delete        Delete only the idp-local Kind cluster'

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
