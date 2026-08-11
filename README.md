# Kubernetes Internal Developer Platform

This repository is being rebuilt into a local-first Kubernetes Internal Developer Platform (IDP) portfolio project. The goal is to demonstrate practical platform engineering through reproducible Kubernetes environments, GitOps delivery, a reusable Helm golden path, developer self-service, policy enforcement, observability, CI/CD, and operational documentation.

## Current Status

The project is in Stage 4: production-quality golden-path Helm chart. Stage 1 established the recovery and engineering baseline, Stage 2 added a real Kind-based local cluster foundation, Stage 3 added Argo CD bootstrap and reconciliation proof, and Stage 4 adds a reusable Helm workload contract with GitOps runtime validation.

The local Kubernetes foundation is implemented with Kind. Argo CD is installed from a pinned and checksum-verified upstream manifest, then used to reconcile minimal platform bootstrap state and the golden-path demo workload. Kyverno policies, observability, service generation, environment promotion, and application delivery workflows remain target capabilities for later stages.

## Target Capabilities

- Reproducible local Kubernetes platform using Kind
- GitOps reconciliation with Argo CD
- Production-quality reusable application packaging with Helm
- Developer self-service service generation
- GitHub Actions validation and later CI/supply-chain workflows
- Kubernetes-native policy enforcement with Kyverno
- Metrics, logs, tracing, alerts, and SRE operating guidance
- Clear architecture, ADRs, recovery records, and roadmap documentation

## Architecture Summary

The intended platform separates infrastructure bootstrap, platform capabilities, reference workloads, developer tooling, and documentation. The local demonstration path will be runnable without mandatory cloud spend, while the architecture leaves room for a future optional cloud reference deployment.

See [docs/architecture/platform-overview.md](docs/architecture/platform-overview.md) for the target architecture and current repository state.

## Repository Structure

- `infra/` - cluster bootstrap, Argo CD control-plane bootstrap configuration, future environment infrastructure, and platform policy bootstrap.
- `platform/` - GitOps-managed platform bootstrap state, reusable Helm golden-path chart, and future platform add-ons and shared contracts.
- `services/` - future reference workloads and generated golden-path demonstration services.
- `tools/` - future developer-facing tooling, service generation, and repository support tooling.
- `docs/` - architecture, ADRs, recovery decisions, roadmap, and later developer/operator documentation.
- `.github/` - repository validation and local platform proof workflows.
- `scripts/` - repository validation, local Kubernetes, GitOps, Helm chart, and golden-path lifecycle scripts.

The detailed directory contract is documented in [docs/repository/structure-contract.md](docs/repository/structure-contract.md).

## Roadmap

The implementation roadmap is dependency-ordered. Stage 1 establishes repository truth, decisions, validation, and contribution expectations before runtime platform work begins.

See [docs/roadmap/implementation-roadmap.md](docs/roadmap/implementation-roadmap.md).

## Validation

The repository includes a small static validation baseline:

```bash
make help
make verify-tools
make validate
```

The validation checks repository structure, Markdown hygiene and internal links, YAML syntax for files that exist, shell syntax, and GitHub Actions workflow YAML. It does not create a Kubernetes cluster, install Argo CD, deploy workloads, publish artifacts, or require cloud credentials.

## Local Kubernetes

Stage 2 provides a reproducible local Kubernetes foundation using a named Kind cluster:

```bash
make verify-cluster-tools
make cluster-create
make cluster-status
make cluster-validate
make cluster-delete
```

The local platform uses cluster name `idp-local` and kubeconfig context `kind-idp-local`. See [docs/local-kubernetes.md](docs/local-kubernetes.md) for supported versions, lifecycle behavior, validation, and troubleshooting.

## GitOps Control Plane

Stage 3 provides a reproducible local Argo CD control plane and a minimal Git-managed bootstrap resource:

```bash
make gitops-install
make gitops-bootstrap
make gitops-status
make gitops-validate
make gitops-test-reconciliation
make gitops-delete
```

The GitOps bootstrap uses the `argocd` namespace, reconciles the `platform-bootstrap` Application from `main` by default, and proves drift correction plus managed-resource recreation. See [docs/gitops.md](docs/gitops.md).

## Golden-Path Helm Chart

Stage 4 provides a reusable Helm chart for ordinary HTTP services:

```bash
make verify-helm-tools
make helm-validate
make golden-path-bootstrap
make golden-path-status
make golden-path-validate
make golden-path-delete
```

The chart deploys through Argo CD, uses a dedicated `golden-path` AppProject and `golden-path-demo` Application, and validates secure defaults including digest-pinned images, probes, resources, security contexts, Service routing, ConfigMap data, and disruption handling. See [docs/golden-path.md](docs/golden-path.md).

## Contributing

Contributions use short-lived branches and pull requests into `main`. Historical branches remain preserved for attribution and recovery evidence; they should not be used directly as the base for new implementation work.

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Historical Recovery

The forensic audit concluded that historical branches contain useful design concepts but should not be merged wholesale. Future work will deliberately recover or reimplement approved concepts while preserving contributor attribution.

See [docs/recovery/historical-recovery.md](docs/recovery/historical-recovery.md).
