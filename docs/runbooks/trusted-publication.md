# Trusted Publication Runbook

Stage 6D trusted publication produces an authoritative OCI registry digest for the representative supply-chain fixture and a machine-readable handoff for Stage 5.

## Current Status

Stage 6D1 is complete / merged and implements the local publication engine, contracts, validators, and tests.
It established the publication contracts before live GHCR mutation.

Trusted publication boundary hardening is complete / merged.

Stage 6D2 is complete and live-proven. The successful protected-main proof run was `32476158117`, attempt `1`, for source revision `398d171e6331c2d1c8cea307a7ae725cd47a1e51`. The workflow completed successfully after one application build, verified public candidate staging, protected Environment approval, authenticated authoritative recheck, no-rebuild digest-pinned promotion, anonymous authoritative verification, validated authoritative evidence, and Stage 5 handoff.

The old private candidate quarantine contract is retired. The active design is runner-local quarantine, verified public GHCR candidate staging, and environment-gated authoritative publication.

## Publication Contract

The verified public candidate staging repository is:

```text
ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture-candidates
```

The authoritative publication repository is:

```text
ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture
```

The candidate repository is non-authoritative public staging for candidates that have already passed local runtime, SBOM, vulnerability scan, and policy verification.
The authoritative repository is the only repository eligible for the Stage 5 image handoff.
Unverified or policy-blocked images must remain runner-local and must not receive a GHCR candidate tag, candidate registry digest, authoritative state, or Stage 5 handoff.

The representative artifact is a test and supply-chain demonstration artifact.
It is not the platform control plane, developer portal, or production workload.

The trusted publication source is the protected `main` revision that triggers the workflow.
The source revision must be the full 40-character lowercase Git SHA.

## Candidate And Authoritative References

The candidate tag format is:

```text
candidate-<source-sha>-run-<workflow-run-id>-attempt-<workflow-run-attempt>
```

Candidate references are non-authoritative.
They may remain in the registry for forensic review only after local policy has passed and the candidate has been published as verified public staging.
Including the workflow run attempt prevents a later rerun from reusing the same candidate tag and overwriting the previous failed-attempt pointer.

The authoritative source-revision tag format is:

```text
sha-<source-sha>
```

The source-revision tag is a convenience pointer.
The OCI registry digest is the authority.
Stage 5 handoff must use repository plus `sha256:<digest>`, not a tag.
The Stage 5 handoff must reference the authoritative repository only; it must never reference the candidate quarantine repository.

## Digest Continuity

Local image IDs and Docker archive SHA-256 values are local execution evidence only. They are not OCI registry digests and must not be used as Stage 5 deployable identity.

Successful authoritative publication requires these registry-domain digests to be equal:

```text
candidate registry digest
verified scan target digest
authoritative tag digest
handoff digest
```

Candidate and authoritative repositories intentionally differ.
Digest equality crosses the repository boundary; repository string equality is not part of the digest continuity invariant.

Before authoritative promotion, candidate verification proves only:

```text
candidate registry digest
verified scan target digest
```

That is a verified candidate, not a completed publication.

## Rerun Safety

If `sha-<source-sha>` already exists and resolves to the expected digest, the publication is idempotently acceptable.
If it resolves to a different digest, the workflow must fail closed and must not move the tag.

The authenticated authoritative recheck runs after `authoritative-publication` Environment approval and before any authoritative registry mutation. `PUBLIC_AUTHORITATIVE_ABSENT` is promotion-eligible. `PUBLIC_AUTHORITATIVE_EXISTS` with the same digest is verified idempotent handling. `PUBLIC_AUTHORITATIVE_EXISTS` with a different digest fails closed. Authentication failure, authorization failure, rate limiting, server failure, network failure, malformed registry responses, unknown states, and unobservable states fail closed.

The current fixture build does not claim bit-for-bit OCI digest reproducibility across rebuilds.
The source-revision tag represents the first successful publication binding, not permission to republish rebuilt variants under the same tag.

## Evidence And Handoff

Successful publication evidence is recorded as:

```text
publication-evidence.json
publication-evidence.json.sha256
```

The Stage 5 handoff is:

```text
image-reference.json
```

The handoff is output only.
It must not mutate `services/**`, `PlatformService` files, generated values, Argo CD Applications, or environment configuration.

Trusted publication evidence is retained for 90 days by the workflow.
Failure evidence for a local policy-blocked build may also be retained for 90 days, but it must not contain a GHCR candidate digest because no candidate was published.

The successful proof retained authoritative evidence as:

```text
trusted-publication-authoritative-398d171e6331c2d1c8cea307a7ae725cd47a1e51-32476158117-1
```

The successful handoff digest was:

```text
ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture@sha256:11b7fc3a664eec61aa5833389deeba0e3f99f7ecbdeaa4aa817199bfc50f2b4a
```

Stage 5 must consume the authoritative repository by immutable digest. It must not consume a candidate tag, candidate repository, authoritative tag-only reference, or local image ID.

## Visibility

The candidate package is expected to be public after publication because it is verified public staging from a public repository workflow.
The authoritative package is also expected to be public, but creating or updating it is isolated behind the protected `authoritative-publication` GitHub Environment.
The workflow references that Environment, but this repository change does not create or configure it. The Environment must exist and be protected before merge.
The workflow must not mutate package visibility, add a personal access token, or rely on a helper repository to recreate private quarantine.

## Stage 6D2 Live Proof

The protected-main workflow performs one local application build with BuildKit SBOM/provenance disabled, runs runtime proof, Syft SBOM generation, Grype vulnerability scanning, and policy evaluation against the local artifact, and only then authenticates to GHCR for candidate publication.

The successful live proof showed the candidate package exists, is linked to this repository, and is public verified staging.
If local policy fails, candidate publication must not occur.

The authoritative job must not run until the `authoritative-publication` Environment is explicitly approved. The successful live proof used normal Environment approval for required reviewer `Franklindot04`; admin bypass remained disabled, and no Environment secrets or variables were required.

The authoritative publication proved the authoritative package is linked to this repository, resolves to the same digest as the verified candidate, is anonymously pullable by digest, and only then emits the Stage 5 handoff. The proven boundary is:

```text
candidate_repository@verified_digest
-> authoritative_repository:sha-<source-sha>
-> independent authoritative digest inspection
-> authoritative digest == candidate digest
```

The successful digest chain is:

```text
candidate registry artifact
-> post-push scan target
-> authoritative registry artifact
-> Stage 5 handoff
```

Every step used:

```text
sha256:11b7fc3a664eec61aa5833389deeba0e3f99f7ecbdeaa4aa817199bfc50f2b4a
```

Candidate post-push vulnerability evidence used Grype `0.117.0`, database metadata `2026-08-21T06:17:24Z`, evidence source `VERIFIED_CANDIDATE_POST_PUSH`, vulnerability report checksum `466318643671536b6edc571622dc5ac999a80b394da31cc687f903a8d8aa2ef0`, and policy decision `PASS`. Authoritative evidence reuses that validated candidate post-push scanner metadata because the candidate and authoritative OCI digests are equal. This is not an independent authoritative Grype rescan.

Historical failed or partial artifacts remain useful forensic evidence but are not part of the successful trust chain. The historical partial authority `sha-f23bd6b5f0ed5ac47411162e9516bd64d5c58dce` is `REGISTRY-VERIFIED` and `WORKFLOW-INCOMPLETE`, not a successful trusted publication.

Publication runs use one trusted publication concurrency group.
The workflow uses workflow-level `queue: max` so the full candidate-to-authoritative transaction, including the Environment approval wait, is serialized.
The workflow does not use cancel-in-progress behavior for registry mutation.
The tradeoff is that irrelevant protected-main pushes may briefly wait behind a publication transaction before scope classification exits; this is preferred over allowing overlapping registry mutation while an authoritative approval is pending.

## Boundaries

Trusted publication intentionally does not create mutable `latest`, `main`, or `stable` tags for candidate or authoritative repositories. Identity remains run-specific candidate tags, source-specific authoritative tags, and digest-pinned Stage 5 handoff.

Stage 6D does not create provenance, attestations, signing, environment promotion, admission enforcement, automatic service updates, broader deployment orchestration, or portal integration.
Stage 6E owns provenance, attestation, and signing evaluation.
Stage 9 owns environment promotion.
