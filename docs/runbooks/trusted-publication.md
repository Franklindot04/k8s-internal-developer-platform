# Trusted Publication Runbook

Stage 6D trusted publication produces an authoritative OCI registry digest for the representative supply-chain fixture and a machine-readable handoff for Stage 5.

## Current Status

Stage 6D1 implements the local publication engine, contracts, validators, and tests.
It does not authenticate to GHCR, publish an image, create a package, change package visibility, or add the trusted publication workflow.

Stage 6D2 will add the protected-main GHCR workflow and first controlled live publication.

## Publication Contract

The planned registry repository is:

```text
ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture
```

The representative artifact is a test and supply-chain demonstration artifact.
It is not the platform control plane, developer portal, or production workload.

The trusted publication source is the protected `main` revision that triggers the future workflow.
The source revision must be the full 40-character lowercase Git SHA.

## Candidate And Authoritative References

The candidate tag format is:

```text
candidate-<source-sha>-run-<workflow-run-id>
```

Candidate references are non-authoritative.
They may remain in the registry for forensic review if verification or policy fails.

The authoritative source-revision tag format is:

```text
sha-<source-sha>
```

The source-revision tag is a convenience pointer.
The OCI registry digest is the authority.
Stage 5 handoff must use repository plus `sha256:<digest>`, not a tag.

## Digest Continuity

Successful publication requires these digests to be equal:

```text
build metadata digest
candidate registry digest
verified scan target digest
authoritative tag digest
handoff digest
```

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

## Visibility

Public GHCR visibility is recommended for the representative fixture because Stage 5 does not currently expose complete self-service private-registry authentication.
Visibility is not changed in Stage 6D1 and requires explicit Stage 6D2 governance before any mutation.

## Boundaries

Stage 6D does not create provenance, attestations, signing, environment promotion, admission enforcement, or automatic service updates.
Stage 6E owns provenance, attestation, and signing evaluation.
Stage 9 owns environment promotion.
