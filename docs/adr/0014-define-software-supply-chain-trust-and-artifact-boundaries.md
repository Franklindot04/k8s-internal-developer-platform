# ADR 0014: Define Software Supply-Chain Trust And Artifact Boundaries

## Status

Accepted for Stage 6A review.

## Context

Stage 5 completed the developer self-service configuration boundary:

```text
developer intent
-> PlatformService validation
-> platform policy
-> deterministic Helm values
-> deterministic Argo CD Application
-> read-only plan
-> safe repository generation
-> read-only verify
```

That boundary intentionally stops at controlled repository artifacts. `PlatformService` requires `spec.image.repository` plus an immutable `sha256:<digest>`, but the trusted image digest currently enters the repository as explicit external input. The repository has no current application container build pipeline, registry publication pipeline, SBOM pipeline, image vulnerability scanner, provenance pipeline, or signing pipeline.

Stage 6 must therefore define the upstream software supply-chain path without changing the Stage 5 deployment contract, absorbing environment promotion, or implementing Kubernetes admission enforcement.

## Decision

Stage 6 owns the path from application source to trusted artifact identity:

```text
application source
-> verification
-> reproducible container build
-> immutable OCI artifact
-> supply-chain evidence
-> trusted publication
-> image digest
```

Stage 5 continues to consume only image repository plus digest. Mutable tags are not deployment identity.

This repository remains primarily a platform implementation, configuration, documentation, and test/integration fixture repository. It is not converted into a production application monorepo. Stage 6B may introduce one test-only representative build fixture solely to prove the supply-chain contract.

Stage 6 is language-neutral. The representative fixture may use one language later, but that implementation choice must not appear in the platform API contract.

PR verification and trusted publication are separate trust domains. PR verification runs untrusted source through `pull_request` with read-only permissions and no registry, signing, cloud, or repository-mutation credentials. It must not use `pull_request_target` to execute PR-controlled build code. Trusted publication may run only from explicitly trusted events such as protected `main`, a release or tag if later adopted, or narrowly controlled manual dispatch.

The authoritative deployable identity is the OCI image digest. Tags may exist for discovery, commit association, or release association, but Stage 5 must continue to deploy by digest.

Stage 6 requires an OCI-compatible registry, but Stage 6A does not select a provider. The future registry must support content-addressable digest identity, authenticated trusted publication, digest lookup, a manageable CI credential model, and evidence/referrer support where practical.

Stage 6 completion requires build/test evidence, immutable artifact identity, a machine-readable SBOM, vulnerability evidence, and provenance or attestation bound to the published digest. Future provenance must identify the trusted source repository, trusted publication source revision, workflow or builder identity, exact published image digest, and relevant build inputs.

Evidence generated during untrusted PR verification is merge-safety evidence. It proves the source change is buildable, tests pass, representative container construction succeeds, evidence generation mechanisms work, policy can be evaluated, and no publication privileges are available. It is not automatically authoritative evidence for a different artifact rebuilt or published later from a trusted event.

Trusted publication must establish evidence for the exact artifact digest it publishes. Stage 6A does not decide whether the later implementation rebuilds on protected `main`, promotes an identical prebuilt OCI artifact while preserving its digest, or uses another safe design. It requires that the immutable digest, SBOM, vulnerability evidence, and provenance or attestation all refer to the same deployable artifact digest before Stage 5 handoff.

Artifact signing is high-value hardening, but signature enforcement is not required for Stage 6 completion. Stage 6E must evaluate keyless signing, attestation identity, registry/referrer compatibility, CI credential complexity, and solo-maintainability before deciding whether signing belongs in Stage 6 or later hardening.

The initial Stage 6 to Stage 5 handoff is manual:

```text
trusted Stage 6 publication
-> immutable image repository + digest
-> developer or platform author updates PlatformService
-> Stage 5 plan/generate/verify flow
```

Automatic configuration pull requests are not Stage 6 core.

Kubernetes-side supply-chain enforcement belongs to Stage 7 or later security hardening. Environment promotion belongs to Stage 9.

## Rationale

The current Stage 5 digest contract is already the right deployment boundary. Weakening it to accept mutable tags would undermine the platform's immutable deployment model just as the supply-chain stage begins.

Separating PR verification from trusted publication protects secrets, avoids giving untrusted code registry or signing authority, and keeps provenance meaningful. A trusted artifact must come from a trusted event and identity, not merely from a pull request that happened to build. Because the trusted publication artifact may have a different digest from the PR artifact, trusted publication must re-establish or preserve artifact-bound evidence for the exact digest it publishes.

A language-neutral supply-chain contract matches the `PlatformService` API: the platform deploys OCI artifacts, not source-language internals. A representative fixture is still useful because SBOM generation, vulnerability scanning, provenance, and registry digest resolution need an executable build subject.

Keeping registry selection out of Stage 6A avoids hard-coding provider assumptions before the publication design proves credential and evidence requirements.

Deferring admission enforcement and environment promotion preserves the existing roadmap boundaries. Stage 6 produces trusted artifacts and evidence; later stages decide where and how to enforce that evidence during cluster admission and promotion.

## Consequences

Stage 6A produces architecture and trust contracts only. It does not add source fixtures, Dockerfiles, workflows, scanners, SBOM tooling, registry configuration, signing, provenance tooling, credentials, branch protection changes, Helm changes, PlatformService changes, Argo changes, or Kubernetes changes.

Stage 6B can focus narrowly on a representative fixture and repeatable local build contract. Stage 6C can add untrusted PR verification without publication credentials. Stage 6D can choose and implement trusted registry publication with immutable digest, SBOM, and vulnerability evidence for the exact published artifact. Stage 6E can bind provenance or attestation to the published digest and evaluate signing.

The initial Stage 6 completion target remains strong but maintainable for one maintainer: one representative fixture, one PR verification path, one trusted publication path, immutable digest, SBOM, vulnerability evidence, provenance or attestation, and clear handoff into Stage 5.

## Alternatives Considered

- Accept mutable tags in `PlatformService`: rejected because Stage 5 already establishes digest-based deployment identity.
- Implement publication in PR workflows: rejected because PR code is untrusted and must not receive deployable publication authority.
- Treat PR-generated evidence as authoritative for later publication: rejected because a trusted publication rebuild may produce a different digest; required evidence must bind to the exact published artifact.
- Convert this repository into a production application monorepo: rejected because the repository is a platform implementation and configuration repository; only a test fixture is needed for supply-chain proof.
- Pick a registry provider during Stage 6A: rejected because registry choice belongs with the trusted publication design.
- Require signature enforcement in Stage 6: rejected for now because signing value depends on registry support, attestation identity, credential complexity, and solo-maintainability.
- Add automatic `PlatformService` update pull requests in Stage 6: rejected because initial digest handoff can be manual and Git automation is a later platform capability.
- Add Kubernetes admission enforcement in Stage 6: rejected because policy/admission enforcement belongs to Stage 7 or later security hardening.
- Add environment promotion in Stage 6: rejected because promotion belongs to Stage 9.
