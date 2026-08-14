# Trusted Publication Runbook

Stage 6D trusted publication produces an authoritative OCI registry digest for the representative supply-chain fixture and a machine-readable handoff for Stage 5.

## Current Status

Stage 6D1 is complete / merged and implements the local publication engine, contracts, validators, and tests.
It does not authenticate to GHCR, publish an image, create a package, or change package visibility.

Trusted publication boundary hardening is complete / merged.

Stage 6D2 is implemented for review. It adds the protected-main GHCR workflow and publication runtime, but the first live publication is not yet proven because the workflow must run only after protected merge to `main`.

## Publication Contract

The planned private candidate quarantine repository is:

```text
ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture-candidates
```

The planned authoritative publication repository is:

```text
ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture
```

The candidate repository is non-authoritative quarantine for unverified, verified-but-unpromoted, policy-blocked, and failed-attempt forensic candidates.
The authoritative repository is the only repository eligible for the Stage 5 image handoff.
These package names remain contracts until protected merge triggers the first live publication; the runbook does not claim either package exists yet.

The representative artifact is a test and supply-chain demonstration artifact.
It is not the platform control plane, developer portal, or production workload.

The trusted publication source is the protected `main` revision that triggers the future workflow.
The source revision must be the full 40-character lowercase Git SHA.

## Candidate And Authoritative References

The candidate tag format is:

```text
candidate-<source-sha>-run-<workflow-run-id>-attempt-<workflow-run-attempt>
```

Candidate references are non-authoritative.
They may remain in the registry for forensic review if verification or policy fails.
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

Successful publication requires these digests to be equal:

```text
build metadata digest
candidate registry digest
verified scan target digest
authoritative tag digest
handoff digest
```

Candidate and authoritative repositories intentionally differ.
Digest equality crosses the repository boundary; repository string equality is not part of the digest continuity invariant.

Before promotion, candidate verification may prove only:

```text
build metadata digest
candidate registry digest
verified scan target digest
```

That is a verified candidate, not a completed publication.

## Rerun Safety

If `sha-<source-sha>` already exists and resolves to the expected digest, the publication is idempotently acceptable.
If it resolves to a different digest, the workflow must fail closed and must not move the tag.

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

Trusted publication evidence should be retained for 90 days in the future workflow.
Failure evidence for a validated policy-blocked candidate may also be retained for 90 days.

## Visibility

Public GHCR visibility is recommended for the representative fixture because Stage 5 does not currently expose complete self-service private-registry authentication.
The candidate quarantine package must remain private.
The authoritative package is expected to be created private initially, then made public only after successful publication, package linkage audit, digest equality proof, and explicit governance approval.
Under the current GHCR visibility model, making the authoritative package public is a deliberate irreversible action.
Visibility is not changed by this implementation. Public visibility remains a later explicit governance operation after private publication evidence is reviewed.

## Stage 6D2 Live Proof Pending

The protected-main workflow authenticates with `GITHUB_TOKEN`, pushes candidates only to the candidate quarantine repository, verifies the candidate digest, runs SBOM and vulnerability policy on the exact candidate artifact, and promotes only a policy-approved digest to the authoritative repository.

The first live candidate publication must prove the candidate package exists, is linked to this repository, and remains private.
If the candidate package is not private, publication must stop before authoritative promotion.

The first authoritative publication must prove the authoritative package appears only after policy pass, is linked to this repository, and resolves to the same digest as the verified candidate before any handoff is emitted.
Promotion remains unproven until protected merge proves registry behavior, but the required boundary is:

```text
candidate_repository@verified_digest
-> authoritative_repository:sha-<source-sha>
-> independent authoritative digest inspection
-> authoritative digest == candidate digest
```

Publication runs use one trusted publication concurrency group.
The workflow does not use cancel-in-progress behavior for registry mutation.
The workflow does not claim strict commit-order guarantees; source-SHA-scoped tags and digest verification keep independent main publications from overwriting one another.

## Boundaries

Stage 6D does not create provenance, attestations, signing, environment promotion, admission enforcement, or automatic service updates.
Stage 6E owns provenance, attestation, and signing evaluation.
Stage 9 owns environment promotion.
