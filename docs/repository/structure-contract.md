# Repository Structure Contract

This contract defines the intended purpose of top-level directories. It does not mean all future capabilities are implemented today.

## `infra/`

Owns infrastructure bootstrap concerns. Future contents may include Kind cluster configuration, GitOps bootstrap resources, environment infrastructure, namespace boundaries, and platform policy bootstrap when those resources are tied to cluster setup.

Current state: contains the Kind local cluster configuration and version contract plus Argo CD bootstrap manifests, golden-path Application registration, self-service AppProject boundary, and version/checksum contracts. Environment infrastructure and platform policy bootstrap remain optional future expansion.

## `platform/`

Owns reusable platform capabilities and shared contracts. Future contents may include the golden-path Helm chart, platform add-ons, shared values contracts, policy bundles, and observability integration.

Current state: contains minimal GitOps-managed platform bootstrap state, the golden-path Helm chart, versioned self-service contract schema, platform-owned profile and GitOps policies, and the self-service AppProject boundary. Add-ons, observability, and environment promotion remain optional future expansion. Supply-chain automation lives in `scripts/`, `.github/workflows/`, tests, and documentation because it is repository/CI behavior rather than Kubernetes runtime configuration.

## `services/`

Owns service intent sources and platform-managed generated service artifacts.

Stage 5 state: a service source of truth lives at `services/<service>/service.yaml`. Before generation, the source-only state is valid. After generation, `services/<service>/generated/` may contain exactly two platform-owned persistent artifacts:

- `values.yaml`
- `application.yaml`

Unexpected persistent files under `generated/` are invalid. Generated artifacts are derived from the `PlatformService` source and must not become competing sources of truth.

## `tools/`

Owns developer-facing and repository-support tooling. Future contents may include template pack tests, additional support utilities, and later interfaces over the self-service contract.

Current state: repository and local Kubernetes lifecycle scripts live in `scripts/`, while repository-local developer self-service tooling lives under `tools/platformctl/`. `platformctl` validates `PlatformService` files, previews deterministic Helm values and Argo CD Applications, safely generates the canonical `values.yaml` and `application.yaml` artifact pair, and verifies generated drift without writing. It does not register Applications automatically or create portal/API behavior.

## `docs/`

Owns durable project knowledge: architecture, ADRs, recovery records, roadmap, developer documentation, operator documentation, runbooks, threat model, and limitations.

Current state: architecture, ADR, recovery, roadmap, structure, local Kubernetes, GitOps control-plane, golden-path Helm chart, self-service, supply-chain architecture, trusted publication runbook, and platform walkthrough documentation are established.

## `.github/`

Owns repository automation and contribution controls. Future contents may include workflows, pull request templates, issue templates, and repository automation.

Current state: baseline repository validation, local Kubernetes lifecycle, GitOps reconciliation validation, golden-path Helm/GitOps validation, service contract, service GitOps, untrusted supply-chain PR verification, and protected-main trusted publication workflows are established. Signing, provenance, attestations, and registry-attached attestations are optional future expansion.

## `scripts/`

Owns small repository-maintenance scripts that are directly invoked by `make` or CI. Scripts must fail when checks fail and must not report success for work they did not perform.

Current state: tool verification, repository validation, local Kubernetes lifecycle, GitOps lifecycle, Helm chart validation, golden-path runtime lifecycle, self-service validation/generation support scripts, supply-chain evidence scripts, vulnerability policy scripts, and trusted publication scripts are established.

## `tests/`

Owns test fixtures and non-production proof assets.

Current state: contains one test-only `supply-chain-fixture` representative service plus supply-chain policy and publication fixtures. These prove source tests, local container buildability, local image identity reporting, non-root runtime, graceful shutdown behavior, vulnerability policy behavior, and trusted-publication contracts without becoming production services or changing the platform's language-neutral application contract.
