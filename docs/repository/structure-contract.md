# Repository Structure Contract

This contract defines the intended purpose of top-level directories. It does not mean all future capabilities are implemented today.

## `infra/`

Owns infrastructure bootstrap concerns. Future contents may include Kind cluster configuration, GitOps bootstrap resources, environment infrastructure, namespace boundaries, and platform policy bootstrap when those resources are tied to cluster setup.

Stage 2 state: contains the Kind local cluster configuration and version contract.

## `platform/`

Owns reusable platform capabilities and shared contracts. Future contents may include the golden-path Helm chart, platform add-ons, shared values contracts, policy bundles, and observability integration.

Stage 2 state: directory exists as recovered structure only.

## `services/`

Owns reference workloads and generated demonstration workloads. Services in this directory should be deployable through the platform contract once the chart and generator exist.

Stage 2 state: recovered service directories contain no working services.

## `tools/`

Owns developer-facing and repository-support tooling. Future contents may include the service generator, template pack tests, and support utilities.

Stage 2 state: repository and local Kubernetes lifecycle scripts live in `scripts/`. Future developer tooling may be added under `tools/` when it is implemented.

## `docs/`

Owns durable project knowledge: architecture, ADRs, recovery records, roadmap, developer documentation, operator documentation, runbooks, threat model, and limitations.

Stage 2 state: architecture, ADR, recovery, roadmap, structure, and local Kubernetes documentation are established.

## `.github/`

Owns repository automation and contribution controls. Future contents may include workflows, pull request templates, issue templates, and repository automation.

Stage 2 state: baseline repository validation and local Kubernetes lifecycle workflows are established.

## `scripts/`

Owns small repository-maintenance scripts that are directly invoked by `make` or CI. Scripts must fail when checks fail and must not report success for work they did not perform.

Stage 2 state: tool verification, repository validation, and local Kubernetes lifecycle scripts are established.
