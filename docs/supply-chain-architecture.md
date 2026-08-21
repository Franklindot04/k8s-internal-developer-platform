# Software Supply-Chain Architecture

Stage 6 defines the software supply-chain boundary for this platform. It begins upstream of the Stage 5 image input and ends when a trusted publication path produces an immutable OCI image identity that Stage 5 can consume.

The Stage 6 responsibility is:

```text
application source
-> verification
-> reproducible container build
-> immutable OCI artifact
-> supply-chain evidence
-> trusted publication
-> image digest
```

Stage 5 then consumes:

```text
image.repository
+ image.digest
```

Stage 6 produces trusted artifacts. Stage 5 describes deployment intent. Stage 7 may enforce workload and admission security. Stage 9 owns environment promotion.

## Current Boundary

Stage 5 requires `spec.image.repository` and a mandatory lowercase `sha256:<digest>` in each `PlatformService`. Tags are not accepted in the developer-facing contract. The values compiler maps that intent into the Stage 4 golden-path chart with an empty tag and a digest, so deployment identity remains immutable.

Today, that digest can come from the trusted publication path documented in this stage. The repository contains pull-request build, SBOM, vulnerability, and policy verification for merge safety, plus a protected-main trusted publication workflow that produces an authoritative registry digest and Stage 5 handoff. Provenance, attestations, registry-attached attestations, signing, broader deployment orchestration, and portal integration remain future milestones.

## Repository Boundary

This repository is primarily a platform implementation, configuration, documentation, and test/integration fixture repository. Stage 6 does not convert it into a production application monorepo.

Stage 6B adds one test-only representative build fixture solely to prove the supply-chain contract. That fixture must not become the required application language, the developer golden-path language, a production service, or a second product maintained inside the platform repository.

## Language Neutrality

Stage 6 is language-neutral. `PlatformService` consumes deployable OCI identity, not source-language details. The representative fixture uses Go to make the build/test proof executable, but that choice does not appear in the platform API contract.

## Image Identity

The authoritative deployable identity is the OCI image digest. Human-friendly tags may exist for discovery, commit association, or release association, but deployment must remain digest-based.

The conceptual future flow is:

```text
source revision
-> image build
-> optional tag
-> registry digest
-> supply-chain evidence bound to digest
-> PlatformService digest
```

A mutable tag alone must never become the Stage 5 deployment identity.

## PR Trust Boundary

Untrusted pull-request verification must use `pull_request`, run PR-controlled source with read-only repository permissions, and avoid registry publication credentials, signing secrets, cloud credentials, repository mutation, `PlatformService` updates, and deployable external publication.

PR workflows must not use `pull_request_target` to execute PR-controlled build code. Their eventual scope is to prove source tests, container buildability, SBOM generation, and vulnerability evidence without publishing a deployable artifact.

## Trusted Publication Boundary

Publication is separate from PR verification. Trusted publication may occur only from an explicitly trusted event such as protected `main`, a release or tag if later adopted, or a narrowly controlled manual dispatch.

A publication workflow may eventually receive registry write permission, attestation permission, and signing identity. Those permissions must be least-privilege and are not introduced during Stage 6A.

## Build vs Publish Separation

PR verification is not artifact publication.

The PR path proves build, test, and evidence generation without deployable publication. The trusted path rebuilds or otherwise establishes trusted artifact identity, publishes, records evidence, and returns the authoritative digest.

This separation protects secrets, isolates malicious PRs, preserves provenance integrity, protects the registry, and keeps a clean trust boundary between untrusted code review and trusted release activity.

## Artifact-Evidence Continuity

PR evidence is merge-safety evidence, not automatically authoritative evidence for a later published artifact. A protected-main publication build may produce a different image digest than a pull-request build, even when source content is similar.

The required continuity principle is:

```text
untrusted PR
-> build/test/evidence
-> merge eligibility

trusted publication source revision
-> trusted build or publication candidate
-> exact artifact identity
-> artifact-bound SBOM
-> artifact-bound vulnerability evidence
-> publication policy
-> trusted publication
-> authoritative digest
-> provenance or attestation bound to digest
-> Stage 5 repository + digest handoff
```

Stage 6C proves the source change is buildable, tests pass, representative container construction succeeds, SBOM generation works, vulnerability scanning works, policy can be evaluated, and no publication privileges are available. Its output must not be treated as authoritative supply-chain evidence for a different artifact rebuilt and published after merge.

Stage 6C1 establishes the local evidence engine. It installs repository-owned pinned Syft and Grype tooling, performs one application build into an exact Docker archive, uses the SHA-256 of the archive bytes as verification artifact identity, removes and reloads the archive for runtime correlation, and runs one Syft archive cataloging operation that emits two sibling SBOM serializations: CycloneDX JSON as the portable reviewer-facing SBOM, and Syft JSON as rich scanner-native inventory evidence. Grype scans the exact Docker archive directly because direct archive scanning preserves the same primary artifact identity while avoiding the current Go SBOM function-symbol warning seen when scanning serialized SBOMs. Direct archive vulnerability verification does not provide function-level reachability analysis, and no such capability is claimed. The repository vulnerability policy evaluates the Grype report, fails closed for malformed/tooling failures, retains complete evidence for legitimate blocking policy failures, and an evidence manifest plus sidecar checksum validates the procedural chain. This archive SHA-256 is not a registry digest, published digest, Stage 5 deployable digest, or authoritative registry identity.

Stage 6C2 is complete. It wires the evidence engine into untrusted `pull_request` CI with `contents: read`, no secrets, no publication credentials, a runner-portable Docker build/archive path, scope-classified conditional execution, retained artifacts, GitHub artifact digests, and the stable `Supply-chain PR validation` final gate. The workflow builds the GitHub pull-request merge ref, records base/head/merge source metadata, uploads validated evidence only from explicit paths, and keeps GitHub artifact digests distinct from the archive SHA-256 and any future registry digest. Relevant supply-chain pull requests prove `supply-chain-pr=true`, execute evidence generation, retain image and evidence artifacts, and pass the final gate. Irrelevant pull requests still start the workflow, prove `supply-chain-pr=false`, skip expensive evidence execution, create no supply-chain artifacts, and pass the final gate. Stage 6C is complete as PR build/test/SBOM/vulnerability verification, but its evidence remains merge-safety evidence and does not grant trusted publication authority.

Stage 6D must ensure the exact deployable artifact has an immutable digest, SBOM, and vulnerability evidence before that digest is ready for Stage 5 handoff. Stage 6A does not decide whether Stage 6D rebuilds on protected `main`, promotes an identical prebuilt OCI artifact while preserving its digest, or uses another safe design. It locks only this invariant: required evidence must refer to the exact published artifact digest.

Stage 6D1 establishes the local trusted-publication engine and contracts without live registry mutation. It locks GHCR repository naming for the representative supply-chain fixture, source-revision and registry-digest validation, attempt-aware non-authoritative candidate references, authoritative source-revision convenience tags, same-source rerun safety, publication evidence validation, and the machine-readable `image-reference.json` Stage 5 handoff shape. The first live GHCR attempt proved that workflow-created packages from this public repository are public, so the old private candidate quarantine model is retired. The active trust boundary is runner-local quarantine before any registry push, followed by verified public candidate staging in `ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture-candidates`; authoritative evidence and Stage 5 handoff use only `ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture`.

Stage 6D2 is complete and live-proven for the representative fixture. The candidate job performs exactly one local application build, local runtime proof, local SBOM generation, local Grype scanning, and local policy evaluation before GHCR authentication and candidate push. Local Docker image IDs and archive SHA-256 values are evidence only, not registry digest authority. Registry digest continuity begins after the verified public candidate exists, and successful authoritative publication requires candidate registry digest, verified scan target digest, authoritative digest, and handoff digest to match. The authoritative job downloads validated candidate evidence and is isolated behind the protected `authoritative-publication` GitHub Environment. Only after Environment approval may it perform the authenticated source-tag recheck, publish the authoritative tag from the exact candidate digest without rebuild, prove public package metadata, prove digest equality, prove anonymous pull-by-digest, validate authoritative evidence, and emit the Stage 5 handoff. Stage 6D does not create or configure the Environment, delete failed public candidates, alter package visibility, add a personal access token, implement provenance, implement attestations, sign artifacts, or mutate Stage 5 services.

## Trusted Publication Invariants

Trusted publication has two public registry roles:

- Candidate: verified public staging in `ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture-candidates`. A candidate is non-authoritative and never grants deployment eligibility or Stage 5 handoff by itself.
- Authoritative: the deployable publication in `ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture`. Stage 5 consumes only this repository by immutable digest.

Durable invariants:

- Authority requires the protected `authoritative-publication` Environment review.
- The authenticated authoritative recheck occurs after Environment approval and before registry mutation.
- Authority originates from the verified candidate digest, not from a rebuild.
- Candidate registry digest, verified post-push scan target digest, authoritative digest, and handoff digest must be equal.
- Anonymous authoritative registry verification is required before the handoff is valid.
- Stage 5 handoff is emitted only after authoritative evidence validates.
- Ambiguous, denied, rate-limited, server-error, malformed, network-failure, and digest-collision states fail closed.
- `latest`, `main`, and `stable` are not trusted publication tags for candidate or authoritative repositories.

The public state model distinguishes `PUBLIC_AUTHORITATIVE_EXISTS`, `PUBLIC_AUTHORITATIVE_ABSENT`, `PUBLIC_AUTHORITATIVE_UNOBSERVABLE`, and `PUBLIC_AUTHORITATIVE_FAILURE`. Unobservable is not absent. First-publication behavior showed that anonymous access to a never-created namespace may be unobservable; after the public authoritative repository exists, a missing source-specific tag can be classified as `404` / `MANIFEST_UNKNOWN` / `PUBLIC_AUTHORITATIVE_ABSENT`.

Authenticated collision handling is:

| State | Decision |
| --- | --- |
| Absent | Promotion eligible. |
| Exists with same digest | Verified idempotent handling. |
| Exists with different digest | Fail closed. |
| 401, 403, 429, 5xx, network failure, malformed, or unknown | Fail closed. |

## Trusted Publication Live Proof

The trusted publication milestone is `COMPLETE - LIVE PROVEN` for the successful protected-main run:

| Property | Live proof/result | Evidence identifier |
| --- | --- | --- |
| Source | Protected `main` | `398d171e6331c2d1c8cea307a7ae725cd47a1e51` |
| Workflow run | Success | [run 32476158117](https://github.com/Franklindot04/k8s-internal-developer-platform/actions/runs/32476158117) |
| Attempt | First attempt, no rerun | `1` |
| Application builds | One local application build | Candidate job success |
| Candidate digest | `sha256:11b7fc3a664eec61aa5833389deeba0e3f99f7ecbdeaa4aa817199bfc50f2b4a` | `candidate-398d171e6331c2d1c8cea307a7ae725cd47a1e51-run-32476158117-attempt-1` |
| Post-push scan digest | Same digest | `VERIFIED_CANDIDATE_POST_PUSH` |
| Environment approval | Required and used | `authoritative-publication` |
| Authenticated recheck | `404` / `MANIFEST_UNKNOWN` / `PUBLIC_AUTHORITATIVE_ABSENT` | Promotion eligible |
| Authoritative digest | Same digest | `sha-398d171e6331c2d1c8cea307a7ae725cd47a1e51` |
| Anonymous verification | Public authoritative digest verified | Authoritative repository by digest |
| Authoritative evidence artifact | Valid | `trusted-publication-authoritative-398d171e6331c2d1c8cea307a7ae725cd47a1e51-32476158117-1` |
| Stage 5 handoff | Valid authoritative digest handoff | `image-reference.json` |
| Overall conclusion | `COMPLETE - LIVE PROVEN` | Workflow success |

The successful Stage 5 handoff reference is:

```text
ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture@sha256:11b7fc3a664eec61aa5833389deeba0e3f99f7ecbdeaa4aa817199bfc50f2b4a
```

Stage 5 must not consume a candidate tag, candidate repository, authoritative tag-only reference, or local image ID.

The candidate post-push vulnerability evidence used Grype `0.117.0` with database metadata `2026-08-21T06:17:24Z`. The vulnerability report checksum is `466318643671536b6edc571622dc5ac999a80b394da31cc687f903a8d8aa2ef0`, the evidence source is `VERIFIED_CANDIDATE_POST_PUSH`, and the policy decision is `PASS`. The authoritative artifact is the same OCI digest as the verified candidate artifact, so authoritative evidence reuses the validated candidate post-push scanner metadata and vulnerability evidence. This is not an independent authoritative Grype rescan.

Live validation exposed several boundary and process-isolation defects during development. Each failed safely before the relevant downstream trust transition. The final architecture reflects corrections for first-publication public-state ambiguity, fail-closed state-classification control flow, repository-owned helper path independence, explicit policy artifact propagation across process boundaries, separation of candidate staging from authoritative collision checking, explicit candidate evidence metadata propagation, and fresh-runner independence for reused scanner metadata.

Historical registry artifacts remain forensic evidence only. The historical partial authority `sha-f23bd6b5f0ed5ac47411162e9516bd64d5c58dce` resolves to `sha256:be46dfd8d13254517024d3fbe158fd7a304c848c5b3129147d6682fd50bf8eea`, but it is `REGISTRY-VERIFIED` and `WORKFLOW-INCOMPLETE`; it is not a successful trusted publication. Historical candidates include `candidate-f23bd6b5f0ed5ac47411162e9516bd64d5c58dce-run-32436359458-attempt-1` at the same digest and `candidate-59a76860307bb46a135de5794b7380b0e11df59a-run-32434344588-attempt-1` at `sha256:83b96769b67bf19fd9fdc5a988a52d2d3ff292e1b067512d942596148d160cf1`.

## Registry Contract

Stage 6 requires an OCI-compatible registry, not a cloud-specific registry selected during Stage 6A. The future registry must support content-addressable digests, authenticated trusted publication, digest lookup, manageable CI credentials, and evidence/referrer support where practical.

GHCR is a plausible implementation candidate because the repository already uses GitHub Actions, but provider selection belongs to the Stage 6D publication design unless a later repository policy mandates a different choice. Stage 6A adds no GHCR-specific configuration.

## Private Registry Boundary

The Stage 4 Helm chart supports `imagePullSecrets`. Stage 5 `PlatformService` does not currently expose registry-auth intent. Private-registry developer self-service is classified as `FUTURE_PLATFORM_CAPABILITY`, not a Stage 6A blocker.

Existing `PlatformService` secret references are application runtime Secret references, not registry authentication.

## Reproducibility Principles

Stage 6 should extend the repository's existing reproducibility practices. Future build slices should prefer pinned action SHAs, pinned builder and tool versions, locked dependencies, pinned and checksummed installers, immutable or pinned base images where feasible, deterministic source revisions, and digest-addressed output.

Stage 6A does not claim bit-for-bit reproducible image builds. Later slices must prove the exact level of repeatability they implement.

## Base Image Boundary

Stage 6B uses one test-only Go fixture under `tests/fixtures/supply-chain-fixture/` to prove a repeatable build contract with pinned declared inputs. The fixture uses an official Go builder image pinned by immutable digest, a scratch runtime, linux/amd64 as the canonical target platform, no third-party application dependencies, and no registry publication. Its local image tag is only a mutable local convenience, and Docker's local image ID is not an authoritative registry digest.

## Required Evidence

Stage 6 completion requires these evidence categories:

- Build/test evidence: the representative artifact builds and passes its defined tests.
- Immutable artifact identity: a published container resolves to a digest.
- SBOM: a machine-readable SBOM exists for the exact deployable artifact digest.
- Vulnerability evidence: a scan or report exists for the exact deployable artifact digest or its digest-bound SBOM.
- Provenance/attestation: trusted publication produces provenance or attestation tied to the published image digest.

Stage 6A does not select SPDX versus CycloneDX. It also does not lock a vulnerability severity threshold. Threshold policy should be decided after Stage 6C produces real scan output and false-positive behavior is understood.

Future provenance must identify at least the trusted source repository, trusted publication source revision, workflow or builder identity, exact published image digest, and relevant build inputs. The trusted publication source revision must be the revision used for trusted publication, not implicitly an earlier pull-request head revision.

## Signing

Artifact signing is high-value supply-chain hardening, but signature enforcement is not required for Stage 6 completion. Stage 6E must evaluate keyless signing, attestation identity, registry/referrer compatibility, CI credential complexity, and solo-maintainability.

If keyless signing integrates cleanly with the chosen registry and trust model, it may be added. Otherwise, signing should be documented as later hardening.

## OCI Evidence Model

The image digest is the central identity. SBOM, provenance, vulnerability evidence, and optional signatures must bind back to that identity.

OCI referrers and attestations are preferred long-term when supported. CI artifacts may provide intermediate evidence before registry attachment is implemented.

## Stage 6 To Stage 5 Handoff

The initial handoff is:

```text
trusted Stage 6 publication
-> immutable image repository + digest
-> developer or platform author updates PlatformService
-> Stage 5 plan/generate/verify flow
```

The digest update may initially be manual. Automatic config pull-request creation is not Stage 6 core and must not be added during Stage 6A.

## Promotion Boundary

Artifact creation is not environment promotion. Stage 6 produces a trusted artifact and evidence. Stage 9 owns promotion between environments, including any development-to-staging or staging-to-production mechanics.

## Admission And Policy Boundary

Stage 6 proves evidence in CI and trusted publication. Stage 7 or later security stages may enforce allowed registries, signatures, provenance, admission policy, pod security, and Kyverno or policy-engine rules. Stage 6A does not implement Kubernetes admission.

## Governance Boundaries

Repository-local secret scanning is not currently implemented. It is classified as `NON_BLOCKING_HARDENING` or governance/security hygiene unless a later roadmap update assigns a more specific owner.

Dependency-update automation is not currently implemented. It is classified as `NON_BLOCKING_HARDENING`; Stage 6A does not add Dependabot or equivalent configuration.

Initial Stage 6 does not require multi-architecture publication. Multi-architecture support is `USEFUL_LATER`. The initial representative proof may target the architecture naturally supported by current CI and test infrastructure.

Caching is an optimization, not a Stage 6 architectural requirement. Future caches must preserve trust separation, correct invalidation, reproducibility, and no cross-trust secret leakage.

Stage 6 does not require semantic release, GitHub Release automation, changelog automation, or release-train mechanics. Trusted publication may initially be tied to protected `main` revisions.

## Failure Domains

PR verification blockers include source test failure, build failure, required evidence generation failure, and eventual vulnerability-policy failure.

Trusted publication blockers include rebuild failure, registry publication failure, digest resolution failure, inability to establish artifact-bound SBOM or vulnerability evidence for the artifact being published, provenance or attestation failure, and selected signing failure if signing later becomes part of trusted publication. Trusted publication must fail closed when required artifact-bound evidence cannot be established for the exact artifact being published.

Deployment and promotion failures belong outside Stage 6 unless they are caused by invalid digest handoff.

## Required-Check Governance

Any future PR-required Stage 6 workflow must follow the repository's established required-check pattern:

```text
always start
-> internal scope classification
-> conditional expensive work
-> stable always-reporting final gate
```

Stage 6A does not make any workflow required. Trusted publish workflows are not PR-required checks.

## Credential Model

PR verification must not receive publication credentials.

Trusted publication should use the minimum write scope needed. For the initial GHCR workflow, the built-in GitHub Actions token with job-local package write permission is preferred over a personal access token. OIDC, attestations, and signing remain outside the Stage 6D boundary.

No credentials are created during Stage 6A.

## Threat Model

| Threat | Stage 6 mitigation |
| --- | --- |
| Malicious PR | Run untrusted PR code without secrets, publication credentials, repository mutation, or deployable publication. |
| Mutable tag substitution | Keep Stage 5 deployment identity digest-based. |
| Compromised dependency | Use locks, SBOMs, vulnerability scanning, and future dependency automation. |
| Compromised base image | Prefer immutable base identity, scan outputs, and later rebuild policy. |
| Registry credential theft | Use least privilege and short-lived identity or OIDC where possible. |
| Artifact replacement | Use content digest identity and evidence bound to that digest. |
| Forged build provenance | Use trusted publication identity and digest-bound attestation. |
| Scan/publish mismatch | Use artifact-bound evidence, digest continuity, and trusted publication evidence for the exact published bits and digest. |
| Scan/deploy mismatch | Stage 5 consumes only the authoritative digest whose evidence was established during trusted publication. |

## Solo-Maintainability

Stage 6 intentionally avoids enterprise-heavy architecture without proportional value. High-value initial scope is one representative fixture, one PR verification path, one trusted publication path, immutable digest, SBOM, vulnerability evidence, provenance or attestation, and clear trust separation.

Initial Stage 6 should avoid multi-cloud registry abstraction, multiple application languages, multi-architecture publication, elaborate release automation, key-management infrastructure, Kubernetes admission duplication, and environment promotion.

## Slice Plan

### Stage 6A - Supply-Chain Architecture & Trust Contracts

Complete. Defines architecture and trust contracts. No software implementation.

### Stage 6B - Representative Build Fixture & Repeatable Build

Complete. Proves a minimal application source can be tested and repeatably built into a local container artifact with pinned declared inputs. No registry publication.

### Stage 6C - PR Build / Test / SBOM / Vulnerability Verification

Complete. Proves untrusted PR verification with no publication credentials, relevant-path evidence execution, irrelevant-path fast-path behavior, retained evidence artifacts, and a stable required-check-ready final gate.

### Stage 6D - Trusted OCI Publication & Immutable Digest

Complete and live-proven for the representative fixture. The protected-main workflow published a verified public candidate, passed the protected `authoritative-publication` Environment gate, promoted the exact candidate digest without rebuild, verified the authoritative digest anonymously, validated authoritative evidence, and emitted a digest-pinned Stage 5 handoff.

### Stage 6E - Provenance / Attestation

Not started. Binds trusted build provenance to the published digest and evaluates keyless signing.

## Definition Of Done

Stage 6 is complete when:

1. Representative source has a deterministic or repeatable build contract.
2. Source tests pass.
3. Container build succeeds.
4. Untrusted PRs cannot publish.
5. Trusted publication exists.
6. Published artifact has immutable digest.
7. Stage 5 can consume repository plus that same authoritative digest.
8. SBOM is generated for the deployable artifact digest.
9. Vulnerability evidence is generated for the deployable artifact digest.
10. Provenance or attestation binds trusted build or publication to the deployable artifact digest.
11. Required-check behavior remains governable.
12. No personal publication credentials are required where avoidable.
13. Documentation or runbooks explain build, publication, evidence, and digest handoff.
14. No environment-promotion logic is introduced.
15. No Kubernetes admission enforcement is introduced.

Signing is not mandatory unless Stage 6E explicitly adopts it based on evidence.
