# Kubernetes Internal Developer Platform

This repository is being rebuilt into a local-first Kubernetes Internal Developer Platform (IDP) portfolio project. The goal is to demonstrate practical platform engineering through reproducible Kubernetes environments, GitOps delivery, a reusable Helm golden path, developer self-service, policy enforcement, observability, CI/CD, and operational documentation.

## Current Status

The project is in Stage 1: recovery and engineering baseline. The repository has been audited after recovery from historical branches, and implementation is being rebuilt from a clean, reviewable foundation.

Runtime platform components are not implemented yet. Kind, Argo CD, Helm golden-path charts, Kyverno policies, observability, service generation, and deployment workflows are target capabilities for later stages.

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

- `infra/` - future cluster bootstrap, GitOps root configuration, environment infrastructure, and platform policy bootstrap.
- `platform/` - future reusable platform capabilities, Helm golden path, add-ons, and shared contracts.
- `services/` - future reference workloads and generated golden-path demonstration services.
- `tools/` - future developer-facing tooling, service generation, and repository support tooling.
- `docs/` - architecture, ADRs, recovery decisions, roadmap, and later developer/operator documentation.
- `.github/` - repository validation workflow and future repository automation.
- `scripts/` - Stage 1 repository validation scripts.

The detailed directory contract is documented in [docs/repository/structure-contract.md](docs/repository/structure-contract.md).

## Roadmap

The implementation roadmap is dependency-ordered. Stage 1 establishes repository truth, decisions, validation, and contribution expectations before runtime platform work begins.

See [docs/roadmap/implementation-roadmap.md](docs/roadmap/implementation-roadmap.md).

## Validation

Stage 1 introduces a small validation baseline:

```bash
make help
make verify-tools
make validate
```

The validation currently checks repository structure, Markdown hygiene and internal links, YAML syntax for files that exist, shell syntax, and GitHub Actions workflow YAML. It does not create a Kubernetes cluster, deploy workloads, publish artifacts, or require cloud credentials.

## Contributing

Contributions use short-lived branches and pull requests into `main`. Historical branches remain preserved for attribution and recovery evidence; they should not be used directly as the base for new implementation work.

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Historical Recovery

The forensic audit concluded that historical branches contain useful design concepts but should not be merged wholesale. Future work will deliberately recover or reimplement approved concepts while preserving contributor attribution.

See [docs/recovery/historical-recovery.md](docs/recovery/historical-recovery.md).
