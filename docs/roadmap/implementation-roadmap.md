# Implementation Roadmap

The roadmap is dependency-ordered. Each stage should produce reviewable evidence before the next stage depends on it.

## Stage 1: Recovery and Engineering Baseline

Objective: Establish repository truth, documentation, decisions, validation, and contribution expectations.

Principal capabilities: architecture overview, ADRs, recovery controls, roadmap, README correction, structure contract, local validation, and baseline GitHub Actions validation.

Dependencies: approved forensic recovery audit.

Meaningful validation/evidence: clean branch from `main`, `make verify-tools`, `make validate`, `git diff --check`, reviewed documentation links, and CI workflow syntax parsing.

Definition of done: the repository accurately describes current state, has executable validation, and is ready for focused runtime implementation branches.

## Stage 2: Reproducible Local Kubernetes Platform

Objective: Provide a deterministic local Kubernetes environment.

Principal capabilities: Kind configuration, lifecycle commands, prerequisite documentation, bootstrap, teardown, and cluster validation.

Dependencies: Stage 1 validation and architecture decisions.

Meaningful validation/evidence: fresh Kind cluster creation, version confirmation, namespace readiness, teardown, and repeatable validation commands.

Definition of done: a maintainer can create, validate, and remove the local cluster from documented commands.

## Stage 3: GitOps Control Plane

Objective: Add GitOps reconciliation for platform and application configuration.

Principal capabilities: Argo CD installation, bootstrap application structure, repository layout, reconciliation validation, drift visibility, safe removal, and reinstall proof.

Dependencies: working local Kubernetes platform.

Meaningful validation/evidence: Argo CD is installed locally from a pinned and checksum-verified manifest, bootstrap state syncs successfully, drift is corrected, managed resources are recreated, removal is scoped, and reinstall/rebootstrap succeeds.

Definition of done: Git changes are the documented source of truth for Stage 3 platform bootstrap state.

## Stage 4: Production-Quality Golden-Path Helm Chart

Objective: Create the reusable application deployment contract.

Principal capabilities: chart metadata, values schema, Deployment, Service, ServiceAccount, probes, resources, HPA, PDB, NetworkPolicy, ingress or Gateway support, config, secrets integration, security contexts, scheduling controls, helpers, and tests.

Dependencies: Stage 1 recovery policy, Stage 2 validation environment, and Stage 3 GitOps control plane.

Meaningful validation/evidence: strict Helm linting, rendered manifests, invalid values rejection, kubeconform validation, selector checks, server-side dry-run, Argo CD deployment, ready pods, Service endpoints, HTTP health response, safe deletion, and redeploy proof.

Definition of done: the chart can deploy a reference service safely and predictably through the GitOps control plane.

## Stage 5: Functional Developer Self-Service Generator

Objective: Generate a usable service from schema-driven inputs.

Principal capabilities: template pack registry, validated inputs, deterministic rendering, service source, Helm values, CI files, docs, metadata, environment config, idempotent writes, and safe error handling.

Dependencies: golden-path chart contract and repository validation.

Meaningful validation/evidence: generator tests, golden-file comparisons, failure-path tests, generated service validation, and deployment through the local platform.

Definition of done: a generated service can be reviewed, tested, and deployed without manual repair.

## Stage 6: CI and Software Supply-Chain Controls

Objective: Produce trusted software artifacts and evidence before immutable image digests enter the Stage 5 deployment intent contract.

Principal capabilities: supply-chain architecture and trust contracts, a representative build fixture, reproducible container build, untrusted PR build/test/SBOM/vulnerability verification, trusted OCI publication, immutable image digest output, provenance or attestation bound to the digest, and documented manual handoff into `PlatformService`.

Dependencies: golden-path chart, completed Stage 5 `PlatformService` digest contract, and a representative build fixture introduced during Stage 6.

Meaningful validation/evidence: untrusted pull requests can prove build/test/evidence generation without publication credentials; trusted publication can publish an OCI image, resolve its immutable digest, generate required evidence, and hand repository plus digest to Stage 5.

Definition of done: a representative source has a repeatable build contract; tests pass; container build succeeds; untrusted PRs cannot publish; trusted publication exists; the published artifact has an immutable digest; Stage 5 can consume repository plus digest; SBOM, vulnerability evidence, and provenance or attestation exist; required-check behavior remains governable; no personal publication credentials are required where avoidable; documentation explains build, publication, evidence, and digest handoff; environment promotion and Kubernetes admission enforcement remain outside Stage 6.

Planned slices:

- Stage 6A - Supply-Chain Architecture & Trust Contracts: complete; defines trust, artifact, evidence, publication, and handoff contracts without software implementation.
- Stage 6B - Representative Build Fixture & Repeatable Build: complete; adds a test-only Go representative fixture while preserving the language-neutral platform contract, with standard-library source tests, a pinned official builder digest, linux/amd64 local build proof, scratch non-root runtime, local image identity reporting, health and graceful shutdown/process exit-code smoke proof, and no registry publication or Stage 6C+ evidence tooling.
- Stage 6C1 - Supply-Chain Evidence Tooling: complete; establishes repository-owned pinned Syft and Grype tooling, one-build Docker archive identity, local runtime correlation from that archive, one Syft cataloging operation that emits CycloneDX JSON for portable review and Syft JSON for rich scanner-native inventory evidence, direct Grype scanning of the exact Docker archive, fail-closed vulnerability policy evaluation, legitimate policy-failure evidence retention, and evidence manifest validation.
- Stage 6C2 - Untrusted PR Verification: complete; wires the Stage 6C1 evidence engine into pull-request CI with read-only permissions, no secrets, no publication credentials, merge-ref source identity, runner-portable archive generation, retained validated evidence, GitHub artifact digests, scope-classified conditional execution, and an always-reporting `Supply-chain PR validation` final gate. Relevant changes execute evidence and retain artifacts; irrelevant changes still start the workflow, skip expensive evidence, upload no supply-chain artifacts, and pass the final gate.
- Stage 6C - PR Build / Test / SBOM / Vulnerability Verification: complete; provides untrusted pull-request build/test/SBOM/vulnerability verification as merge-safety evidence, not trusted publication authority.
- Stage 6D1 - Trusted Image Publication Engine & Contracts: complete / merged; establishes local trusted-publication naming, candidate and authoritative reference construction, digest continuity validation, same-source rerun protection, publication evidence validation, and a Stage 5-compatible `image-reference.json` handoff without registry mutation. Boundary hardening for private candidate quarantine and attempt-aware candidate identity is implemented for review.
- Stage 6D2 - Trusted GHCR Workflow & First Live Publication: not started; will add the trusted protected-main workflow and first controlled GHCR publication using the Stage 6D1 engine.
- Stage 6D - Trusted OCI Publication & Immutable Digest: in progress; the local engine/contracts slice is complete, boundary hardening is implemented for review, and live GHCR publication is not implemented yet.
- Stage 6E - Provenance / Attestation: not started; binds trusted build provenance to the published digest and evaluates keyless signing.

## Stage 7: Kubernetes Security and Policy Enforcement

Objective: Enforce baseline Kubernetes security and reliability standards.

Principal capabilities: Kyverno installation, Pod Security Standards, resource quotas, LimitRanges, namespace isolation, NetworkPolicy defaults, admission policies, and policy tests.

Dependencies: local cluster, GitOps, and workload chart.

Meaningful validation/evidence: known-good workloads pass, known-bad workloads fail, and policy decisions are documented.

Definition of done: platform standards are executable controls, not only documentation.

## Stage 8: Observability Platform

Objective: Make platform and application behavior visible.

Principal capabilities: metrics, dashboards, centralized logs, traces, OpenTelemetry integration, alerts, application telemetry, platform telemetry, SLIs, and SLO inputs.

Dependencies: deployed workloads and stable environment model.

Meaningful validation/evidence: a reference service exposes metrics/logs/traces and alerts can be exercised in controlled scenarios.

Definition of done: service health and platform health can be inspected from documented commands and dashboards.

## Stage 9: Environment and Promotion Model

Objective: Demonstrate controlled change movement across environment boundaries.

Principal capabilities: dev/staging/prod-style configuration, GitOps promotion, rollback patterns, immutable image references, and separation of platform and application config.

Dependencies: GitOps, chart, generator, and CI controls.

Meaningful validation/evidence: a reference change is promoted through environments by Git changes with validation gates.

Definition of done: promotion is reviewable, repeatable, and reversible.

## Stage 10: End-to-End Developer Golden Path

Objective: Connect service creation, validation, deployment, and observability into one coherent workflow.

Principal capabilities: generate service, run local tests, validate manifests, register with GitOps, deploy, inspect health, and review telemetry.

Dependencies: generator, chart, GitOps, CI, policy, and observability.

Meaningful validation/evidence: a maintainer can complete the workflow from a clean checkout using documented commands.

Definition of done: the platform demonstrates a realistic developer onboarding and service delivery path.

## Stage 11: SRE and Operational Maturity

Objective: Add operational practices that make the platform maintainable.

Principal capabilities: SLOs, alerts, runbooks, troubleshooting, failure scenarios, resource and capacity guidance, upgrade strategy, recovery practices, backup considerations, and incident response notes.

Dependencies: working platform and observability.

Meaningful validation/evidence: runbooks are tied to observable signals and failure drills produce useful operator actions.

Definition of done: the platform can be operated and explained under failure, not only installed.

## Stage 12: Documentation, Architecture, Testing, and Release Hardening

Objective: Prepare the project for portfolio review and future collaboration.

Principal capabilities: final architecture docs, diagrams, ADR index, threat model, developer guide, operator guide, limitation notes, validation matrix, release notes, and demo script.

Dependencies: completed platform capabilities.

Meaningful validation/evidence: fresh-clone walkthrough, complete validation run, verified links, and documented trade-offs.

Definition of done: the repository tells the truth, works from documented commands, and demonstrates mature platform engineering.
