# Platform Walkthrough

This walkthrough gives a platform engineer, technical reviewer, or maintainer a compact path through the implemented local-first reference-platform core. It uses existing repository commands only and does not require triggering trusted publication, changing registry state, or approving an Environment.

## Prerequisites

Baseline repository validation requires Git, Bash, Ruby, and Make.

The local Kubernetes and GitOps demo path additionally requires Docker with a reachable daemon, Kind `v0.32.0`, and a compatible kubectl client for Kubernetes `v1.35.5`. Helm validation requires Helm `v3.21.0` and kubeconform `v0.7.0`. The self-service CLI tests use Python `3.12` and the locked dependencies in `tools/platformctl/requirements.lock`.

GitHub CLI is useful only for inspecting hosted workflow runs and pull-request checks. It is not required for local validation.

## 1. Understand The Architecture

Start with the short architecture map and the current completion boundary:

- [Platform architecture overview](../architecture/platform-overview.md)
- [Implementation roadmap](../roadmap/implementation-roadmap.md)
- [Repository structure contract](../repository/structure-contract.md)
- [Software supply-chain architecture](../supply-chain-architecture.md)

The completed core covers local Kubernetes, Argo CD GitOps, Helm workload packaging, self-service artifact generation, repository and CI governance, and trusted publication. Policy engines, observability stacks, environment promotion, portal integration, signing, and cryptographic provenance remain optional future expansion.

## 2. Validate The Repository Baseline

Run the repository-native baseline first:

```bash
make verify-tools
make validate
```

This proves repository structure, Markdown links, YAML syntax, shell syntax, workflow governance, supply-chain evidence contracts, vulnerability policy behavior, and trusted-publication static/runtime contracts. It does not create a cluster, install Argo CD, deploy workloads, publish images, or require cloud credentials.

Validation may leave ignored local cache or evidence output. Those artifacts are ignored and are not repository state.

## 3. Exercise The Kind Lifecycle

Verify local Kubernetes prerequisites and exercise the project cluster:

```bash
make verify-cluster-tools
make cluster-create
make cluster-status
make cluster-validate
```

The project cluster is `idp-local` with context `kind-idp-local`. When finished with local cluster work:

```bash
make cluster-delete
```

Deletion targets only the project Kind cluster.

## 4. Inspect Helm And GitOps Packaging

Validate the golden-path chart without deploying it:

```bash
make verify-helm-tools
make helm-validate
```

Relevant paths:

- `platform/helm-charts/golden-path/`
- `platform/helm-charts/golden-path/values.schema.json`
- `platform/helm-charts/golden-path/tests/values/`
- `infra/gitops/golden-path/`

To exercise the GitOps runtime path locally, create the Kind cluster first, then install and bootstrap Argo CD:

```bash
make cluster-create
make gitops-install
make gitops-bootstrap
make gitops-validate
make golden-path-bootstrap
make golden-path-status
make golden-path-validate
```

Clean up the runtime state in reverse scope:

```bash
make golden-path-delete
make gitops-delete
make cluster-delete
```

## 5. Review The Self-Service Flow

The developer intent contract is `PlatformService`:

- schema: `platform/self-service/service.schema.json`
- profile policy: `platform/self-service/profile-policy.yaml`
- GitOps policy: `platform/self-service/gitops-policy.yaml`
- CLI implementation: `tools/platformctl/`
- contract documentation: [Developer self-service contract](../self-service-contract.md)

Run the self-service validation suite:

```bash
make service-contract-test
make service-values-test
make service-gitops-test
make service-generation-test
make service-values-helm-validate
```

Preview generated Helm values and Argo CD Application output from an existing fixture without writing repository files:

```bash
PYTHONPATH=tools/platformctl/src python3 -m platformctl service plan tools/platformctl/tests/fixtures/values/minimal-single/services/minimal-api/service.yaml
```

The production write path is:

```bash
PYTHONPATH=tools/platformctl/src python3 -m platformctl service generate services/<service>/service.yaml
PYTHONPATH=tools/platformctl/src python3 -m platformctl service verify services/<service>/service.yaml
```

Generation writes only:

```text
services/<service>/generated/values.yaml
services/<service>/generated/application.yaml
```

It does not commit, push, open a pull request, register Argo CD Applications, or deploy workloads automatically.

## 6. Review CI And Governance

The protected `main` checks are:

- `Validate repository baseline`
- `Kind lifecycle validation`
- `Argo CD reconciliation validation`
- `Helm chart and GitOps validation`
- `Supply-chain PR validation`

`Service contract validation` and `Service GitOps validation` are implemented workflows but are not required `main` checks. The required runtime workflows use scope classifiers and stable final gates so irrelevant pull requests still report explicit pass/fail status.

Relevant documentation:

- [Required CI checks](../ci-required-checks.md)
- [Contributing](../../CONTRIBUTING.md)

## 7. Review Trusted Publication

Do not trigger a new trusted publication for review. Use the documented live proof:

- [Trusted publication runbook](trusted-publication.md)
- [Software supply-chain architecture](../supply-chain-architecture.md)

The proven model is:

```text
protected main
-> one local application build
-> local runtime/SBOM/vulnerability policy
-> public non-authoritative candidate
-> post-push candidate verification
-> protected Environment approval
-> authenticated authoritative recheck
-> digest-preserving no-rebuild promotion
-> anonymous authoritative verification
-> authoritative evidence
-> Stage 5 authoritative digest handoff
```

Candidate images are public verified staging and non-authoritative. Stage 5 consumes only the authoritative repository by immutable digest.

## 8. Review Optional Future Work

Optional future milestones are useful only if the project intentionally expands beyond the completed core. They include policy enforcement, observability, environment promotion, broader SRE depth, signing, cryptographic provenance, registry-attached attestations, portal integration, and additional infrastructure depth.

Those areas are not required to validate or review the current reference-platform core.
